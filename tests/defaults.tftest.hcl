mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name = "my-service"
  source_repository = {
    connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    repository_id  = "my-group/my-service"
  }
}

run "names_are_derived_from_name" {
  command = apply

  assert {
    condition     = aws_codepipeline.this.name == "my-service-codepipeline"
    error_message = "Unexpected pipeline name: ${aws_codepipeline.this.name}"
  }
  assert {
    condition     = aws_s3_bucket.artifacts.bucket == "my-service-artifacts-111111111111"
    error_message = "Unexpected bucket name: ${aws_s3_bucket.artifacts.bucket}"
  }
  assert {
    condition     = aws_ecr_repository.this[0].name == "my-service"
    error_message = "Unexpected ECR repository name."
  }
  assert {
    condition     = aws_iam_role.codebuild.name == "MyServiceCodebuildRole" && aws_iam_role.codepipeline.name == "MyServiceCodepipelineRole"
    error_message = "Unexpected IAM role names: ${aws_iam_role.codebuild.name}, ${aws_iam_role.codepipeline.name}"
  }
  assert {
    condition     = tolist(keys(aws_codebuild_project.this)) == tolist(["build"]) && aws_codebuild_project.this["build"].name == "my-service-build-codebuild-project"
    error_message = "Expected exactly the default build project."
  }
}

run "zip_source_on_request" {
  command = apply
  variables {
    source_repository = {
      connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
      repository_id  = "my-group/my-service"
      full_clone     = false
    }
  }

  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].configuration.OutputArtifactFormat == "CODE_ZIP"
    error_message = "full_clone = false must hand over a ZIP."
  }
  assert {
    condition     = !contains([for s in data.aws_iam_policy_document.codebuild.statement : s.sid], "UseSourceConnection")
    error_message = "Without a clone CodeBuild does not need the connection."
  }
}

run "source_and_trigger_defaults" {
  command = apply

  assert {
    condition     = aws_codepipeline.this.pipeline_type == "V2"
    error_message = "Pipelines must be V2 to support triggers."
  }
  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].configuration.OutputArtifactFormat == "CODEBUILD_CLONE_REF"
    error_message = "The source must be a Git clone by default, so that executable bits survive."
  }
  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].configuration.BranchName == "main"
    error_message = "The source branch must default to main."
  }
  assert {
    condition     = aws_codepipeline.this.trigger[0].git_configuration[0].push[0].branches[0].includes == tolist(["main"])
    error_message = "Pushes must by default trigger only for the source branch."
  }
  assert {
    condition     = length(aws_codepipeline.this.trigger[0].git_configuration[0].pull_request) == 0
    error_message = "Pull requests must not trigger by default."
  }
}

run "optional_parts_are_off_by_default" {
  command = apply

  assert {
    condition     = length(aws_codeartifact_repository.this) == 0
    error_message = "No CodeArtifact repository without a domain."
  }
  assert {
    condition     = length(aws_s3_bucket_policy.artifacts) == 0 && length(aws_s3_access_point.artifacts) == 0 && length(aws_s3_bucket_public_access_block.artifacts) == 0
    error_message = "The artifact bucket must stay private by default."
  }
  assert {
    condition     = contains([for s in data.aws_iam_policy_document.codebuild.statement : s.sid], "UseSourceConnection")
    error_message = "CodeBuild clones through the connection by default, so it needs to use it."
  }
  assert {
    condition     = !contains([for s in data.aws_iam_policy_document.codebuild.statement : s.sid], "AssumeDeploymentRole")
    error_message = "No deployment role without environments."
  }
}

run "pipeline_role_may_use_the_connection_under_both_prefixes" {
  command = apply

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.codepipeline.statement :
      s.sid == "UseSourceConnection" && contains(s.actions, "codeconnections:UseConnection") && contains(s.actions, "codestar-connections:UseConnection")
    ])
    error_message = "The pipeline role needs UseConnection under both service prefixes."
  }
}
