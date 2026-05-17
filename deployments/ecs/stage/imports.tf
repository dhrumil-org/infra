################################################################################
# One-time import blocks — claiming ownership of RDS-auto-created log groups
#
# RDS creates /aws/rds/instance/<id>/postgresql on first log export with the
# AWS-owned default key and no retention. Now that modules/rds/main.tf
# pre-creates these groups with our `logs` CMK + 7-year retention, we have
# to import the existing AWS resource so Terraform takes ownership rather
# than erroring with ResourceAlreadyExistsException.
#
# The `upgrade` log group is NOT imported because no RDS upgrade has occurred
# yet — AWS hasn't created that group. Terraform will create it fresh.
#
# After `terraform apply` succeeds and the import lands in state, this file
# can be deleted in a follow-up cleanup commit. Leaving it in is harmless
# (Terraform skips import blocks for resources already in state).
################################################################################

import {
  to = module.rds.aws_cloudwatch_log_group.postgresql
  id = "/aws/rds/instance/${var.project}-${var.env}-db/postgresql"
}
