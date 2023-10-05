variable "application" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "customer" {
  type = string
}

variable "project" {
  type = string
}

variable "codecommit_repository_name" {
  type = string
}

variable "codecommit_repository_camel_case_name" {
  type = string
}

variable "codeartifact_domain_name" {
  type = string
}

variable "ecr_repository_camel_case_name" {
  type = string
}

variable "aws_development_account_number" {
  type = string
}

variable "aws_integration_account_number" {
  type = string
}

variable "aws_production_account_number" {
  type = string
}

variable "pipeline_actions" {
  default = [
    {
      name                    = "build"
      category                = "Build"
      provider                = "CodeBuild"
      input_artifacts         = ["SourceArtifact"]
      output_artifacts        = ["BuildArtifact"]
      buildspec               = "buildspec.yml"
      codebuild_project_index = 0
    }
  ]
}
