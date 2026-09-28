# aws_repository_with_ci

Terraform module that gives one Git repository a complete CI/CD setup in an AWS tools account:

- **CodePipeline (V2)** that starts on Git events and reads the repository through an
  **AWS CodeConnections** connection
- **CodeBuild** projects, one per build action
- **ECR** repository for container images and, optionally, a **CodeArtifact** repository for packages
- **S3** artifact bucket, optionally public or behind an access point, readable by the deployment accounts
- **IAM** roles for pipeline and builds, scoped to the resources of this module

The module does not care which Git provider hosts the repository. The provider only matters for the
connection, which `modules/code_connection` creates once per account and provider and every pipeline
shares. Any provider CodeConnections supports works: Azure DevOps, Bitbucket, GitHub and GitLab, plus
self-managed GitHub Enterprise Server and GitLab installations through a CodeConnections host.

## Requirements

| | Version |
|---|---|
| Terraform | >= 1.9 |
| hashicorp/aws | >= 6.8.0, the first release that knows the AzureDevOps provider type |

## Usage

Reference the module by the Git URL of this repository and a release tag; `OWNER` stands for the
account hosting it.

```hcl
module "azure_devops_connection" {
  source = "git::https://github.com/OWNER/aws_repository_with_ci.git//modules/code_connection?ref=v3.1.0"

  name          = "azure-devops"
  provider_type = "AzureDevOps"
}

module "my_service" {
  source = "git::https://github.com/OWNER/aws_repository_with_ci.git?ref=v3.1.0"

  name = "my-service"
  source_repository = {
    connection_arn = module.azure_devops_connection.arn
    repository_id  = "my-organization/my-project/my-service"
  }

  environments = {
    dev  = "222222222222"
    prod = "444444444444"
  }

  tags = { Customer = "My Customer", Project = "My Project" }
}
```

More in [examples/](examples/): a container service on Azure DevOps, and an infrastructure repository on
GitLab with plan, manual approval and apply.

## Connecting a Git provider

AWS creates every connection in the `PENDING` state, and no pipeline can use it until the handshake
with the provider is completed once by hand:

1. `terraform apply` the `code_connection` module.
2. In the AWS console, open *Developer Tools > Settings > Connections*, select the connection and
   choose *Update pending connection*.
3. Sign in to the provider and install the AWS connector app. This needs administrative rights
   there: *Administer* permission for the Azure DevOps organization, the *Owner* role in GitLab,
   organization owner in GitHub, workspace administrator in Bitbucket.

The connection then turns `AVAILABLE`, which the `status` output reflects. One connection serves every
repository the provider account can see.

A pipeline registers the webhook that starts it on Git events only when it is created, and only
while its connection is `AVAILABLE`. A pipeline created earlier could still be started by hand but
would never react to a push. The module therefore refuses to create or change a pipeline whose
connection is not `AVAILABLE`, which makes the order of a new setup:

1. `terraform apply` creates the connection and everything else, and fails at the pipeline with a
   message pointing to the console.
2. Activate the connection as described above.
3. `terraform apply` again creates the pipeline, with its webhook.

The first apply is not blocked before it gets that far: while the connection does not exist yet
its status cannot be checked, so only the pipeline itself is held back.

A pipeline that was created while its connection was still `PENDING`, for example with an earlier
version of this module, has no webhook. Recreate it once the connection is `AVAILABLE`:

```sh
terraform apply -replace='module.my_service.aws_codepipeline.this'
```

A newly created pipeline starts one execution on its own.

`source_repository.repository_id` is the repository the way the provider names it, for example
`group/subgroup/repo` on GitLab. The format differs between providers and is case sensitive; the
safest value is the one the CodePipeline console lists when you pick the repository for a source
action.

## Triggers

By default, pushes to `source_repository.branch` start the pipeline. `triggers.push_branches` and
`triggers.pull_request_branches` take branch patterns such as `release/*` or `**`. The branch and
commit of a run reach the builds as `SOURCE_BRANCH_NAME` and `SOURCE_COMMIT_ID`.

The source arrives as a ZIP of the commit. Set `source_repository.full_clone = true` when a build
needs Git itself, for example to read tags; CodeBuild then clones through the connection.

## Environments and deployment

`environments` maps environment names to AWS account IDs. Those accounts may read the artifact bucket
and pull images from the ECR repository. An action with `environment = "prod"` receives
`ENVIRONMENT=prod` and `ENVIRONMENT_AWS_ACCOUNT_ID`, and CodeBuild may assume
`deployment_role.name` in the environment accounts, by default in all of them.

## Build environment variables

| Variable | Set when |
|---|---|
| `AWS_DEFAULT_REGION`, `CURRENT_AWS_ACCOUNT_ID` | always |
| `S3_CODEPIPELINE_ARTIFACT_STORE_URL` | always |
| `ECR_REPOSITORY_NAME` | `ecr_repository.enabled` |
| `CODE_ARTIFACT_DOMAIN`, `CODE_ARTIFACT_REPOSITORY` | `codeartifact_domain` is set |
| `ENVIRONMENT`, `ENVIRONMENT_AWS_ACCOUNT_ID` | the action has an `environment` |
| `SOURCE_BRANCH_NAME`, `SOURCE_COMMIT_ID` | always, per pipeline execution |

`environment_variables` adds variables to every project, and `actions[*].codebuild.environment_variables`
to a single one.

## Resource names and adopting existing resources

Every name derives from `name` (see the description of `resource_names` for the scheme). To bring
resources that already exist under Terraform management without recreating them, set their current
names in `resource_names` and move the state with `moved` or `import` blocks. Recreating an ECR
repository, a CodeArtifact repository or the artifact bucket would lose images, packages and published
artifacts, so check the plan for replacements of these before applying.

As a safety net, the module never force-deletes: an ECR repository that still holds images and an
artifact bucket that still has objects make a destroying plan fail instead of emptying them.
CodeArtifact offers no such protection, which makes the plan review for it all the more important.

## Tests

```sh
terraform init -backend=false
terraform test
```

The tests run against a mocked AWS provider and need neither credentials nor an account.

## Upgrading

See [CHANGELOG.md](CHANGELOG.md). v3 is not backwards compatible with v2.
