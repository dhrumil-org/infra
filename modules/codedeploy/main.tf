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
# Deployment Group — Blue/Green with AllAtOnce traffic shift
################################################################################

resource "aws_codedeploy_deployment_group" "this" {
  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = "${var.project}-${var.env}-${var.service_name}-dg"
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  service_role_arn       = aws_iam_role.codedeploy.arn

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
  }

  blue_green_deployment_config {
    # CONTINUE_DEPLOYMENT: traffic auto-shifts to the replacement task set
    # the moment its target group reports healthy. Failures still trigger
    # auto_rollback_configuration on DEPLOYMENT_FAILURE — that gate stays.
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
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
        listener_arns = [
          var.https_listener_arn
        ]
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


