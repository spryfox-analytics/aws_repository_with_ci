# A pipeline must not be created while its connection is not AVAILABLE, because it would never be
# started by Git events. The guard must not dead-lock a new project either: the first run has to
# create the connection, so that there is something to activate.

mock_provider "aws" {
  source = "./tests/mocks"
}

# The connection's ARN is unknown until it exists, so the status cannot be checked while
# planning: the first plan goes through even though the connection will start out PENDING.
run "first_plan_is_not_blocked" {
  command = plan
  module {
    source = "./tests/fixtures/first_run"
  }
  override_data {
    target = module.ci.data.aws_codestarconnections_connection.source
    values = { name = "my-provider", connection_status = "PENDING" }
  }
}

run "apply_after_activation_creates_the_pipeline" {
  command = apply
  module {
    source = "./tests/fixtures/first_run"
  }
  override_data {
    target = module.ci.data.aws_codestarconnections_connection.source
    values = { name = "my-provider", connection_status = "AVAILABLE" }
  }
  assert {
    condition     = module.ci.codepipeline_name == "my-service-codepipeline"
    error_message = "The pipeline must be created once the connection is available."
  }
}

run "existing_connection_that_is_not_available_blocks_the_plan" {
  command = plan
  variables {
    name = "my-service"
    source_repository = {
      connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
      repository_id  = "my-group/my-service"
    }
  }
  override_data {
    target = data.aws_codestarconnections_connection.source
    values = { name = "my-provider", connection_status = "PENDING" }
  }
  expect_failures = [aws_codepipeline.this]
}
