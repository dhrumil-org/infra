################################################################################
# S3 Artifact Bucket for CodePipeline
################################################################################

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project}-${var.env}-pipeline-artifacts-${var.aws_account_id}"

  tags = {
    Name = "${var.project}-${var.env}-pipeline-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# Generate taskdef.json and appspec.yaml, zip and upload to S3
################################################################################

resource "local_file" "taskdef" {
  content = templatefile("${path.module}/taskdef.json.tpl", {
    task_family           = var.task_family
    task_cpu              = var.task_cpu
    task_memory           = var.task_memory
    execution_role_arn    = var.execution_role_arn
    task_role_arn         = var.task_role_arn
    container_name        = var.container_name
    container_port        = var.container_port
    log_group             = var.log_group
    aws_region            = var.aws_region
    environment_vars_json = jsonencode(var.environment_variables)
    secrets_json          = jsonencode(var.secrets)
  })
  filename = "${path.module}/generated/taskdef.json"
}

resource "local_file" "appspec" {
  content = templatefile("${path.module}/appspec.yaml.tpl", {
    container_name = var.container_name
    container_port = var.container_port
  })
  filename = "${path.module}/generated/appspec.yaml"
}

data "archive_file" "config" {
  type        = "zip"
  output_path = "${path.module}/generated/config.zip"

  source {
    content  = local_file.taskdef.content
    filename = "taskdef.json"
  }

  source {
    content  = local_file.appspec.content
    filename = "appspec.yaml"
  }
}

resource "aws_s3_object" "config" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "config/config.zip"
  source = data.archive_file.config.output_path
  etag   = data.archive_file.config.output_md5

  depends_on = [
    data.archive_file.config,
    aws_s3_bucket_versioning.artifacts,
    aws_s3_bucket_server_side_encryption_configuration.artifacts,
  ]
}

################################################################################
# CodePipeline — ECR Source + S3 Config → CodeDeploy Deploy
################################################################################

resource "aws_codepipeline" "this" {
  name     = "${var.project}-${var.env}-deploy-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  ############################################################################
  # Stage 1: Source — ECR image + S3 config files
  ############################################################################
  stage {
    name = "Source"

    action {
      name             = "ECR-Image"
      category         = "Source"
      owner            = "AWS"
      provider         = "ECR"
      version          = "1"
      output_artifacts = ["ecr_output"]
      run_order        = 1

      configuration = {
        RepositoryName = var.ecr_repository_name
        ImageTag       = var.ecr_image_tag
      }
    }

    action {
      name             = "Config-Files"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["config_output"]
      run_order        = 1

      configuration = {
        S3Bucket             = aws_s3_bucket.artifacts.bucket
        S3ObjectKey          = "config/config.zip"
        PollForSourceChanges = "false"
      }
    }
  }

  ############################################################################
  # Stage 2: Deploy — CodeDeploy to ECS (blue/green)
  ############################################################################
  stage {
    name = "Deploy"

    action {
      name            = "Deploy-ECS"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["config_output", "ecr_output"]

      configuration = {
        ApplicationName                = var.codedeploy_app_name
        DeploymentGroupName            = var.codedeploy_deployment_group_name
        TaskDefinitionTemplateArtifact = "config_output"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "config_output"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "ecr_output"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }

  # Post-deploy stage — re-align ALB port 80 with whatever target group port 443
  # is currently on. Needed because CodeDeploy ECS only manages one listener
  # in prod_traffic_route, leaving port 80 stuck on the empty old target group
  # after every blue/green swap. Skipped if alb_name is empty.
  dynamic "stage" {
    for_each = var.alb_name != "" ? [1] : []
    content {
      name = "Sync"

      action {
        name            = "Sync-Listeners"
        category        = "Build"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        input_artifacts = ["config_output"]

        configuration = {
          ProjectName = aws_codebuild_project.listener_sync[0].name
        }
      }
    }
  }

  tags = {
    Name = "${var.project}-${var.env}-deploy-pipeline"
  }
}

################################################################################
# CodeBuild — Listener Sync
#
# Runs `aws elbv2 modify-listener` to copy port 443's current target group ARN
# to port 80, so API Gateway HTTP_PROXY integration always reaches live tasks.
################################################################################

resource "aws_codebuild_project" "listener_sync" {
  count = var.alb_name != "" ? 1 : 0

  name         = "${var.project}-${var.env}-listener-sync"
  description  = "Re-align ALB port 80 with port 443 after CodeDeploy blue/green swap"
  service_role = aws_iam_role.listener_sync[0].arn
  build_timeout = 5

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "ALB_NAME"
      value = var.alb_name
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - set -e
            - echo "Looking up $ALB_NAME in $AWS_REGION..."
            - ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --region "$AWS_REGION" --query 'LoadBalancers[0].LoadBalancerArn' --output text)
            - LIVE_TG=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" --query 'Listeners[?Port==`443`].DefaultActions[0].TargetGroupArn' --output text)
            - HTTP_LISTENER=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" --query 'Listeners[?Port==`80`].ListenerArn' --output text)
            - echo "Aligning HTTP listener -> $LIVE_TG"
            - aws elbv2 modify-listener --listener-arn "$HTTP_LISTENER" --default-actions "Type=forward,TargetGroupArn=$LIVE_TG" --region "$AWS_REGION"
            - echo "Done."
    EOT
  }

  logs_config {
    cloudwatch_logs {
      group_name = "/aws/codebuild/${var.project}-${var.env}-listener-sync"
    }
  }

  tags = { Name = "${var.project}-${var.env}-listener-sync" }
}

resource "aws_iam_role" "listener_sync" {
  count = var.alb_name != "" ? 1 : 0
  name  = "${var.project}-${var.env}-listener-sync-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project}-${var.env}-listener-sync-role" }
}

resource "aws_iam_role_policy" "listener_sync" {
  count = var.alb_name != "" ? 1 : 0
  role  = aws_iam_role.listener_sync[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ELBSync"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:ModifyListener",
        ]
        Resource = "*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/codebuild/${var.project}-${var.env}-listener-sync*"
      },
    ]
  })
}

################################################################################
# EventBridge Rule — Trigger pipeline on ECR image push
################################################################################

resource "aws_cloudwatch_event_rule" "ecr_push" {
  name        = "${var.project}-${var.env}-ecr-push-trigger"
  description = "Trigger CodePipeline when new image is pushed to ECR"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type     = ["PUSH"]
      result          = ["SUCCESS"]
      repository-name = [var.ecr_repository_name]
      image-tag       = [var.ecr_image_tag]
    }
  })

  tags = {
    Name = "${var.project}-${var.env}-ecr-push-trigger"
  }
}

resource "aws_cloudwatch_event_target" "codepipeline" {
  rule     = aws_cloudwatch_event_rule.ecr_push.name
  arn      = aws_codepipeline.this.arn
  role_arn = aws_iam_role.eventbridge.arn
}

################################################################################
# IAM Role — CodePipeline
################################################################################

resource "aws_iam_role" "codepipeline" {
  name = "${var.project}-${var.env}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project}-${var.env}-codepipeline-role"
  }
}

################################################################################
# AWS Managed Policies — CodePipeline needs broad access
#
# Custom scoped policies fail due to IAM propagation delays on new roles
# and CodePipeline's internal resource access patterns. AWS managed policies
# are pre-cached and work immediately.
################################################################################

resource "aws_iam_role_policy_attachment" "codepipeline_s3" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_ecr" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "codepipeline_kms" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
}

resource "aws_iam_role_policy_attachment" "codepipeline_codedeploy" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployFullAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_ecs" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

# Custom policy only for PassRole + ELB (not in managed policies)
resource "aws_iam_role_policy" "codepipeline_extra" {
  name = "${var.project}-${var.env}-codepipeline-extra"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = var.ecs_task_role_arns
      },
      {
        Sid    = "ELB"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeBuildInvoke"
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds",
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# IAM Role — EventBridge (to trigger CodePipeline)
################################################################################

resource "aws_iam_role" "eventbridge" {
  name = "${var.project}-${var.env}-eventbridge-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project}-${var.env}-eventbridge-pipeline-role"
  }
}

resource "aws_iam_role_policy" "eventbridge" {
  name = "${var.project}-${var.env}-eventbridge-pipeline-policy"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "codepipeline:StartPipelineExecution"
      Resource = aws_codepipeline.this.arn
    }]
  })
}
