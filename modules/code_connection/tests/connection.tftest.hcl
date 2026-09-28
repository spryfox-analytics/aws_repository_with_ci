mock_provider "aws" {}

run "azure_devops" {
  command = apply
  variables {
    name          = "azure-devops"
    provider_type = "AzureDevOps"
  }
  assert {
    condition     = aws_codeconnections_connection.this.provider_type == "AzureDevOps"
    error_message = "Azure DevOps must be accepted."
  }
}

run "gitlab" {
  command = apply
  variables {
    name          = "gitlab"
    provider_type = "GitLab"
  }
  assert {
    condition     = aws_codeconnections_connection.this.provider_type == "GitLab"
    error_message = "GitLab must be accepted."
  }
}

run "rejects_unknown_provider" {
  command = plan
  variables {
    name          = "codecommit"
    provider_type = "CodeCommit"
  }
  expect_failures = [var.provider_type]
}

run "rejects_provider_and_host_together" {
  command = plan
  variables {
    name          = "both"
    provider_type = "GitLab"
    host_arn      = "arn:aws:codeconnections:eu-west-1:111111111111:host/example-0000000000"
  }
  expect_failures = [var.host_arn]
}
