# Mocked values must still pass the provider's own argument validation, so identifiers and
# documents are given in their real formats.

mock_data "aws_caller_identity" {
  defaults = { account_id = "111111111111" }
}

mock_data "aws_region" {
  defaults = { region = "eu-west-1" }
}

mock_data "aws_iam_policy_document" {
  defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

mock_resource "aws_iam_role" {
  defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
}

mock_resource "aws_s3_bucket" {
  defaults = { arn = "arn:aws:s3:::mock-bucket" }
}

mock_resource "aws_ecr_repository" {
  defaults = {
    arn            = "arn:aws:ecr:eu-west-1:111111111111:repository/mock"
    repository_url = "111111111111.dkr.ecr.eu-west-1.amazonaws.com/mock"
  }
}

mock_resource "aws_codebuild_project" {
  defaults = { arn = "arn:aws:codebuild:eu-west-1:111111111111:project/mock" }
}

mock_resource "aws_codeartifact_repository" {
  defaults = { arn = "arn:aws:codeartifact:eu-west-1:111111111111:repository/mock-domain/mock" }
}

mock_resource "aws_codepipeline" {
  defaults = { arn = "arn:aws:codepipeline:eu-west-1:111111111111:mock" }
}

mock_resource "aws_s3_access_point" {
  defaults = { arn = "arn:aws:s3:eu-west-1:111111111111:accesspoint/mock" }
}

mock_data "aws_codestarconnections_connection" {
  defaults = {
    name              = "mock-connection"
    connection_status = "AVAILABLE"
    provider_type     = "GitLab"
  }
}

mock_resource "aws_codeconnections_connection" {
  defaults = {
    arn               = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    connection_status = "PENDING"
  }
}

mock_resource "aws_lambda_function" {
  defaults = { arn = "arn:aws:lambda:eu-west-1:111111111111:function:mock" }
}

mock_resource "aws_cloudwatch_log_group" {
  defaults = { arn = "arn:aws:logs:eu-west-1:111111111111:log-group:mock" }
}
