terraform {
  required_providers {
    aws   = { source = "hashicorp/aws" }
    awscc = { source = "hashicorp/awscc" }
  }
}

locals {
  codepipeline_name = "${local.dashed_repository_path}-codepipeline"
}

resource "awscc_codepipeline_pipeline" "this" {
  name          = local.codepipeline_name
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_stores = [
    {
      region = var.aws_region
      artifact_store = {
        type     = "S3"
        location = aws_s3_bucket.codepipeline_artifact_store.bucket
      }
    }
  ]

  triggers = [
  {
    provider_type = "CodeStarSourceConnection"
    git_configuration = {
      source_action_name = "Source"

      # Start on ANY branch push
      push = [
        {
          branches = {
            includes = ["**"],
            excludes = ["__DUMMY_SINCE_ONE_ENTRY_REQUIRED_HERE__"]
          }
        }
      ]

      # Also start on any PR opened/updated/closed
      pull_request = [
        {
          branches = {
            includes = ["**"],
            excludes = ["__DUMMY_SINCE_ONE_ENTRY_REQUIRED_HERE__"]
          }
          # optional, but good to be explicit:
          events = ["OPEN", "UPDATED", "CLOSED"]
        }
      ]
    }
  }
]

  stages = [
    {
      name    = "Source"
      actions = [
        {
          name           = "Source"
          action_type_id = {
            category = "Source"
            owner    = "AWS"
            provider = "CodeStarSourceConnection"
            version  = "1"
          }
          output_artifacts = [
            { name = "SourceArtifact" }
          ]
          namespace = "SourceVariables"
          run_order = 1
        }
      ]
    },
    {
      name    = "Deploy"
      actions = [
        for idx, act in var.pipeline_actions : {
          name            = act.name
          action_type_id  = {
            category = act.category
            owner    = "AWS"
            provider = act.provider
            version  = "1"
          }
          input_artifacts = [
            for ia in act.input_artifacts : { name = ia }
          ]
          output_artifacts = [
            for oa in act.output_artifacts : { name = oa }
          ]
          run_order     = idx + 1
          configuration = jsonencode(
            merge(
              { ProjectName = aws_codebuild_project.this[act.codebuild_project_index].name },
              {
                EnvironmentVariables = jsonencode([
                  {
                    name  = "TRIGGER_BRANCH"
                    value = "#{SourceVariables.BranchName}"
                    type  = "PLAINTEXT"
                  }
                ])
              }
            )
          )
        }
      ]
    }
  ]

  tags = [
    { key = "Application", value = var.application          },
    { key = "Customer",    value = var.customer             },
    { key = "Name",        value = local.codepipeline_name  },
    { key = "Project",     value = var.project              },
  ]
}
