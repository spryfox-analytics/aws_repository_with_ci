locals {
  codepipeline_role_name   = "${local.camel_cased_repository_path}CodepipelineRole"
  codepipeline_policy_name = "${local.camel_cased_repository_path}CodepipelinePolicy"
}

resource "aws_iam_role" "codepipeline" {
  name = local.codepipeline_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = local.codepipeline_role_name
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = local.codepipeline_policy_name
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = ["${aws_s3_bucket.codepipeline_artifact_store.arn}*"]
      },
      {
        Effect   = "Allow"
        Action   = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = [var.gitlab_code_connection_arn]
      }
    ]
  })
}
