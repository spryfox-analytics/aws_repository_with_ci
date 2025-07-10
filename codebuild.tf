locals {
  repository_name = replace(var.gitlab_repository_path, "/", "-")
}

resource "aws_codebuild_project" "this" {
  for_each      = { for index, action in var.pipeline_actions : index => action if action.codebuild_project_index != "" }

  name          = "${local.repository_name}-${var.pipeline_actions[each.key].name}-codebuild-project"
  service_role  = aws_iam_role.codebuild.arn
  badge_enabled = false
  build_timeout = 60
  queued_timeout = 480

  artifacts {
    type                  = "CODEPIPELINE"
    packaging             = "NONE"
    name                  = "${local.repository_name}-${var.pipeline_actions[each.key].name}"
    override_artifact_name = false
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "CODE_ARTIFACT_DOMAIN"
      value = aws_codeartifact_repository.this.domain
    }
    environment_variable {
      name  = "CODE_ARTIFACT_REPOSITORY"
      value = aws_codeartifact_repository.this.repository
    }
    environment_variable {
      name  = "CURRENT_AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "ENVIRONMENT_AWS_ACCOUNT_ID"
      value = (try(var.pipeline_actions[each.key].environment, "") == "") ? "" : ((var.pipeline_actions[each.key].environment == "prod") ? var.aws_production_account_number : ((var.pipeline_actions[each.key].environment == "int") ? var.aws_integration_account_number : ((var.pipeline_actions[each.key].environment == "dev") ? var.aws_development_account_number : "")))
    }
    environment_variable {
      name  = "ECR_REPOSITORY_NAME"
      value = aws_ecr_repository.this.name
    }
    environment_variable {
      name  = "ENVIRONMENT"
      value = try(var.pipeline_actions[each.key].environment, "") == "" ? "" : var.pipeline_actions[each.key].environment
    }
    environment_variable {
      name  = "S3_CODEPIPELINE_ARTIFACT_STORE_URL"
      value = "s3://${aws_s3_bucket.codepipeline_artifact_store.bucket}"
    }
    dynamic "environment_variable" {
      for_each = var.additional_environment_variables
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }
  source {
    type              = "CODEPIPELINE"
    buildspec         = var.pipeline_actions[each.key].buildspec
    git_clone_depth   = 0
    report_build_status = false
    insecure_ssl      = false
  }
  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
    s3_logs {
      status = "DISABLED"
    }
  }

  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = "${local.repository_name}-${var.pipeline_actions[each.key].name}-codebuild"
    Project     = var.project
  }
}
