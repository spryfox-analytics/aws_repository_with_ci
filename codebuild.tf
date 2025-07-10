resource "aws_codebuild_project" "this" {
  for_each      = { for index, action in var.pipeline_actions : index => action if action.codebuild_project_index != "" }

  name          = "${replace(var.gitlab_repository_path, "/", "-")}-${var.pipeline_actions[each.key].name}-codebuild-project"
  service_role  = aws_iam_role.codebuild.arn
  badge_enabled = false
  build_timeout = 60
  queued_timeout = 480

  artifacts {
    type                  = "CODEPIPELINE"
    packaging             = "NONE"
    name                  = "${replace(var.gitlab_repository_path, "/", "-")}-${var.pipeline_actions[each.key].name}"
    override_artifact_name = false
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    dynamic "environment_variable" {
      for_each = concat(
        [
          // always‐present vars
          { name = "AWS_DEFAULT_REGION",               value = var.aws_region },
          { name = "CODE_ARTIFACT_DOMAIN",             value = aws_codeartifact_repository.this.domain },
          { name = "CODE_ARTIFACT_REPOSITORY",         value = aws_codeartifact_repository.this.repository },
          { name = "CURRENT_AWS_ACCOUNT_ID",           value = data.aws_caller_identity.current.account_id },
          { name = "ECR_REPOSITORY_NAME",              value = aws_ecr_repository.this.name },
          { name = "S3_CODEPIPELINE_ARTIFACT_STORE_URL", value = "s3://${aws_s3_bucket.codepipeline_artifact_store.bucket}" }
        ],
        // optional ENVIRONMENT vars (only when environment is non-null/non-empty)
        var.pipeline_actions[each.key].environment != null && var.pipeline_actions[each.key].environment != ""
          ? [
              {
                name  = "ENVIRONMENT",
                value = var.pipeline_actions[each.key].environment
              },
              {
                name  = "ENVIRONMENT_AWS_ACCOUNT_ID",
                value = lookup({
                  dev  = var.aws_development_account_number
                  int  = var.aws_integration_account_number
                  prod = var.aws_production_account_number
                }, var.pipeline_actions[each.key].environment, "")
              }
            ]
          : [],
        // extra user‐supplied vars
        [for key, val in var.additional_environment_variables : {
          name  = key
          value = val
        }]
      )

      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
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
    Name        = "${replace(var.gitlab_repository_path, "/", "-")}-${var.pipeline_actions[each.key].name}-codebuild"
    Project     = var.project
  }
}
