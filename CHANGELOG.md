# Changelog

## v3.0.0

A rewrite around a provider-agnostic source. Not backwards compatible with v2.

### Added

- `modules/code_connection` creates the CodeConnections connection, now including **Azure DevOps**
  (`provider_type = "AzureDevOps"`) besides Bitbucket, GitHub and GitLab, and self-managed providers
  through `host_arn`.
- `resource_names` overrides the name of every resource, so existing resources can be adopted without
  being recreated.
- `triggers` controls which pushes and pull requests start the pipeline.
- `environments` accepts any number of deployment environments instead of exactly dev, int and prod.
- `deployment_role` names the role CodeBuild assumes in the environment accounts and limits it to a
  subset of them.
- Per-action CodeBuild settings: compute type, image, privileged mode, timeouts, variables.
- `SOURCE_COMMIT_ID` for every build.
- Tests against a mocked AWS provider (`terraform test`).

### Changed

- **Only the `aws` provider is required.** The pipeline is an `aws_codepipeline` of type V2 again
  instead of an `awscc_codepipeline_pipeline`; `aws` supports V2 triggers by now.
- **Default triggers:** pushes to the source branch only. v2 started on pushes to every branch and on
  every pull request.
- **Source artifact:** a ZIP of the commit by default. v2 always handed over a full clone, which is
  now opt-in via `source_repository.full_clone`.
- **IAM:** the connection is granted as `codeconnections:UseConnection` and
  `codestar-connections:UseConnection`, as AWS requires, and to CodeBuild only for a full clone.
  Logs, ECR pushes and pipeline build starts are limited to this module's resources.
- **Default artifact bucket name:** `<name>-artifacts-<account id>` instead of `<name>-cdppln-<account id>`.
- **Public artifact bucket:** made public through a bucket policy and public access block rather than
  a public-read ACL with CORS.
- **Pipeline variable** `TRIGGER_BRANCH` is now `SOURCE_BRANCH_NAME`.
- ECR repositories and the artifact bucket explicitly refuse to be force-deleted.

### Removed

- The environment accounts' permission to manage website configuration of the artifact bucket
  (`s3:PutBucketWebsite*`, `s3:DeleteBucketWebsite*`).

### Variables from v2

| v2 | v3 |
|---|---|
| `customer`, `project`, `application` | `tags` |
| `aws_region` | taken from the provider |
| `aws_development_account_number`, `aws_integration_account_number`, `aws_production_account_number` | `environments` |
| `gitlab_code_connection_arn` | `source_repository.connection_arn` |
| `gitlab_repository_path` | `source_repository.repository_id`; `name` is now set explicitly |
| `codeartifact_domain_name` | `codeartifact_domain`, optional |
| `pipeline_actions` | `actions`; `codebuild_project_index` is gone, projects are keyed by action name |
| `additional_environment_variables` | `environment_variables` |
| `enable_public_read_for_codepipeline_artifact_store` | `artifact_bucket.public_read` |

### Migrating from v2

Resources keep their names when `name` equals the last segment of the former `gitlab_repository_path`,
except for the artifact bucket; set `resource_names.artifact_bucket` to its current name. The CodeBuild
projects change their address from an index to the action name, and the pipeline changes its resource
type, so move or re-import them:

```hcl
moved {
  from = module.my_service.aws_codebuild_project.this["0"]
  to   = module.my_service.aws_codebuild_project.this["build"]
}

removed {
  from = module.my_service.awscc_codepipeline_pipeline.this
  lifecycle { destroy = false }
}

import {
  to = module.my_service.aws_codepipeline.this
  id = "my-service-codepipeline"
}
```
