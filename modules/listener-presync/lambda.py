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
    """Resolve which target group is the replacement (green) by asking CodeDeploy."""
    info = codedeploy.get_deployment(deploymentId=deployment_id)["deploymentInfo"]
    pair = info["loadBalancerInfo"]["targetGroupPairInfoList"][0]
    # CodeDeploy reports both target groups + which one currently serves prod
    target_groups = pair["targetGroups"]
    prod_tg_name = pair["prodTrafficRoute"].get("listenerArns", [None])[0]
    # Easier path: the "replacement" task set's target group is the one NOT
    # currently serving prod. CodeDeploy exposes targetGroups as [{name: ...}, ...]
    # but doesn't directly mark which is replacement. So instead, read the
    # current default action of the prod listener — that's the OLD/blue.
    # The OTHER one is green.
    prod_listener_arn = os.environ["PROD_LISTENER_ARN"]
    cur = elbv2.describe_listeners(ListenerArns=[prod_listener_arn])
    cur_tg = cur["Listeners"][0]["DefaultActions"][0]["TargetGroupArn"]

    other_names = [tg["name"] for tg in target_groups if cur_tg.endswith(tg["name"])]
    # The one whose name is in cur_tg is the "current" (blue). Swap to the other.
    for tg in target_groups:
        if not cur_tg.endswith(tg["name"]):
            # Resolve full ARN from name
            described = elbv2.describe_target_groups(Names=[tg["name"]])["TargetGroups"][0]
            return described["TargetGroupArn"]

    # Fallback: if for some reason both names appear in cur_tg, just stick with current
    return cur_tg


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
