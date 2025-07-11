resource "aws_codeartifact_repository" "this" {
  repository = local.dashed_repository_path
  domain     = var.codeartifact_domain_name
}
