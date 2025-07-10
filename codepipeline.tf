locals {
  # Map of exactly one branch if ["all"], else map of the list they supplied
  pipeline_branches = var.trigger_branches == ["all"] ? { for b in [var.default_branch_name] : b => b } : { for b in var.trigger_branches : b => b }
}

resource "aws_codepipeline" "this" {
  for_each = local.pipeline_branches
  name     = "${aws_codecommit_repository.this.repository_name}-${each.key}-codepipeline"
  role_arn = aws_iam_role.codepipeline.arn
  artifact_store {
    location = aws_s3_bucket.codepipeline_artifact_store.bucket
    type     = "S3"
  }
  stage {
    name = "Source"
    action {
      name     = "Source"
      category = "Source"
      owner    = "AWS"
      provider = "CodeCommit"
      version  = "1"
      configuration = {
        RepositoryName = aws_codecommit_repository.this.repository_name
        BranchName     = each.key  # per-pipeline branch
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
        run_order       = action.key + 1
        input_artifacts = action.value.input_artifacts
        output_artifacts = action.value.output_artifacts
        configuration = merge(
          try(action.value.codebuild_project_index, "") == "" ? {} : {
            ProjectName = aws_codebuild_project.this[action.value.codebuild_project_index].arn
          },
          {
            EnvironmentVariablesOverride = jsonencode([
              {
                name  = "TRIGGER_BRANCH"
                value = each.key
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
    Name        = each.value
    Project     = var.project
  }
}
