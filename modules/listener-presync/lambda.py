"""
Listener Pre-Sync Lambda
========================

Invoked by CodeDeploy as a `BeforeAllowTraffic` lifecycle hook during ECS
blue/green deployments. Fires AFTER the replacement (green) task set is
healthy in its target group, but BEFORE CodeDeploy atomically swaps the
production listener (HTTPS:443) to it.

Job: copy the green target group ARN onto the secondary listener
(HTTP:80), so when CodeDeploy then swaps 443 to green, both listeners
are already pointing at the same target group. No misalignment window,
zero downtime.

Environment variables (set by terraform):
  PROD_LISTENER_ARN      - the listener CodeDeploy is about to swap (HTTPS:443)
  SECONDARY_LISTENER_ARN - the listener that needs to follow it (HTTP:80)
"""

import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

elbv2 = boto3.client("elbv2")
codedeploy = boto3.client("codedeploy")


def _green_target_group_arn(deployment_id: str) -> str:
    """Resolve which target group is the replacement (green).

    BeforeAllowTraffic fires AFTER green tasks are healthy in their target
    group but BEFORE CodeDeploy swaps the prod listener. So at this moment:
      - prod listener (HTTPS:443) still points at the OLD (blue) target group
      - the OTHER target group in the pair is the replacement (green)

    CodeDeploy's GetDeployment API returns both target group NAMES (not ARNs).
    Match by membership in the current ARN string (the substring `/<name>/`
    appears between the path prefix and the random suffix). Then resolve the
    OTHER name to a full ARN.
    """
    info = codedeploy.get_deployment(deploymentId=deployment_id)["deploymentInfo"]
    pair = info["loadBalancerInfo"]["targetGroupPairInfoList"][0]
    target_groups = pair["targetGroups"]  # [{"name": "..-blue"}, {"name": "..-green"}]

    prod_listener_arn = os.environ["PROD_LISTENER_ARN"]
    cur_tg_arn = elbv2.describe_listeners(ListenerArns=[prod_listener_arn])["Listeners"][0]["DefaultActions"][0]["TargetGroupArn"]

    # ARN looks like .../targetgroup/<name>/<random-suffix> — check name as a substring.
    for tg in target_groups:
        name = tg["name"]
        if f"/{name}/" not in cur_tg_arn:
            # This is the replacement target group.
            described = elbv2.describe_target_groups(Names=[name])["TargetGroups"][0]
            return described["TargetGroupArn"]

    # Defensive fallback: shouldn't happen — CodeDeploy always returns 2 distinct TGs.
    raise RuntimeError(
        f"Could not identify replacement target group; current={cur_tg_arn}, "
        f"target_groups={[tg['name'] for tg in target_groups]}"
    )


def lambda_handler(event, context):
    deployment_id = event["DeploymentId"]
    hook_execution_id = event["LifecycleEventHookExecutionId"]

    logger.info("BeforeAllowTraffic hook for deployment %s", deployment_id)

    try:
        green_tg = _green_target_group_arn(deployment_id)
        secondary_listener = os.environ["SECONDARY_LISTENER_ARN"]

        logger.info("Pre-aligning secondary listener %s -> %s", secondary_listener, green_tg)

        elbv2.modify_listener(
            ListenerArn=secondary_listener,
            DefaultActions=[{"Type": "forward", "TargetGroupArn": green_tg}],
        )

        logger.info("Secondary listener aligned. Reporting Succeeded to CodeDeploy.")

        codedeploy.put_lifecycle_event_hook_execution_status(
            deploymentId=deployment_id,
            lifecycleEventHookExecutionId=hook_execution_id,
            status="Succeeded",
        )

        return {"status": "ok", "target_group_arn": green_tg}

    except Exception as exc:
        logger.exception("Failed to pre-align secondary listener")
        # Tell CodeDeploy we failed; it will roll back the deployment.
        codedeploy.put_lifecycle_event_hook_execution_status(
            deploymentId=deployment_id,
            lifecycleEventHookExecutionId=hook_execution_id,
            status="Failed",
        )
        raise
