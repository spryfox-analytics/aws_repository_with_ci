output "codeartifact_repository_arn" {
  value = aws_codeartifact_repository.this.arn
}

output "codeartifact_repository_id" {
  value = aws_codeartifact_repository.this.id
}

output "codebuild_project_arns" {
  value = [for p in aws_codebuild_project.this : p.arn]
}

output "codebuild_project_names" {
  value = [for p in aws_codebuild_project.this : p.name]
}

output "codebuild_role_arn" {
  value = aws_iam_role.codebuild.arn
}

output "codebuild_role_name" {
  value = aws_iam_role.codebuild.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "codepipeline_name" {
  value = awscc_codepipeline_pipeline.this.name
}

output "codepipeline_role_arn" {
  value = aws_iam_role.codepipeline.arn
}

output "codepipeline_role_name" {
  value = aws_iam_role.codepipeline.name
}
