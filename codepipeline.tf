resource "aws_codepipeline" "this" {
  name          = local.names.pipeline
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      namespace        = "SourceVariables"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn        = var.source_repository.connection_arn
        FullRepositoryId     = var.source_repository.repository_id
        BranchName           = var.source_repository.branch
        OutputArtifactFormat = var.source_repository.full_clone ? "CODEBUILD_CLONE_REF" : "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Deploy"

    dynamic "action" {
      for_each = local.actions

      content {
        name             = action.value.name
        category         = action.value.category
        owner            = "AWS"
        provider         = action.value.provider
        version          = "1"
        run_order        = action.key + 1
        input_artifacts  = action.value.input_artifacts
        output_artifacts = action.value.output_artifacts

        configuration = action.value.provider == "CodeBuild" ? {
          ProjectName = aws_codebuild_project.this[action.value.name].name
          # Which commit a run builds is only known at run time, so it is handed over per execution.
          EnvironmentVariables = jsonencode([
            { name = "SOURCE_BRANCH_NAME", value = "#{SourceVariables.BranchName}", type = "PLAINTEXT" },
            { name = "SOURCE_COMMIT_ID", value = "#{SourceVariables.CommitId}", type = "PLAINTEXT" },
          ])
        } : (length(action.value.configuration) > 0 ? action.value.configuration : null)
      }
    }
  }

  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "Source"

      push {
        branches {
          includes = var.triggers.push_branches != null ? var.triggers.push_branches : [var.source_repository.branch]
        }
      }

      dynamic "pull_request" {
        for_each = length(var.triggers.pull_request_branches) > 0 ? [1] : []

        content {
          events = var.triggers.pull_request_events

          branches {
            includes = var.triggers.pull_request_branches
          }
        }
      }
    }
  }

  tags = merge(local.tags, { Name = local.names.pipeline })

  lifecycle {
    # When the connection is created in the same run, its ARN is unknown while planning, so this
    # is only evaluated during apply, after the connection exists. A first run therefore creates
    # the connection, leaving something to activate, and stops short of the pipeline alone.
    precondition {
      condition     = data.aws_codestarconnections_connection.source.connection_status == "AVAILABLE"
      error_message = <<-EOT
        The connection ${data.aws_codestarconnections_connection.source.name} is ${data.aws_codestarconnections_connection.source.connection_status}, not AVAILABLE.
        A pipeline created now would never be started by Git events, so it is held back.
        Activate the connection in the AWS console, then apply again:
        https://${local.region}.console.aws.amazon.com/codesuite/settings/connections?region=${local.region}
      EOT
    }
  }
}
