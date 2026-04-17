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
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
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
  bucket                 = aws_s3_bucket.artifacts.id
  key                    = "config/config.zip"
  source                 = data.archive_file.config.output_path
  etag                   = data.archive_file.config.output_md5
  server_side_encryption = "aws:kms"

  depends_on = [
    data.archive_file.config,
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
  # Stage 2: Deploy — CodeDeploy canary to ECS
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

  tags = {
    Name = "${var.project}-${var.env}-deploy-pipeline"
  }
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

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.project}-${var.env}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging",
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation",
          "s3:GetBucketAcl",
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = var.ecr_repository_arn
      },
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetApplication"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
          "ecs:TagResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = var.ecs_task_role_arns
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule"
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
