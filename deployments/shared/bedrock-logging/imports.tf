################################################################################
# One-time import blocks — migrating ownership from deployments/bedrock/stage
# into this stack.
#
# Order of operations for the migration:
#   1. cd deployments/bedrock/stage && terraform apply
#      → applies the `removed` blocks (now in invocation-logging.tf) so the
#        OLD state stops tracking these resources WITHOUT destroying them
#        in AWS. The KMS key/alias added in commit 76b4095 had not been
#        applied yet, so they're also reverted in stage.
#
#   2. cd deployments/shared/bedrock-logging && terraform init && terraform apply
#      → runs these import blocks to claim ownership of the existing AWS
#        resources, creates the new KMS key/alias, and updates the log group
#        with kms_key_id + 7-year retention in place.
#
# After both applies succeed, this file (imports.tf) can be deleted in a
# follow-up cleanup commit. Leaving it in is harmless — Terraform skips
# import blocks for resources that are already in state.
################################################################################

import {
  to = aws_cloudwatch_log_group.bedrock_invocations
  id = "/aws/bedrock/${var.project}-invocations"
}

import {
  to = aws_iam_role.bedrock_logging
  id = "${var.project}-bedrock-logging"
}

import {
  to = aws_iam_role_policy.bedrock_logging
  id = "${var.project}-bedrock-logging:write-invocation-logs"
}

# Model invocation logging is a regional singleton. Its import ID is the
# region string (per AWS provider docs for
# aws_bedrock_model_invocation_logging_configuration).
import {
  to = aws_bedrock_model_invocation_logging_configuration.this
  id = var.aws_region
}
