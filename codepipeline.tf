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

  # ── webhook trigger on every branch ────────────────────────────────
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = ["**"]              # every branch
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
      namespace  = "SourceVariables"

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.gitlab.arn
        FullRepositoryId = var.gitlab_repository_path
        BranchName       = "main"  # fallback for manual runs
        DetectChanges    = true                     # enable webhook
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
        name             = action.value.name
        category         = action.value.category
        provider         = action.value.provider
        owner            = "AWS"
        version          = "1"
        input_artifacts  = action.value.input_artifacts
        output_artifacts = action.value.output_artifacts
        run_order        = action.key + 1

        configuration = merge(
          {
            ProjectName = aws_codebuild_project.this[action.value.codebuild_project_index].name
          },
          {
            # ← CORRECT KEY for CodeBuild env vars
            EnvironmentVariables = jsonencode([
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
