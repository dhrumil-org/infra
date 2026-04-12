resource "aws_kms_key" "this" {
  for_each = var.keys

  description             = each.value.description
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = each.value.policy

  tags = {
    Name = "${var.project}-${var.env}-${each.key}"
  }
}

resource "aws_kms_alias" "this" {
  for_each = var.keys

  name          = "alias/${var.project}-${var.env}-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}
