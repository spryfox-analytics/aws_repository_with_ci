# Adopting resources that were created before, under names that do not follow this module's
# scheme, must be possible without renaming them: a rename would replace them and lose their
# content (images, packages, published artifacts).

mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name = "my-web-application"
  source_repository = {
    connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    repository_id  = "my-organization/my-project/my-web-application"
  }
  environments        = { prod = "444444444444" }
  codeartifact_domain = "my-domain"
  artifact_bucket     = { public_read = true, access_point = true }
  resource_names = {
    pipeline                 = "legacy-web-codepipeline"
    artifact_bucket          = "legacy-web-codepl-artifact-store-111111111111"
    artifact_access_point    = "legacy-web-web-application-access-point"
    ecr_repository           = "legacy-web"
    codeartifact_repository  = "legacy-web"
    codebuild_project_prefix = "legacy-web"
    iam_role_prefix          = "LegacyWeb"
  }
}

run "overrides_win_over_derived_names" {
  command = apply

  assert {
    condition     = aws_codepipeline.this.name == "legacy-web-codepipeline"
    error_message = "Pipeline override ignored."
  }
  assert {
    condition     = aws_s3_bucket.artifacts.bucket == "legacy-web-codepl-artifact-store-111111111111"
    error_message = "Bucket override ignored."
  }
  assert {
    condition     = aws_s3_access_point.artifacts[0].name == "legacy-web-web-application-access-point"
    error_message = "Access point override ignored."
  }
  assert {
    condition     = aws_ecr_repository.this[0].name == "legacy-web" && aws_codeartifact_repository.this[0].repository == "legacy-web"
    error_message = "ECR or CodeArtifact override ignored."
  }
  assert {
    condition     = aws_codebuild_project.this["build"].name == "legacy-web-build-codebuild-project"
    error_message = "CodeBuild prefix override ignored."
  }
  assert {
    condition     = aws_iam_role.codebuild.name == "LegacyWebCodebuildRole" && aws_iam_role_policy.codebuild.name == "LegacyWebCodebuildPolicy"
    error_message = "IAM prefix override ignored."
  }
}

run "public_bucket_serves_objects" {
  command = apply

  assert {
    condition     = contains([for s in data.aws_iam_policy_document.artifacts[0].statement : s.sid], "PublicReadGetObject")
    error_message = "public_read must add the public read statement."
  }
  assert {
    condition     = !aws_s3_bucket_public_access_block.artifacts[0].block_public_policy
    error_message = "A public bucket must not block public policies."
  }
  assert {
    condition     = !aws_s3_access_point.artifacts[0].public_access_block_configuration[0].block_public_policy
    error_message = "The access point of a public bucket must not block public policies."
  }
}

run "protected_resources_are_never_force_deleted" {
  command = apply

  assert {
    condition     = !aws_ecr_repository.this[0].force_delete && !aws_s3_bucket.artifacts.force_destroy
    error_message = "ECR repositories and artifact buckets must refuse deletion while they hold content."
  }
}
