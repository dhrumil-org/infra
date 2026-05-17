################################################################################
# Bedrock invocation logging — MOVED to deployments/shared/bedrock-logging
#
# Bedrock Model Invocation Logging is account-level (one config per region for
# the whole account). It used to live here, but it captures BOTH stage AND prod
# Bedrock traffic, so owning it from a single env's stack was misleading. It
# now lives in deployments/shared/bedrock-logging/.
#
# This file contains `removed` blocks (Terraform 1.7+) that release ownership
# of the resources from this stack's state WITHOUT destroying them in AWS.
# After the new shared stack imports them, this entire file can be deleted.
#
# Migration order:
#   1. terraform apply HERE          → state cleanup, no AWS resource changes
#   2. terraform apply in shared/bedrock-logging  → imports + KMS upgrade
#
# Note: the KMS key resources added to this file in commit 76b4095 were never
# applied to AWS, so they don't need `removed` blocks — Terraform will just
# notice the resource blocks are gone and produce no plan diff.
################################################################################

removed {
  from = aws_cloudwatch_log_group.bedrock_invocations
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role.bedrock_logging
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role_policy.bedrock_logging
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_bedrock_model_invocation_logging_configuration.this
  lifecycle {
    destroy = false
  }
}
