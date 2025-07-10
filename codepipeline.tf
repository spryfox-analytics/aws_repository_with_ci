locals {
  codepipeline_name = "${aws_codecommit_repository.this.repository_name}-codepipeline"
}

resource "aws_codepipeline" "this" {
  name     = local.codepipeline_name
  pipeline_type = "V2"
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
        BranchName     = var.default_branch_name
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
        configuration = try(action.value.codebuild_project_index, "") == "" ? {} : {
          ProjectName = [for index, codebuild_project in aws_codebuild_project.this : codebuild_project.arn][action.value.codebuild_project_index]
        }
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
