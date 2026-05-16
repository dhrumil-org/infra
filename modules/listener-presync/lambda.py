import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

elbv2 = boto3.client("elbv2")
codedeploy = boto3.client("codedeploy")


def lambda_handler(event, context):
    deployment_id = event["DeploymentId"]
    hook_execution_id = event["LifecycleEventHookExecutionId"]

    logger.info("AfterAllowTraffic hook for deployment %s", deployment_id)

    try:
        prod_listener_arn = os.environ["PROD_LISTENER_ARN"]
        secondary_listener_arn = os.environ["SECONDARY_LISTENER_ARN"]

        # Read the production listener's current target group. AfterAllowTraffic
        # fires after CodeDeploy swapped this, so it now points at the new live
        # task set's target group — exactly what we want on the secondary.
        prod_actions = elbv2.describe_listeners(ListenerArns=[prod_listener_arn])["Listeners"][0]["DefaultActions"]
        forward = next((a for a in prod_actions if a["Type"] == "forward"), None)
        if forward is None:
            raise RuntimeError(f"Production listener has no forward action: {prod_actions}")
        live_tg_arn = forward["TargetGroupArn"]

        # Check current secondary state; skip the modify call if already aligned.
        sec_actions = elbv2.describe_listeners(ListenerArns=[secondary_listener_arn])["Listeners"][0]["DefaultActions"]
        sec_forward = next((a for a in sec_actions if a["Type"] == "forward"), None)
        current_tg_on_secondary = sec_forward["TargetGroupArn"] if sec_forward else None

        if current_tg_on_secondary == live_tg_arn:
            logger.info("Secondary listener already aligned to %s — no change needed", live_tg_arn)
        else:
            logger.info("Aligning secondary listener %s: %s -> %s",
                        secondary_listener_arn, current_tg_on_secondary, live_tg_arn)
            elbv2.modify_listener(
                ListenerArn=secondary_listener_arn,
                DefaultActions=[{"Type": "forward", "TargetGroupArn": live_tg_arn}],
            )

        logger.info("Reporting Succeeded to CodeDeploy.")
        codedeploy.put_lifecycle_event_hook_execution_status(
            deploymentId=deployment_id,
            lifecycleEventHookExecutionId=hook_execution_id,
            status="Succeeded",
        )

        return {"status": "ok", "target_group_arn": live_tg_arn}

    except Exception:
        logger.exception("Failed to align secondary listener")
        # CodeDeploy will mark the deployment as failed and (since auto_rollback
        # has DEPLOYMENT_FAILURE listed) revert traffic back to blue.
        codedeploy.put_lifecycle_event_hook_execution_status(
            deploymentId=deployment_id,
            lifecycleEventHookExecutionId=hook_execution_id,
            status="Failed",
        )
        raise
