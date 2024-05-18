output "codeartifact_repository_arn" {
  value = aws_codeartifact_repository.this.arn
}

output "codeartifact_repository_id" {
  value = aws_codeartifact_repository.this.id
}

output "codebuild_project_role_arn" {
  value = aws_iam_role.codebuild.arn
}

output "codebuild_project_role_name" {
  value = aws_iam_role.codebuild.name
}

output "codecommit_repository_arn" {
  value = aws_codecommit_repository.this.arn
}

output "codecommit_repository_name" {
  value = aws_codebuild_project.this.name
}

output "codepipeline_arn" {
  value = aws_codepipeline.this.arn
}

output "codepipeline_name" {
  value = aws_codepipeline.this.name
}

output "codepipeline_role_arn" {
  value = aws_iam_role.codepipeline.arn
}

output "codepipeline_role_name" {
  value = aws_iam_role.codepipeline.name
}
