# A web application served by CloudFront through Origin Access Control: the bucket stays private
# and only the named distributions may read the given prefix.

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name = "my-web-application"
  source_repository = {
    connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    repository_id  = "my-organization/my-project/my-web-application"
  }
  environments = { prod = "444444444444" }
  artifact_bucket = {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::444444444444:distribution/EDFDVBD6EXAMPLE"]
    cloudfront_path_prefix       = "releases/"
  }
}

run "distribution_reads_privately" {
  command = apply

  assert {
    condition     = aws_s3_bucket_public_access_block.artifacts.block_public_policy && aws_s3_bucket_public_access_block.artifacts.restrict_public_buckets
    error_message = "The bucket must block public access."
  }
  assert {
    condition     = contains([for s in data.aws_iam_policy_document.artifacts.statement : s.sid], "CloudFrontOriginAccessControl")
    error_message = "The distributions must get a read statement."
  }
  assert {
    condition     = !contains([for s in data.aws_iam_policy_document.artifacts.statement : s.sid], "PublicReadGetObject")
    error_message = "No public read with Origin Access Control."
  }
}
