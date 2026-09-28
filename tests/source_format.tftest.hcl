# CodeBuild can clone only from some providers. Where it cannot, the source has to be a ZIP, and a
# requested clone must fail the plan instead of failing every build at the source download.

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name = "my-service"
  source_repository = {
    connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    repository_id  = "my-organization/my-project/my-service"
  }
}

run "azure_devops_gets_a_zip" {
  command = apply
  override_data {
    target = data.aws_codestarconnections_connection.source
    values = { name = "azure-devops", connection_status = "AVAILABLE", provider_type = "AzureDevOps" }
  }

  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].configuration.OutputArtifactFormat == "CODE_ZIP"
    error_message = "Azure DevOps sources must be handed over as a ZIP."
  }
  assert {
    condition     = !contains([for s in data.aws_iam_policy_document.codebuild.statement : s.sid], "UseSourceConnection")
    error_message = "Without a clone CodeBuild does not need the connection."
  }
}

run "azure_devops_rejects_a_clone" {
  command = plan
  variables {
    source_repository = {
      connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
      repository_id  = "my-organization/my-project/my-service"
      full_clone     = true
    }
  }
  override_data {
    target = data.aws_codestarconnections_connection.source
    values = { name = "azure-devops", connection_status = "AVAILABLE", provider_type = "AzureDevOps" }
  }
  expect_failures = [aws_codepipeline.this]
}

run "github_gets_a_clone" {
  command = apply
  override_data {
    target = data.aws_codestarconnections_connection.source
    values = { name = "github", connection_status = "AVAILABLE", provider_type = "GitHub" }
  }

  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].configuration.OutputArtifactFormat == "CODEBUILD_CLONE_REF"
    error_message = "GitHub sources must be cloned by default."
  }
}
