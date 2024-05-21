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

resource "aws_s3_bucket_cors_configuration" "codepipeline_artifact_store_cors" {
  count  = var.enable_public_read_for_codepipeline_artifact_store ? 1 : 0
  bucket = aws_s3_bucket.codepipeline_artifact_store.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_acl" "codepipeline_artifact_store_acl" {
  count  = var.enable_public_read_for_codepipeline_artifact_store ? 1 : 0
  bucket = aws_s3_bucket.codepipeline_artifact_store.id
  acl    = "public-read"
  depends_on = [aws_s3_bucket_ownership_controls.codepipeline_artifact_store_ownership]
}

resource "aws_s3_bucket_ownership_controls" "codepipeline_artifact_store_ownership" {
  count  = var.enable_public_read_for_codepipeline_artifact_store ? 1 : 0
  bucket = aws_s3_bucket.codepipeline_artifact_store.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
  depends_on = [aws_s3_bucket_public_access_block.codepipeline_artifact_store_public_access]
}

resource "aws_s3_bucket_public_access_block" "codepipeline_artifact_store_public_access" {
  count  = var.enable_public_read_for_codepipeline_artifact_store ? 1 : 0
  bucket = aws_s3_bucket.codepipeline_artifact_store.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
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
      "s3:PutBucketWebsite*",
      "s3:DeleteBucketWebsite*"
    ]

    resources = [
      aws_s3_bucket.codepipeline_artifact_store.arn,
      "${aws_s3_bucket.codepipeline_artifact_store.arn}/*"
    ]
  }
}
