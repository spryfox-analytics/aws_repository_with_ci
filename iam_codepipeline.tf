locals {
  codepipeline_role_name   = "${var.codecommit_repository_camel_case_name}CodepipelineRole"
  codepipeline_policy_name = "${var.codecommit_repository_camel_case_name}CodepipelinePolicy"
}

resource "aws_iam_role" "codepipeline" {
  name = local.codepipeline_role_name
  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Principal : {
          Service : "codepipeline.amazonaws.com"
        },
        Action : "sts:AssumeRole"
      }
    ]
  })
  tags = {
    Application = var.application
    Customer    = var.customer
    Name        = local.codepipeline_role_name
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = local.codepipeline_policy_name
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ],
        Resource : [
          "${aws_s3_bucket.codepipeline_artifact_store.arn}*"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ],
        Resource : "*"
      },
      {
        Effect : "Allow",
        Action : [
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:UploadArchive",
          "codecommit:GetUploadArchiveStatus",
          "codecommit:CancelUploadArchive"
        ],
        Resource : [
          "${aws_codecommit_repository.this.arn}*"
        ]
      }
    ]
  })
}
