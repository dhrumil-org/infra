################################################################################
# CodeDeploy Application
################################################################################

resource "aws_codedeploy_app" "this" {
  name             = "${var.project}-${var.env}-${var.service_name}"
  compute_platform = "ECS"

  tags = {
    Name = "${var.project}-${var.env}-${var.service_name}-codedeploy"
  }
}

################################################################################
# Deployment Configuration — Canary 10% for 15 minutes
################################################################################

resource "aws_codedeploy_deployment_config" "canary" {
  deployment_config_name = "${var.project}-${var.env}-canary-10-15"
  compute_platform       = "ECS"

  traffic_routing_config {
    type = "TimeBasedCanary"

    time_based_canary {
      interval   = 15
      percentage = 10
    }
  }
}

################################################################################
# Deployment Group
################################################################################

resource "aws_codedeploy_deployment_group" "this" {
  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = "${var.project}-${var.env}-${var.service_name}-dg"
  # AllAtOnce: shifts 100% traffic immediately once green is healthy.
  # Switch to canary config for prod when blue side is a real app.
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  service_role_arn       = aws_iam_role.codedeploy.arn

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 0
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.ecs_service_name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.https_listener_arn]
      }

      test_traffic_route {
        listener_arns = [var.test_listener_arn]
      }

      target_group {
        name = var.blue_target_group_name
      }

      target_group {
        name = var.green_target_group_name
      }
    }
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.service_name}-deployment-group"
  }
}

################################################################################
# IAM Role for CodeDeploy
################################################################################

resource "aws_iam_role" "codedeploy" {
  name = "${var.project}-${var.env}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "codedeploy.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project}-${var.env}-codedeploy-role"
  }
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
