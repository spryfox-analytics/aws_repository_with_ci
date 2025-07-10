locals {
  codepipeline_name = "${replace(var.gitlab_repository_path, "/", "-")}-codepipeline"
}

resource "aws_codepipeline" "this" {
  name          = local.codepipeline_name
  pipeline_type = "V2"
  role_arn      = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifact_store.bucket
    type     = "S3"
  }

  # ── Trigger on every push, any branch ───────────────────────────────
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      # no 'branches' filter → every branch fires
      push {
        branches {
          include = ["*"]
          exclude = []
        }
      }
    }
  }

  stage {
    name = "Source"
    action {
      name       = "Source"
      category   = "Source"
      owner      = "AWS"
      provider   = "CodeStarSourceConnection"
      version    = "1"
      namespace  = "SourceVariables"       # fixed namespace for output vars

      configuration = {
        ConnectionArn     = aws_codestarconnections_connection.gitlab.arn
        FullRepositoryId  = var.gitlab_repository_path
        BranchName        = "main"  # used on manual runs
        DetectChanges     = true                    # enable webhook
      }

      output_artifacts = ["SourceArtifact"]
      run_order        = 1
    }
  }

  stage {
    name = "Deploy"

    dynamic "action" {
      for_each = var.pipeline_actions
      content {
        name            = action.value.name
        category        = action.value.category
        provider        = action.value.provider
        owner           = "AWS"
        version         = "1"
        input_artifacts  = action.value.input_artifacts
        output_artifacts = action.value.output_artifacts
        run_order       = action.key + 1

        # ── Launch your CodeBuild project, and override its env vars ──
        configuration = merge(
          { ProjectName = aws_codebuild_project.this[action.value.codebuild_project_index].name },
          {
            EnvironmentVariablesOverride = jsonencode([
              {
                name  = "TRIGGER_BRANCH"
                value = "#{SourceVariables.BranchName}"
                type  = "PLAINTEXT"
              }
            ])
          }
        )
      }
    }
  }

  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = local.codepipeline_name
    Project     = var.project
  }
}
