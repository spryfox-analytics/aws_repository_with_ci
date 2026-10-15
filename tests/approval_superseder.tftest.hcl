mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name = "my-infrastructure"
  source_repository = {
    connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    repository_id  = "my-organization/my-project/my-infrastructure"
  }
  environments = {
    dev  = "222222222222"
    int  = "333333333333"
    prod = "444444444444"
  }
  stages = [
    { name = "Dev", actions = [{ name = "apply-dev", environment = "dev" }] },
    {
      name = "Int"
      actions = [
        { name = "plan-int", environment = "int" },
        { name = "approve-int", category = "Approval", provider = "Manual" },
        { name = "apply-int", environment = "int" },
      ]
    },
    {
      name = "Prod"
      actions = [
        { name = "plan-prod", environment = "prod" },
        { name = "approve-prod", category = "Approval", provider = "Manual" },
        { name = "apply-prod", environment = "prod" },
      ]
    },
  ]
}

run "off_by_default" {
  command = apply

  assert {
    condition     = length(aws_lambda_function.approval_superseder) == 0 && length(aws_cloudwatch_event_rule.approval_superseder) == 0
    error_message = "Without supersede_waiting_approvals the module must not create the superseder."
  }
  assert {
    condition     = aws_codepipeline.this.execution_mode == "SUPERSEDED"
    error_message = "The pipeline must keep CodePipeline's default execution mode SUPERSEDED."
  }
}

run "one_function_gates_every_approval_by_the_stage_in_front_of_it" {
  command = apply
  variables {
    supersede_waiting_approvals = true
  }

  assert {
    condition     = length(aws_lambda_function.approval_superseder) == 1 && aws_lambda_function.approval_superseder[0].function_name == "my-infrastructure-approval-superseder"
    error_message = "One function per pipeline, named after it."
  }
  assert {
    condition = jsondecode(aws_lambda_function.approval_superseder[0].environment[0].variables.GATES) == [
      { previous_stage = "Dev", previous_action = "apply-dev", approval_stage = "Int", approval_action = "approve-int" },
      { previous_stage = "Int", previous_action = "apply-int", approval_stage = "Prod", approval_action = "approve-prod" },
    ]
    error_message = "Every approval is gated by the last action of the stage in front of its stage."
  }
  assert {
    condition     = aws_lambda_function.approval_superseder[0].environment[0].variables.PIPELINE_NAME == "my-infrastructure-codepipeline"
    error_message = "The function must know the pipeline."
  }
  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.approval_superseder[0].event_pattern)["$or"][0].detail.stage == ["Dev", "Int"]
    error_message = "The rule must fire when a run finishes a stage in front of an approval."
  }
  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.approval_superseder[0].event_pattern)["$or"][1].detail.action == ["approve-int", "approve-prod"]
    error_message = "The rule must fire when a run reaches an approval."
  }
  assert {
    condition     = aws_iam_role.approval_superseder[0].name == "MyInfrastructureApprovalSupersederRole"
    error_message = "The role follows iam_role_prefix."
  }
  assert {
    condition     = contains(data.aws_iam_policy_document.approval_superseder[0].statement[1].actions, "codepipeline:StopPipelineExecution")
    error_message = "The function must be allowed to stop executions."
  }
  assert {
    condition     = aws_lambda_permission.approval_superseder[0].principal == "events.amazonaws.com"
    error_message = "EventBridge must be allowed to invoke the function."
  }
}

run "an_approval_in_the_first_deploy_stage_is_gated_by_source" {
  command = apply
  variables {
    supersede_waiting_approvals = true
    stages = [
      {
        name = "Prod"
        actions = [
          { name = "plan-prod", environment = "prod" },
          { name = "approve-prod", category = "Approval", provider = "Manual" },
          { name = "apply-prod", environment = "prod" },
        ]
      },
    ]
  }

  assert {
    condition     = jsondecode(aws_lambda_function.approval_superseder[0].environment[0].variables.GATES) == [{ previous_stage = "Source", previous_action = "Source", approval_stage = "Prod", approval_action = "approve-prod" }]
    error_message = "An approval in the first deploy stage waits behind Source."
  }
}

run "nothing_to_supersede_without_approvals" {
  command = apply
  variables {
    supersede_waiting_approvals = true
    stages                      = [{ name = "Dev", actions = [{ name = "apply-dev", environment = "dev" }] }]
  }

  assert {
    condition     = length(aws_lambda_function.approval_superseder) == 0
    error_message = "Without an approval there is nothing to supersede."
  }
}

run "the_name_can_be_set" {
  command = apply
  variables {
    supersede_waiting_approvals = true
    resource_names              = { approval_superseder_function = "legacy-superseder" }
  }

  assert {
    condition     = aws_lambda_function.approval_superseder[0].function_name == "legacy-superseder" && aws_cloudwatch_event_rule.approval_superseder[0].name == "legacy-superseder"
    error_message = "resource_names.approval_superseder_function names the function and the rule."
  }
}

run "needs_superseded_execution_mode" {
  command = plan
  variables {
    supersede_waiting_approvals = true
    execution_mode              = "QUEUED"
  }

  expect_failures = [var.execution_mode]
}

run "execution_mode_can_be_queued_without_the_feature" {
  command = plan
  variables {
    execution_mode = "QUEUED"
  }

  assert {
    condition     = aws_codepipeline.this.execution_mode == "QUEUED"
    error_message = "execution_mode must reach the pipeline."
  }
}
