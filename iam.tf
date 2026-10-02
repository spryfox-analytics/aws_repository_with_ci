locals {
  codepipeline_role_name = "${local.names.iam_role_prefix}CodepipelineRole"
  codebuild_role_name    = "${local.names.iam_role_prefix}CodebuildRole"

  # AWS evaluates UseConnection under either service prefix depending on the code path and the
  # prefix of the connection ARN, and asks for both to be granted.
  use_connection_actions = ["codeconnections:UseConnection", "codestar-connections:UseConnection"]
}

# --- CodePipeline -------------------------------------------------------------------------------

data "aws_iam_policy_document" "codepipeline_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = local.codepipeline_role_name
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role.json
  tags               = merge(local.tags, { Name = local.codepipeline_role_name })

  lifecycle {
    precondition {
      condition     = length(local.codepipeline_role_name) <= 64
      error_message = "The IAM role name \"${local.codepipeline_role_name}\" exceeds 64 characters; set resource_names.iam_role_prefix."
    }
  }
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    sid = "ArtifactStore"
    actions = [
      "s3:GetBucketVersioning",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }

  dynamic "statement" {
    for_each = length(aws_codebuild_project.this) > 0 ? [1] : []
    content {
      sid       = "RunBuilds"
      actions   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
      resources = [for project in aws_codebuild_project.this : project.arn]
    }
  }

  statement {
    sid       = "UseSourceConnection"
    actions   = local.use_connection_actions
    resources = [var.source_repository.connection_arn]
  }

  dynamic "statement" {
    for_each = local.skip_unchanged ? [1] : []
    content {
      sid       = "CheckChanges"
      actions   = ["lambda:InvokeFunction"]
      resources = [aws_lambda_function.change_check[0].arn]
    }
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "${local.names.iam_role_prefix}CodepipelinePolicy"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline.json
}

# --- CodeBuild ----------------------------------------------------------------------------------

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = local.codebuild_role_name
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
  tags               = merge(local.tags, { Name = local.codebuild_role_name })

  lifecycle {
    precondition {
      condition     = length(local.codebuild_role_name) <= 64
      error_message = "The IAM role name \"${local.codebuild_role_name}\" exceeds 64 characters; set resource_names.iam_role_prefix."
    }
  }
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${local.names.codebuild_project_prefix}-*"]
  }

  # Builds publish to the artifact bucket freely (sync, delete, overwrite), so it is not narrowed
  # further than to the bucket itself.
  statement {
    sid       = "ArtifactBucket"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }

  # Builds resolve dependencies from any repository of the account's CodeArtifact domains, not only
  # from the one this module creates.
  statement {
    sid = "CodeArtifact"
    actions = [
      "codeartifact:GetAuthorizationToken",
      "codeartifact:GetRepositoryEndpoint",
      "codeartifact:PublishPackageVersion",
      "codeartifact:PutPackageMetadata",
      "codeartifact:ReadFromRepository",
    ]
    resources = ["arn:aws:codeartifact:${local.region}:${local.account_id}:*"]
  }

  statement {
    sid       = "CodeArtifactToken"
    actions   = ["sts:GetServiceBearerToken"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "sts:AWSServiceName"
      values   = ["codeartifact.amazonaws.com"]
    }
  }

  dynamic "statement" {
    for_each = var.ecr_repository.enabled ? [1] : []
    content {
      sid       = "EcrLogin"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.ecr_repository.enabled ? [1] : []
    content {
      sid = "EcrPushPull"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
      ]
      resources = [aws_ecr_repository.this[0].arn]
    }
  }

  dynamic "statement" {
    for_each = length(local.deployment_environments) > 0 ? [1] : []
    content {
      sid       = "AssumeDeploymentRole"
      actions   = ["sts:AssumeRole"]
      resources = [for environment in local.deployment_environments : "arn:aws:iam::${var.environments[environment]}:role/${var.deployment_role.name}"]
    }
  }

  # A full clone makes CodeBuild itself fetch the repository through the connection.
  dynamic "statement" {
    for_each = local.full_clone ? [1] : []
    content {
      sid       = "UseSourceConnection"
      actions   = local.use_connection_actions
      resources = [var.source_repository.connection_arn]
    }
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${local.names.iam_role_prefix}CodebuildPolicy"
  role   = aws_iam_role.codebuild.name
  policy = data.aws_iam_policy_document.codebuild.json
}
