locals {
  codeartifact_repository_name = aws_codecommit_repository.this.repository_name
}

resource "aws_codeartifact_repository" "this" {
  repository = local.codeartifact_repository_name
  domain     = var.codeartifact_domain_name
}
