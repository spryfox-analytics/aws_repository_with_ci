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
        OutputArtifactFormat = local.full_clone ? "CODEBUILD_CLONE_REF" : "CODE_ZIP"
      }
    }
  }

  dynamic "stage" {
    for_each = local.stages

    content {
      name = stage.value.name

      dynamic "before_entry" {
        for_each = local.skip_unchanged ? [1] : []

        content {
          condition {
            result = "SKIP"

            rule {
              name            = "SourceChanged"
              input_artifacts = ["SourceArtifact"]

              rule_type_id {
                category = "Rule"
                owner    = "AWS"
                provider = "LambdaInvoke"
                version  = "1"
              }

              configuration = {
                FunctionName = aws_lambda_function.change_check[0].function_name
                UserParameters = jsonencode({
                  pipeline  = local.names.pipeline
                  directory = local.source_directory
                  execution = "#{codepipeline.PipelineExecutionId}"
                })
              }
            }
          }
        }
      }

      dynamic "action" {
        for_each = stage.value.actions

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
  }

  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "Source"

      push {
        branches {
          includes = var.triggers.push_branches != null ? var.triggers.push_branches : [var.source_repository.branch]
        }

        dynamic "file_paths" {
          for_each = local.trigger_file_paths

          content {
            includes = file_paths.value.includes
            excludes = file_paths.value.excludes
          }
        }
      }

      dynamic "pull_request" {
        for_each = length(var.triggers.pull_request_branches) > 0 ? [1] : []

        content {
          events = var.triggers.pull_request_events

          branches {
            includes = var.triggers.pull_request_branches
          }

          dynamic "file_paths" {
            for_each = local.trigger_file_paths

            content {
              includes = file_paths.value.includes
              excludes = file_paths.value.excludes
            }
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

    precondition {
      condition     = !local.full_clone || local.codebuild_can_clone
      error_message = "CodeBuild cannot clone from ${data.aws_codestarconnections_connection.source.provider_type}, so source_repository.full_clone must not be true. Builds receive a ZIP of the commit instead, which does not keep executable bits; set them in the build, e.g. with RUN chmod +x in the Dockerfile."
    }
  }
}
