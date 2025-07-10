locals {
  codeartifact_repository_name = replace(var.gitlab_repository_path, "/", "-")
}

resource "aws_codeartifact_repository" "this" {
  repository = local.codeartifact_repository_name
  domain     = var.codeartifact_domain_name
}
