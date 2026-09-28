output "codepipeline_name" {
  value = aws_codepipeline.this.name
}

output "codepipeline_arn" {
  value = aws_codepipeline.this.arn
}

output "codepipeline_role_arn" {
  value = aws_iam_role.codepipeline.arn
}

output "codebuild_projects" {
  description = "CodeBuild projects keyed by action name."
  value       = { for name, project in aws_codebuild_project.this : name => { name = project.name, arn = project.arn } }
}

output "codebuild_role_arn" {
  value = aws_iam_role.codebuild.arn
}

output "codebuild_role_name" {
  value = aws_iam_role.codebuild.name
}

output "artifact_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "artifact_bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}

output "artifact_access_point_arn" {
  value = one(aws_s3_access_point.artifacts[*].arn)
}

output "ecr_repository_name" {
  value = one(aws_ecr_repository.this[*].name)
}

output "ecr_repository_url" {
  value = one(aws_ecr_repository.this[*].repository_url)
}

output "codeartifact_repository_name" {
  value = one(aws_codeartifact_repository.this[*].repository)
}

output "codeartifact_repository_arn" {
  value = one(aws_codeartifact_repository.this[*].arn)
}
