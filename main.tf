data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# A pipeline registers the webhook that starts it on Git events only when it is created, and
# only while its connection is AVAILABLE. Created against a PENDING connection it would build
# when started by hand but never on a push, without any error. The status is checked here so
# that such a pipeline is not created in the first place.
data "aws_codestarconnections_connection" "source" {
  arn = var.source_repository.connection_arn
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  camel_case_name = join("", [for part in split("-", var.name) : title(part)])

  names = {
    pipeline                 = coalesce(var.resource_names.pipeline, "${var.name}-codepipeline")
    artifact_bucket          = coalesce(var.resource_names.artifact_bucket, "${var.name}-artifacts-${local.account_id}")
    artifact_access_point    = coalesce(var.resource_names.artifact_access_point, "${var.name}-access-point")
    ecr_repository           = coalesce(var.resource_names.ecr_repository, var.name)
    codeartifact_repository  = coalesce(var.resource_names.codeartifact_repository, var.name)
    codebuild_project_prefix = coalesce(var.resource_names.codebuild_project_prefix, var.name)
    iam_role_prefix          = coalesce(var.resource_names.iam_role_prefix, local.camel_case_name)
    change_check_function    = coalesce(var.resource_names.change_check_function, "${var.name}-change-check")
  }

  source_directory = var.source_repository.directory

  # Azure DevOps reports the push that completes a pull request without commits, so CodePipeline
  # learns of no changed file and a file path filter never starts the pipeline. There the stage
  # conditions of skip_unchanged take the filter's place.
  path_filters_work = data.aws_codestarconnections_connection.source.provider_type != "AzureDevOps"
  skip_unchanged    = var.skip_unchanged != null ? var.skip_unchanged : local.source_directory != null

  # One file path filter for push and pull request triggers, or none. CodePipeline rejects empty
  # include or exclude lists, so an unused one is left out.
  trigger_file_path_includes = length(var.triggers.file_paths) > 0 ? var.triggers.file_paths : (local.source_directory != null && local.path_filters_work ? ["${local.source_directory}/**"] : [])
  trigger_file_paths = length(local.trigger_file_path_includes) + length(var.triggers.file_paths_excluded) > 0 ? [{
    includes = length(local.trigger_file_path_includes) > 0 ? local.trigger_file_path_includes : null
    excludes = length(var.triggers.file_paths_excluded) > 0 ? var.triggers.file_paths_excluded : null
  }] : []

  # Without stages, the actions form the single stage "Deploy" as before.
  stages = [
    for stage in(var.stages != null ? var.stages : [{ name = "Deploy", actions = var.actions }]) : {
      name = stage.name
      actions = [
        for action in stage.actions : merge(action, {
          input_artifacts = action.input_artifacts != null ? action.input_artifacts : (action.provider == "CodeBuild" ? ["SourceArtifact"] : [])
          # A buildspec file lies in the service directory; an inline buildspec stays as it is.
          buildspec = local.source_directory != null && !strcontains(action.buildspec, "\n") ? "${local.source_directory}/${action.buildspec}" : action.buildspec
        })
      ]
    }
  ]
  actions           = flatten([for stage in local.stages : stage.actions])
  codebuild_actions = { for action in local.actions : action.name => action if action.provider == "CodeBuild" }

  # An explicit empty list means "no deployment role", so only null falls back to every environment.
  # CodeBuild clones the source itself for a full clone, which it can do from these providers
  # only. For the others, notably Azure DevOps, the source can only be handed over as a ZIP.
  providers_codebuild_can_clone_from = ["Bitbucket", "GitHub", "GitHubEnterpriseServer", "GitLab", "GitLabSelfManaged"]
  codebuild_can_clone                = contains(local.providers_codebuild_can_clone_from, data.aws_codestarconnections_connection.source.provider_type)
  full_clone                         = var.source_repository.full_clone != null ? var.source_repository.full_clone : local.codebuild_can_clone

  deployment_environments = var.deployment_role.environments != null ? var.deployment_role.environments : keys(var.environments)
  environment_account_ids = distinct(values(var.environments))

  tags = { for key, value in var.tags : key => value if key != "Name" }
}
