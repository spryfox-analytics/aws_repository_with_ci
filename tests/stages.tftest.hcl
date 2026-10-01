mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name = "my-infrastructure"
  source_repository = {
    connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    repository_id  = "my-organization/my-project/my-infrastructure"
    full_clone     = true
  }
  environments = {
    dev  = "222222222222"
    int  = "333333333333"
    prod = "444444444444"
  }
  stages = [
    { name = "Dev", actions = [{ name = "apply-dev", environment = "dev", buildspec = "buildspec_apply.yml" }] },
    {
      name = "Int"
      actions = [
        { name = "plan-int", environment = "int", buildspec = "buildspec_plan.yml" },
        { name = "approve-int", category = "Approval", provider = "Manual" },
        { name = "apply-int", environment = "int", buildspec = "buildspec_apply.yml" },
      ]
    },
  ]
}

run "every_stage_follows_source_in_order" {
  command = apply

  assert {
    condition     = [for s in aws_codepipeline.this.stage : s.name] == ["Source", "Dev", "Int"]
    error_message = "The stages must follow Source in the given order."
  }
  assert {
    condition     = [for a in aws_codepipeline.this.stage[2].action : a.name] == ["plan-int", "approve-int", "apply-int"]
    error_message = "Each stage must keep the order of its actions."
  }
  assert {
    condition     = [for a in aws_codepipeline.this.stage[2].action : a.run_order] == [1, 2, 3]
    error_message = "The run order starts again in every stage."
  }
}

run "codebuild_actions_of_every_stage_get_projects" {
  command = apply

  assert {
    condition     = tolist(sort(keys(aws_codebuild_project.this))) == tolist(["apply-dev", "apply-int", "plan-int"])
    error_message = "Every CodeBuild action of every stage needs a project, approvals none."
  }
  assert {
    condition = alltrue([
      for v in aws_codebuild_project.this["apply-dev"].environment[0].environment_variable :
      v.value == "222222222222" if v.name == "ENVIRONMENT_AWS_ACCOUNT_ID"
    ])
    error_message = "A build in the Dev stage must know the dev account."
  }
}

run "without_stages_the_actions_form_the_deploy_stage" {
  command = apply
  variables {
    stages  = null
    actions = [{ name = "build" }]
  }

  assert {
    condition     = [for s in aws_codepipeline.this.stage : s.name] == ["Source", "Deploy"]
    error_message = "Without stages the pipeline must keep its single Deploy stage."
  }
}

run "rejects_action_names_repeated_across_stages" {
  command = plan
  variables {
    stages = [
      { name = "Dev", actions = [{ name = "apply" }] },
      { name = "Prod", actions = [{ name = "apply" }] },
    ]
  }
  expect_failures = [var.stages]
}

run "rejects_a_stage_named_source" {
  command = plan
  variables {
    stages = [{ name = "Source", actions = [{ name = "build" }] }]
  }
  expect_failures = [var.stages]
}

run "rejects_an_empty_stage" {
  command = plan
  variables {
    stages = [{ name = "Dev", actions = [] }]
  }
  expect_failures = [var.stages]
}

run "rejects_an_unknown_environment_in_a_stage" {
  command = plan
  variables {
    stages = [{ name = "Dev", actions = [{ name = "deploy", environment = "staging" }] }]
  }
  expect_failures = [var.stages]
}
