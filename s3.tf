resource "aws_s3_bucket" "artifacts" {
  bucket = local.names.artifact_bucket
  # Builds publish release artifacts here (e.g. Lambda packages, web assets), so a bucket that
  # still has content must not disappear with a plan.
  force_destroy = false

  tags = merge(local.tags, { Name = local.names.artifact_bucket })

  lifecycle {
    precondition {
      condition     = length(local.names.artifact_bucket) <= 63
      error_message = "The artifact bucket name \"${local.names.artifact_bucket}\" exceeds 63 characters; shorten var.name or set resource_names.artifact_bucket."
    }
  }
}

# Blocks public access unless public_read asks for it (S3.8).
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = !var.artifact_bucket.public_read
  block_public_policy     = !var.artifact_bucket.public_read
  ignore_public_acls      = !var.artifact_bucket.public_read
  restrict_public_buckets = !var.artifact_bucket.public_read
}

data "aws_iam_policy_document" "artifacts" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = length(local.environment_account_ids) > 0 ? [1] : []
    content {
      sid = "EnvironmentAccountsRead"
      principals {
        type        = "AWS"
        identifiers = local.environment_account_ids
      }
      actions   = ["s3:Get*", "s3:List*"]
      resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.artifact_bucket.cloudfront_distribution_arns) > 0 ? [1] : []
    content {
      sid = "CloudFrontOriginAccessControl"
      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.artifacts.arn}/${var.artifact_bucket.cloudfront_path_prefix}*"]
      condition {
        test     = "StringEquals"
        variable = "AWS:SourceArn"
        values   = var.artifact_bucket.cloudfront_distribution_arns
      }
    }
  }

  dynamic "statement" {
    for_each = var.artifact_bucket.public_read ? [1] : []
    content {
      sid = "PublicReadGetObject"
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      actions   = ["s3:GetObject"]
      resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifacts.json

  # A public policy is rejected while the bucket still blocks public policies.
  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

resource "aws_s3_access_point" "artifacts" {
  count = var.artifact_bucket.access_point ? 1 : 0

  bucket = aws_s3_bucket.artifacts.id
  name   = local.names.artifact_access_point

  public_access_block_configuration {
    block_public_acls       = !var.artifact_bucket.public_read
    block_public_policy     = !var.artifact_bucket.public_read
    ignore_public_acls      = !var.artifact_bucket.public_read
    restrict_public_buckets = !var.artifact_bucket.public_read
  }
}

# Both resources had a count up to v3.8.0.
moved {
  from = aws_s3_bucket_public_access_block.artifacts[0]
  to   = aws_s3_bucket_public_access_block.artifacts
}

moved {
  from = aws_s3_bucket_policy.artifacts[0]
  to   = aws_s3_bucket_policy.artifacts
}
