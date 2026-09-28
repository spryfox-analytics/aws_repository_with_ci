resource "aws_codeartifact_repository" "this" {
  count = var.codeartifact_domain != null ? 1 : 0

  repository = local.names.codeartifact_repository
  domain     = var.codeartifact_domain

  tags = merge(local.tags, { Name = local.names.codeartifact_repository })
}
