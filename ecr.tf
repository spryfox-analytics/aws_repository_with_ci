resource "aws_ecr_repository" "this" {
  name = local.dashed_repository_path
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = local.dashed_repository_path
    Project     = var.project
  }
}
