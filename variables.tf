variable "name" {
  description = "Base name for every resource of this module, usually the repository name, e.g. \"my-service\". Individual names can be overridden in `resource_names`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name may only contain lower-case letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "source_repository" {
  description = <<-EOT
    Git repository the pipeline builds from. It is reached through an AWS CodeConnections
    connection (see modules/code_connection), which is what makes the module independent of the
    Git provider: every provider CodeConnections supports works the same way.

    - connection_arn: ARN of an AVAILABLE connection to the provider hosting the repository.
    - repository_id:  the repository as the provider identifies it, e.g. "group/subgroup/repo" on
                      GitLab. Use exactly the value the CodePipeline console offers for the
                      repository; the format differs between providers and is case sensitive.
    - branch:         branch the source action reads, and the default push trigger.
    - full_clone:     hand CodeBuild a Git clone of the commit (CODEBUILD_CLONE_REF) instead of
                      a ZIP of it (CODE_ZIP). Left unset, the module decides by provider: a
                      clone wherever CodeBuild can clone from the provider, which keeps the
                      files' executable bits, and the ZIP for Azure DevOps, which CodeBuild
                      cannot clone from. true for Azure DevOps is rejected.
  EOT
  type = object({
    connection_arn = string
    repository_id  = string
    branch         = optional(string, "main")
    full_clone     = optional(bool)
  })

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:(codeconnections|codestar-connections):", var.source_repository.connection_arn))
    error_message = "source_repository.connection_arn must be the ARN of a CodeConnections connection."
  }
}

variable "triggers" {
  description = <<-EOT
    Git events that start the pipeline.

    - push_branches:         branch patterns whose pushes start it. Defaults to the source branch.
    - pull_request_branches: branch patterns whose pull requests start it. None by default.
    - pull_request_events:   pull request events that count.
  EOT
  type = object({
    push_branches         = optional(list(string))
    pull_request_branches = optional(list(string), [])
    pull_request_events   = optional(list(string), ["OPEN", "UPDATED", "CLOSED"])
  })
  default = {}
}

variable "environments" {
  description = "AWS account IDs of the deployment environments, keyed by environment name, e.g. { dev = \"111111111111\", prod = \"333333333333\" }. These accounts may read the build outputs, and an action's `environment` refers to one of the keys."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for account_id in values(var.environments) : can(regex("^[0-9]{12}$", account_id))])
    error_message = "Every value of environments must be a 12-digit AWS account ID."
  }
}

variable "deployment_role" {
  description = "Role CodeBuild may assume in the environment accounts to deploy there. `environments` limits this to a subset of the keys of var.environments; by default every environment is included."
  type = object({
    name         = optional(string, "ToolAccountCodeBuildRole")
    environments = optional(list(string))
  })
  default = {}

  validation {
    condition     = alltrue([for environment in(var.deployment_role.environments == null ? [] : var.deployment_role.environments) : contains(keys(var.environments), environment)])
    error_message = "deployment_role.environments may only name keys of var.environments."
  }
}

variable "actions" {
  description = <<-EOT
    Actions of the pipeline's Deploy stage, run one after another in the given order. Every
    action whose provider is CodeBuild gets its own CodeBuild project.

    - environment:      key of var.environments the action deploys to. Exposed to the build as
                        ENVIRONMENT and ENVIRONMENT_AWS_ACCOUNT_ID.
    - input_artifacts:  defaults to ["SourceArtifact"] for CodeBuild actions and to none otherwise.
    - configuration:    action configuration for non-CodeBuild actions, e.g. of a manual approval.
    - codebuild:        settings of the CodeBuild project; ignored for other providers.
  EOT
  type = list(object({
    name             = string
    category         = optional(string, "Build")
    provider         = optional(string, "CodeBuild")
    environment      = optional(string)
    buildspec        = optional(string, "buildspec.yml")
    input_artifacts  = optional(list(string))
    output_artifacts = optional(list(string), [])
    configuration    = optional(map(string), {})
    codebuild = optional(object({
      compute_type          = optional(string, "BUILD_GENERAL1_SMALL")
      image                 = optional(string, "aws/codebuild/amazonlinux2-x86_64-standard:4.0")
      privileged_mode       = optional(bool, true)
      build_timeout         = optional(number, 60)
      queued_timeout        = optional(number, 480)
      environment_variables = optional(map(string), {})
    }), {})
  }))
  default = [{
    name             = "build"
    output_artifacts = ["BuildArtifact"]
  }]

  validation {
    condition     = length(var.actions) > 0
    error_message = "At least one action is required."
  }

  validation {
    condition     = length(distinct([for action in var.actions : action.name])) == length(var.actions)
    error_message = "Action names must be unique; they name the CodeBuild projects."
  }

  validation {
    condition     = alltrue([for action in var.actions : action.environment == null ? true : contains(keys(var.environments), action.environment)])
    error_message = "An action's environment must be a key of var.environments."
  }
}

variable "environment_variables" {
  description = "Additional plain-text environment variables for every CodeBuild project. Per-action variables in `actions[*].codebuild.environment_variables` take precedence."
  type        = map(string)
  default     = {}
}

variable "codeartifact_domain" {
  description = "CodeArtifact domain in which to create a repository for this module's packages. Leave null to create none."
  type        = string
  default     = null
}

variable "ecr_repository" {
  description = "ECR repository for the build's container images. `lambda_read_access` additionally lets Lambda pull the images."
  type = object({
    enabled              = optional(bool, true)
    scan_on_push         = optional(bool, true)
    image_tag_mutability = optional(string, "MUTABLE")
    lambda_read_access   = optional(bool, true)
  })
  default = {}
}

variable "artifact_bucket" {
  description = <<-EOT
    S3 bucket CodePipeline stores its artifacts in, and builds may publish to via
    S3_CODEPIPELINE_ARTIFACT_STORE_URL.

    - public_read:  make every object publicly readable, e.g. to serve a web application from it.
    - access_point: additionally create an S3 access point on the bucket.
  EOT
  type = object({
    public_read  = optional(bool, false)
    access_point = optional(bool, false)
  })
  default = {}
}

variable "resource_names" {
  description = <<-EOT
    Explicit names for individual resources, overriding the ones derived from `name`. Mainly
    for adopting existing resources without renaming, and thereby recreating, them.

    Defaults:
    - pipeline:                 "<name>-codepipeline"
    - artifact_bucket:          "<name>-artifacts-<account id>"
    - artifact_access_point:    "<name>-access-point"
    - ecr_repository:           "<name>"
    - codeartifact_repository:  "<name>"
    - codebuild_project_prefix: "<name>"; projects are named "<prefix>-<action>-codebuild-project"
    - iam_role_prefix:          <name> in CamelCase; roles are "<prefix>CodebuildRole" and
                                "<prefix>CodepipelineRole"
  EOT
  type = object({
    pipeline                 = optional(string)
    artifact_bucket          = optional(string)
    artifact_access_point    = optional(string)
    ecr_repository           = optional(string)
    codeartifact_repository  = optional(string)
    codebuild_project_prefix = optional(string)
    iam_role_prefix          = optional(string)
  })
  default = {}
}

variable "tags" {
  description = "Tags for every resource. Each resource additionally gets a Name tag."
  type        = map(string)
  default     = {}
}
