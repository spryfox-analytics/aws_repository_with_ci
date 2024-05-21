resource "aws_codebuild_project" "this" {
  for_each       = { for index, codebuild_project_index in tomap({ for index, action in var.pipeline_actions : index => try(action.codebuild_project_index, "") }) : index => codebuild_project_index if codebuild_project_index != "" }
  badge_enabled  = false
  build_timeout  = 60
  name           = "${aws_codecommit_repository.this.repository_name}-${var.pipeline_actions[each.key].name}-codebuild-project"
  queued_timeout = 480
  service_role   = aws_iam_role.codebuild.arn
  artifacts {
    encryption_disabled    = false
    name                   = "${aws_codecommit_repository.this.repository_name}-${var.pipeline_actions[each.key].name}"
    override_artifact_name = false
    packaging              = "NONE"
    type                   = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
    type                        = "LINUX_CONTAINER"
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
      name  = "CUSTOM_ENVIRONMENT"
      value = var.custom_environment
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
  }
  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
    s3_logs {
      encryption_disabled = false
      status              = "DISABLED"
    }
  }
  source {
    buildspec           = var.pipeline_actions[each.key].buildspec
    git_clone_depth     = 0
    insecure_ssl        = false
    report_build_status = false
    type                = "CODEPIPELINE"
  }
  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = "${aws_codecommit_repository.this.repository_name}-${var.pipeline_actions[each.key].name}-codebuild-project"
    Project     = var.project
  }
}
