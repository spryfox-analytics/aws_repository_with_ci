locals {
  codecommit_git_mirroring_user_policy_name   = "${var.codecommit_repository_camel_case_name}AccessPolicy"
  codecommit_git_user_access_credentials_name = "${var.codecommit_repository_name}-git-user-access-credentials"
  codecommit_git_user_name                    = "${var.codecommit_repository_name}-git-user"
  codecommit_git_user_policy_name             = "${var.codecommit_repository_name}-git-user-policy"
}

resource "aws_iam_user" "codecommit_git_user" {
  name = local.codecommit_git_user_name
}

resource "aws_iam_policy" "git_mirroring_user" {
  name = local.codecommit_git_mirroring_user_policy_name
  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Sid : "MinimumGitLabPushMirroringPermissions",
        Effect : "Allow",
        Action : [
          "codecommit:GitPull",
          "codecommit:GitPush"
        ],
        Resource : [
          "${aws_codecommit_repository.this.arn}*"
        ]
      }
    ]
  })
}

resource "aws_iam_service_specific_credential" "git_mirroring_user" {
  service_name = "codecommit.amazonaws.com"
  user_name    = aws_iam_user.codecommit_git_user.name
}

resource "aws_iam_user_policy_attachment" "git_mirroring_user" {
  user       = aws_iam_user.codecommit_git_user.name
  policy_arn = aws_iam_policy.git_mirroring_user.arn
}

resource "aws_secretsmanager_secret" "codecommit_git_user_access_credentials" {
  name = local.codecommit_git_user_access_credentials_name
  tags = {
    Name        = local.codecommit_git_user_access_credentials_name
    Customer    = var.customer
    Project     = var.project
    Application = var.application
  }
}

resource "aws_secretsmanager_secret_version" "codecommit_git_user_access_credentials_version" {
  secret_id = aws_secretsmanager_secret.codecommit_git_user_access_credentials.id
  secret_string = jsonencode({
    HTTPS_GIT_USERNAME = aws_iam_service_specific_credential.git_mirroring_user.service_user_name
    HTTPS_GIT_PASSWORD = aws_iam_service_specific_credential.git_mirroring_user.service_password
  })
}
