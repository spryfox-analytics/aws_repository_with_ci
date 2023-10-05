resource "aws_codecommit_repository" "this" {
  repository_name = var.codecommit_repository_name
  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = var.codecommit_repository_name
    Project     = var.project
  }
}
