resource "aws_codestarconnections_connection" "gitlab" {
  name          = var.gitlab_connection_name
  provider_type = var.gitlab_provider_type
}
