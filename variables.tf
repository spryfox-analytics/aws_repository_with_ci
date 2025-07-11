variable "customer" {
  type        = string
  description = "Customer or team name"
}

variable "project" {
  type        = string
  description = "Project identifier"
}

variable "application" {
  type        = string
  description = "Logical application name"
}

variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
}

variable "aws_development_account_number" {
  type        = string
  description = "Dev account ID"
}

variable "aws_integration_account_number" {
  type        = string
  description = "Integration account ID"
}

variable "aws_production_account_number" {
  type        = string
  description = "Prod account ID"
}

variable "gitlab_code_connection_arn" {
  description = "ARN of an existing AWS CodeStar Connections connection (e.g. GitLab) to use for all pipelines."
  type        = string
}

variable "gitlab_repository_path" {
  type        = string
  description = "Full GitLab repo path (e.g. group/subgroup/repo)"
}

variable "repository_camel_case_name" {
  type        = string
  description = "CamelCase repo name for IAM role naming"
}

variable "codeartifact_domain_name" {
  type        = string
  description = "Domain for AWS CodeArtifact"
}

variable "ecr_repository_camel_case_name" {
  type        = string
  description = "CamelCase name for ECR repository"
}

variable "enable_public_read_for_codepipeline_artifact_store" {
  type        = bool
  default     = false
  description = "Whether the S3 artifact bucket is publicly readable"
}

variable "pipeline_actions" {
  type        = list(object({
    name                    = string
    category                = string
    provider                = string
    input_artifacts         = list(string)
    output_artifacts        = list(string)
    buildspec               = string
    codebuild_project_index = number
    environment             = optional(string)
  }))
  default = [{
    name                    = "build"
    category                = "Build"
    provider                = "CodeBuild"
    input_artifacts         = ["SourceArtifact"]
    output_artifacts        = ["BuildArtifact"]
    buildspec               = "buildspec.yml"
    codebuild_project_index = 0
  }]
  description = "List of actions for the Deploy stage"
}

variable "additional_environment_variables" {
  type        = map(string)
  default     = {}
  description = "Extra environment variables for CodeBuild"
}
