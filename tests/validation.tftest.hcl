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

run "rejects_unknown_environment" {
  command = plan
  variables {
    actions = [{ name = "deploy", environment = "staging" }]
  }
  expect_failures = [var.actions]
}

run "rejects_duplicate_action_names" {
  command = plan
  variables {
    actions = [{ name = "build" }, { name = "build" }]
  }
  expect_failures = [var.actions]
}

run "rejects_foreign_connection_arn" {
  command = plan
  variables {
    source_repository = {
      connection_arn = "arn:aws:codecommit:eu-west-1:111111111111:my-service"
      repository_id  = "my-service"
    }
  }
  expect_failures = [var.source_repository]
}

run "rejects_deployment_role_for_unknown_environment" {
  command = plan
  variables {
    environments    = { prod = "444444444444" }
    deployment_role = { environments = ["int"] }
  }
  expect_failures = [var.deployment_role]
}

run "rejects_invalid_name" {
  command = plan
  variables {
    name = "My_Service"
  }
  expect_failures = [var.name]
}

run "rejects_overlong_bucket_name" {
  command = plan
  variables {
    name = "a-very-long-service-name-that-exceeds-the-bucket-limit"
  }
  expect_failures = [aws_s3_bucket.artifacts]
}
