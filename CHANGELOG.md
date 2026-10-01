# Changelog

## v3.5.0

### Added

- `stages`: deploy stages of their own after Source, each with actions as in `actions`. CodePipeline
  runs one execution per stage at a time, so with a single Deploy stage an open manual approval holds
  back every later push, also the parts of the deployment that need no approval. With stages it only
  holds its own stage, for example while dev deploys on every push.

### Upgrading

Nothing changes without `stages`: the actions still form the stage "Deploy", and the CodeBuild
projects keep their names, so a plan shows no change.

## v3.4.0

### Changed

- The default CodeBuild image is `aws/codebuild/amazonlinux-x86_64-standard:5.0` (Amazon Linux 2023)
  instead of `aws/codebuild/amazonlinux2-x86_64-standard:4.0`. Amazon Linux 2 has reached its end of
  life and the 4.0 image is no longer among the supported ones; its runtimes decay, for example
  Node.js no longer starts in it for lack of a recent glibc. 5.0 offers Python 3.9 to 3.14 and
  Node.js 18 to 26.

### Upgrading

Builds run on Amazon Linux 2023. Buildspecs that name a runtime version need one that 5.0 offers;
projects that need the old image can keep it with `actions[*].codebuild.image`.

## v3.3.0

### Changed

- The source format follows the provider when `source_repository.full_clone` is unset: a Git clone
  where CodeBuild can clone from the provider (Bitbucket, GitHub, GitHub Enterprise Server, GitLab),
  a ZIP for Azure DevOps. v3.2.0 cloned everywhere, but CodeBuild cannot clone from Azure DevOps,
  so every build of an Azure DevOps repository failed at the source download with "authorization
  failed for primary source".
- `full_clone = true` is rejected for providers CodeBuild cannot clone from, with an explanation.

### Upgrading

Azure DevOps pipelines switch back to the ZIP and CodeBuild no longer uses the connection. The ZIP
does not keep executable bits; builds that run scripts from the repository directly have to make
them executable again, see the README.

## v3.2.0

### Changed

- `source_repository.full_clone` defaults to `true`: builds receive a Git clone of the commit again,
  as in v2. The ZIP that v3.0 and v3.1 used by default does not keep the files' executable bits, so
  images whose entrypoint is a script from the repository were built fine but failed to start with
  "Permission denied". `full_clone = false` still selects the ZIP.

### Upgrading

Nothing to change. CodeBuild additionally gets permission to use the source connection, which the
clone is fetched through.

## v3.1.0

### Changed

- A pipeline is only created or changed while its connection is `AVAILABLE`. A pipeline registers
  the webhook that starts it on Git events only when it is created against an available
  connection; created against a `PENDING` one it can be started by hand but never reacts to a push,
  and nothing reports it. The plan or apply now fails instead, with a link to where the connection
  is activated. A new setup is not dead-locked by this: in its first run the connection is created
  and only the pipeline is held back, so there is a connection to activate before applying again.

### Upgrading

Nothing to change for pipelines whose connection is `AVAILABLE`. A pipeline created while its
connection was still `PENDING` has no webhook; recreate it with
`terraform apply -replace='<module address>.aws_codepipeline.this'`.

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
