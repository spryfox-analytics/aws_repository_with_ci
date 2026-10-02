resource "aws_codebuild_project" "this" {
  for_each = local.codebuild_actions

  name           = "${local.names.codebuild_project_prefix}-${each.key}-codebuild-project"
  service_role   = aws_iam_role.codebuild.arn
  badge_enabled  = false
  build_timeout  = each.value.codebuild.build_timeout
  queued_timeout = each.value.codebuild.queued_timeout

  artifacts {
    type                   = "CODEPIPELINE"
    packaging              = "NONE"
    name                   = "${local.names.codebuild_project_prefix}-${each.key}"
    override_artifact_name = false
  }

  environment {
    compute_type                = each.value.codebuild.compute_type
    image                       = each.value.codebuild.image
    type                        = "LINUX_CONTAINER"
    privileged_mode             = each.value.codebuild.privileged_mode
    image_pull_credentials_type = "CODEBUILD"

    dynamic "environment_variable" {
      for_each = merge(
        {
          AWS_DEFAULT_REGION                 = local.region
          CURRENT_AWS_ACCOUNT_ID             = local.account_id
          S3_CODEPIPELINE_ARTIFACT_STORE_URL = "s3://${aws_s3_bucket.artifacts.bucket}"
        },
        var.ecr_repository.enabled ? { ECR_REPOSITORY_NAME = aws_ecr_repository.this[0].name } : {},
        local.source_directory != null ? { SOURCE_DIRECTORY = local.source_directory } : {},
        var.codeartifact_domain != null ? {
          CODE_ARTIFACT_DOMAIN     = aws_codeartifact_repository.this[0].domain
          CODE_ARTIFACT_REPOSITORY = aws_codeartifact_repository.this[0].repository
        } : {},
        each.value.environment != null ? {
          ENVIRONMENT                = each.value.environment
          ENVIRONMENT_AWS_ACCOUNT_ID = var.environments[each.value.environment]
        } : {},
        var.environment_variables,
        each.value.codebuild.environment_variables,
      )

      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  source {
    type                = "CODEPIPELINE"
    buildspec           = each.value.buildspec
    git_clone_depth     = 0
    report_build_status = false
    insecure_ssl        = false
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
    s3_logs {
      status = "DISABLED"
    }
  }

  tags = merge(local.tags, { Name = "${local.names.codebuild_project_prefix}-${each.key}-codebuild-project" })
}
