mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name = "my-service"
  source_repository = {
    connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    repository_id  = "my-org/my-project/monorepo"
    directory      = "my-service"
  }
}

run "off_without_a_directory" {
  command = apply
  variables {
    source_repository = {
      connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
      repository_id  = "my-group/my-service"
    }
  }

  assert {
    condition     = length(aws_lambda_function.change_check) == 0 && length(aws_codepipeline.this.stage[1].before_entry) == 0
    error_message = "A repository of its own needs no change check."
  }
}

run "a_directory_skips_unchanged_stages" {
  command = apply
  variables {
    stages = [
      { name = "Dev", actions = [{ name = "apply-dev" }] },
      { name = "Prod", actions = [{ name = "approve-prod", category = "Approval", provider = "Manual" }, { name = "apply-prod" }] },
    ]
  }

  assert {
    condition     = length(aws_lambda_function.change_check) == 1 && aws_lambda_function.change_check[0].function_name == "my-service-change-check"
    error_message = "A directory must bring the change check function."
  }
  assert {
    condition     = alltrue([for stage in slice(aws_codepipeline.this.stage, 1, 3) : stage.before_entry[0].condition[0].result == "SKIP"])
    error_message = "Every deploy stage must be skipped when the check fails, also the approval stages."
  }
  assert {
    condition     = jsondecode(aws_codepipeline.this.stage[1].before_entry[0].condition[0].rule[0].configuration.UserParameters).directory == "my-service"
    error_message = "The check must compare the pipeline's directory."
  }
  assert {
    condition     = aws_codepipeline.this.stage[1].before_entry[0].condition[0].rule[0].input_artifacts == tolist(["SourceArtifact"])
    error_message = "The check needs the source of the execution."
  }
  assert {
    condition     = contains([for s in data.aws_iam_policy_document.codepipeline.statement : s.sid], "CheckChanges")
    error_message = "The pipeline must be allowed to invoke the check."
  }
}

run "azure_devops_relies_on_the_check_instead_of_a_path_filter" {
  command = apply
  override_data {
    target = data.aws_codestarconnections_connection.source
    values = { name = "azure-devops", connection_status = "AVAILABLE", provider_type = "AzureDevOps" }
  }

  assert {
    condition     = length(aws_codepipeline.this.trigger[0].git_configuration[0].push[0].file_paths) == 0
    error_message = "Azure DevOps never fires a path filtered trigger on a completed pull request, so there must be none."
  }
  assert {
    condition     = length(aws_codepipeline.this.stage[1].before_entry) == 1
    error_message = "Azure DevOps pipelines must skip unchanged stages instead."
  }
}

run "can_be_turned_off" {
  command = apply
  variables {
    skip_unchanged = false
  }

  assert {
    condition     = length(aws_lambda_function.change_check) == 0 && length(aws_codepipeline.this.stage[1].before_entry) == 0
    error_message = "skip_unchanged = false must leave the stages unconditional."
  }
}

run "additional_directories_count_as_changes" {
  command = apply
  variables {
    source_repository = {
      connection_arn         = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
      repository_id          = "my-org/my-project/monorepo"
      directory              = "my-service"
      additional_directories = ["core", "security", "my-service"]
    }
  }

  assert {
    condition     = jsondecode(aws_codepipeline.this.stage[1].before_entry[0].condition[0].rule[0].configuration.UserParameters).additional_directories == ["core", "security"]
    error_message = "The check must also compare the additional directories, without repeating the directory."
  }
  assert {
    condition     = jsondecode(aws_codepipeline.this.stage[1].before_entry[0].condition[0].rule[0].configuration.UserParameters).directory == "my-service"
    error_message = "The directory must stay the check's main directory."
  }
}

run "no_additional_directories_keep_the_configuration" {
  command = apply

  assert {
    condition     = !contains(keys(jsondecode(aws_codepipeline.this.stage[1].before_entry[0].condition[0].rule[0].configuration.UserParameters)), "additional_directories")
    error_message = "Without additional directories the rule configuration must stay as in v3.7.0."
  }
  assert {
    condition     = aws_lambda_function.change_check[0].description == "Skips the stages of my-service-codepipeline when my-service did not change."
    error_message = "Without additional directories the function description must stay as in v3.7.0."
  }
}
