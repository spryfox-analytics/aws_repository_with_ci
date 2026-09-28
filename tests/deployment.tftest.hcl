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
  deployment_role     = { environments = ["int", "prod"] }
  codeartifact_domain = "my-domain"
  triggers            = { pull_request_branches = ["**"] }
  actions = [
    { name = "plan-int", environment = "int", buildspec = "buildspec_plan.yml" },
    { name = "approve-int", category = "Approval", provider = "Manual" },
    { name = "apply-int", environment = "int", buildspec = "buildspec_apply.yml" },
  ]
}

run "only_codebuild_actions_get_projects" {
  command = apply

  assert {
    condition     = tolist(sort(keys(aws_codebuild_project.this))) == tolist(["apply-int", "plan-int"])
    error_message = "Approval actions must not get a CodeBuild project."
  }
  assert {
    condition     = [for a in aws_codepipeline.this.stage[1].action : a.name] == ["plan-int", "approve-int", "apply-int"]
    error_message = "Actions must keep their order."
  }
  assert {
    condition     = length(aws_codepipeline.this.stage[1].action[1].input_artifacts) == 0
    error_message = "A manual approval takes no input artifacts."
  }
}

run "builds_know_their_environment" {
  command = apply

  assert {
    condition = alltrue([
      for v in aws_codebuild_project.this["plan-int"].environment[0].environment_variable :
      v.value == "333333333333" if v.name == "ENVIRONMENT_AWS_ACCOUNT_ID"
    ])
    error_message = "ENVIRONMENT_AWS_ACCOUNT_ID must be the int account."
  }
  assert {
    condition = length(setintersection(
      [for v in aws_codebuild_project.this["plan-int"].environment[0].environment_variable : v.name],
      ["ENVIRONMENT", "ENVIRONMENT_AWS_ACCOUNT_ID", "CODE_ARTIFACT_DOMAIN", "CODE_ARTIFACT_REPOSITORY", "ECR_REPOSITORY_NAME", "S3_CODEPIPELINE_ARTIFACT_STORE_URL", "AWS_DEFAULT_REGION", "CURRENT_AWS_ACCOUNT_ID"]
    )) == 8
    error_message = "A build is missing one of the documented environment variables."
  }
}

run "deployment_role_is_limited_to_the_chosen_environments" {
  command = apply

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.codebuild.statement :
      s.sid == "AssumeDeploymentRole" && sort(s.resources) == sort([
        "arn:aws:iam::333333333333:role/ToolAccountCodeBuildRole",
        "arn:aws:iam::444444444444:role/ToolAccountCodeBuildRole",
      ])
    ])
    error_message = "CodeBuild may assume the deployment role in int and prod only."
  }
}

run "full_clone_and_pull_requests" {
  command = apply

  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].configuration.OutputArtifactFormat == "CODEBUILD_CLONE_REF"
    error_message = "full_clone must hand CodeBuild a clone reference."
  }
  assert {
    condition     = contains([for s in data.aws_iam_policy_document.codebuild.statement : s.sid], "UseSourceConnection")
    error_message = "A full clone needs the connection in CodeBuild."
  }
  assert {
    condition     = aws_codepipeline.this.trigger[0].git_configuration[0].pull_request[0].branches[0].includes == tolist(["**"])
    error_message = "Pull request trigger missing."
  }
}

run "every_environment_may_read_the_outputs" {
  command = apply

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.artifacts[0].statement :
      s.sid == "EnvironmentAccountsRead" && length(setsubtract(["222222222222", "333333333333", "444444444444"], flatten([for p in s.principals : p.identifiers]))) == 0
    ])
    error_message = "All environment accounts must be able to read the artifact bucket."
  }
}
