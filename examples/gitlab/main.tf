# An infrastructure repository in GitLab: every push to main plans and, after a manual approval,
# applies against production. Pull requests are planned too.

provider "aws" {
  region = "eu-west-1"
}

module "gitlab_connection" {
  source = "../../modules/code_connection"

  name          = "gitlab"
  provider_type = "GitLab"
}

module "my_infrastructure" {
  source = "../.."

  name = "my-infrastructure"
  source_repository = {
    connection_arn = module.gitlab_connection.arn
    repository_id  = "my-group/my-infrastructure"
  }
  triggers = {
    pull_request_branches = ["**"]
  }

  environments = {
    prod = "444444444444"
  }
  ecr_repository = { enabled = false }

  actions = [
    { name = "plan-prod", environment = "prod", buildspec = "buildspec_plan.yml" },
    { name = "approve-prod", category = "Approval", provider = "Manual" },
    { name = "apply-prod", environment = "prod", buildspec = "buildspec_apply.yml" },
  ]
}
