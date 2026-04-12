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
# CodePipeline — ECR Source → CodeDeploy Deploy
################################################################################

resource "aws_codepipeline" "this" {
  name     = "${var.project}-${var.env}-deploy-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  ############################################################################
  # Stage 1: Source — Triggers on ECR image push
  ############################################################################
  stage {
    name = "Source"

    action {
      name             = "ECR-Image"
      category         = "Source"
      owner            = "AWS"
      provider         = "ECR"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = var.ecr_repository_name
        ImageTag       = var.ecr_image_tag
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
      input_artifacts = ["source_output"]

      configuration = {
        ApplicationName                = var.codedeploy_app_name
        DeploymentGroupName            = var.codedeploy_deployment_group_name
        TaskDefinitionTemplateArtifact = "source_output"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "source_output"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "source_output"
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
          "s3:GetBucketVersioning",
          "s3:PutObject"
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
          "ecs:UpdateService"
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
