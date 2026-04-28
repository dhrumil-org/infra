################################################################################
# Application Load Balancer
################################################################################

resource "aws_lb" "this" {
  name               = "${var.project}-${var.env}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != "" ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = "${var.project}-${var.env}-alb"
      enabled = true
    }
  }

  tags = {
    Name = "${var.project}-${var.env}-alb"
  }
}

################################################################################
# Target Groups (Blue + Green for CodeDeploy canary)
################################################################################

resource "aws_lb_target_group" "blue" {
  name        = "${var.project}-${var.env}-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200-299"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project}-${var.env}-blue-tg"
  }
}

resource "aws_lb_target_group" "green" {
  name        = "${var.project}-${var.env}-green"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200-299"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project}-${var.env}-green-tg"
  }
}

################################################################################
# HTTPS Listener (primary — TLS 1.2 minimum for HIPAA)
################################################################################

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    ignore_changes = all
  }
}

################################################################################
# HTTP Listener — forward to blue target group
#
# Used by API Gateway HTTP_PROXY integration. API Gateway can't verify the
# ALB's TLS cert (cert is for api.stage.vocuone.ai, hostname is the ALB DNS),
# so we use HTTP on the API Gateway → ALB hop. Traffic stays inside AWS.
#
# Clients always reach us via API Gateway on HTTPS — they never hit port 80
# directly. The previous HTTP-to-HTTPS redirect is unnecessary now.
################################################################################

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # CodeDeploy manages this listener's default_action during blue/green
  # promotions (it's now listed in prod_traffic_route alongside HTTPS:443).
  # Terraform must ignore the runtime-flipping target group ARN, otherwise
  # every plan would try to revert it back to blue.
  lifecycle {
    ignore_changes = [default_action]
  }
}

################################################################################
# Test Listener (port 8443 for CodeDeploy canary traffic validation)
################################################################################

resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.this.arn
  port              = 8443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }
}
