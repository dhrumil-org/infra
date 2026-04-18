################################################################################
# CloudWatch Log Group (KMS encrypted, HIPAA retention)
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.project}-${var.env}-${var.service_name}"
  retention_in_days = 365
  kms_key_id        = var.log_kms_key_arn

  tags = {
    Name = "${var.project}-${var.env}-${var.service_name}-logs"
  }
}

################################################################################
# ECS Task Definition
################################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.project}-${var.env}-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      environment = var.environment_variables

      secrets = var.secrets

      healthCheck = var.container_health_check
    }
  ])

  tags = {
    Name = "${var.project}-${var.env}-${var.service_name}-task"
  }
}

################################################################################
# ECS Service (CodeDeploy controlled for canary deployments)
################################################################################

resource "aws_ecs_service" "this" {
  name            = "${var.project}-${var.env}-${var.service_name}"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  health_check_grace_period_seconds  = var.health_check_grace_period

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    base              = 1
    weight            = 100
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count,
      load_balancer,
    ]
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.service_name}-service"
  }
}
