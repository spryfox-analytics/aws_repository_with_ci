locals {
  repository_name      = replace(var.gitlab_repository_path, "/", "-")
  ecr_repository_name = local.repository_name
}

resource "aws_ecr_repository" "this" {
  name = local.ecr_repository_name
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = local.ecr_repository_name
    Project     = var.project
  }
}
