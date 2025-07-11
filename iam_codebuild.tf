locals {
  codebuild_role_name       = "${local.camel_cased_repository_path}CodebuildRole"
  codebuild_policy_name     = "${local.camel_cased_repository_path}CodebuildPolicy"
  tool_account_codebuild_role_name = "ToolAccountCodeBuildRole"
}

resource "aws_iam_role" "codebuild" {
  name = local.codebuild_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = local.codebuild_role_name
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name = local.codebuild_policy_name
  role = aws_iam_role.codebuild.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = ["${aws_s3_bucket.codepipeline_artifact_store.arn}*"]
      },
      {
        Effect   = "Allow"
        Action   = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:ReadFromRepository",
          "codeartifact:PublishPackageVersion",
          "codeartifact:PutPackageMetadata"
        ]
        Resource = ["*"]
      },
      {
        Effect    = "Allow"
        Action    = ["sts:GetServiceBearerToken"]
        Resource  = ["*"]
        Condition = { StringEquals = { "sts:AWSServiceName" = "codeartifact.amazonaws.com" } }
      },
      {
        Effect   = "Allow"
        Action   = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetAuthorizationToken",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = [
          "arn:aws:iam::${var.aws_integration_account_number}:role/${local.tool_account_codebuild_role_name}",
          "arn:aws:iam::${var.aws_production_account_number}:role/${local.tool_account_codebuild_role_name}"
        ]
      }
    ]
  })
}
