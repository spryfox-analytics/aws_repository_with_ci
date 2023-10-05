locals {
  codepipeline_s3_bucket_name = "${aws_codecommit_repository.this.repository_name}-codepl-artifact-store-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "codepipeline_artifact_store" {
  bucket = local.codepipeline_s3_bucket_name
  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = local.codepipeline_s3_bucket_name
    Project     = var.project
  }
}

resource "aws_s3_bucket_policy" "allow_access_from_another_account" {
  bucket = aws_s3_bucket.codepipeline_artifact_store.id
  policy = data.aws_iam_policy_document.allow_access_from_another_account.json
}

data "aws_iam_policy_document" "allow_access_from_another_account" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [var.aws_development_account_number, var.aws_integration_account_number, var.aws_production_account_number]
    }

    actions = [
      "s3:Get*",
      "s3:List*",
    ]

    resources = [
      aws_s3_bucket.codepipeline_artifact_store.arn,
      "${aws_s3_bucket.codepipeline_artifact_store.arn}/*",
    ]
  }
}
