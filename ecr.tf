resource "aws_ecr_repository" "this" {
  count = var.ecr_repository.enabled ? 1 : 0

  name                 = local.names.ecr_repository
  image_tag_mutability = var.ecr_repository.image_tag_mutability
  # Never let Terraform delete a repository that still holds images; removing it takes a
  # deliberate cleanup first.
  force_delete = false

  image_scanning_configuration {
    scan_on_push = var.ecr_repository.scan_on_push
  }

  tags = merge(local.tags, { Name = local.names.ecr_repository })
}

data "aws_iam_policy_document" "ecr" {
  count = var.ecr_repository.enabled && (length(local.environment_account_ids) > 0 || var.ecr_repository.lambda_read_access) ? 1 : 0

  statement {
    sid    = "ReadonlyAccess"
    effect = "Allow"

    dynamic "principals" {
      for_each = length(local.environment_account_ids) > 0 ? [1] : []
      content {
        type        = "AWS"
        identifiers = local.environment_account_ids
      }
    }

    dynamic "principals" {
      for_each = var.ecr_repository.lambda_read_access ? [1] : []
      content {
        type        = "Service"
        identifiers = ["lambda.amazonaws.com"]
      }
    }

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:DescribeRepositories",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:ListImages",
      "ecr:ListTagsForResource",
    ]
  }
}

resource "aws_ecr_repository_policy" "this" {
  count = length(data.aws_iam_policy_document.ecr)

  repository = aws_ecr_repository.this[0].name
  policy     = data.aws_iam_policy_document.ecr[0].json
}
