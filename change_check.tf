# Stage conditions that skip the deploy stages when the pipeline's directory did not change since
# the last successful execution. Needed where the provider cannot filter triggers by file path,
# notably Azure DevOps: every push starts every pipeline of the repository, and the stages of the
# pipelines whose directory is unchanged are skipped. See change_check/index.py.

data "archive_file" "change_check" {
  count = local.skip_unchanged ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/change_check/index.py"
  output_path = "${path.root}/.terraform/tmp/${local.names.change_check_function}.zip"
}

resource "aws_cloudwatch_log_group" "change_check" {
  count = local.skip_unchanged ? 1 : 0

  name              = "/aws/lambda/${local.names.change_check_function}"
  retention_in_days = 30
  tags              = local.tags
}

data "aws_iam_policy_document" "change_check_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "change_check" {
  count = local.skip_unchanged ? 1 : 0

  name               = "${local.names.iam_role_prefix}ChangeCheckRole"
  assume_role_policy = data.aws_iam_policy_document.change_check_assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "change_check" {
  count = local.skip_unchanged ? 1 : 0

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.change_check[0].arn}:*"]
  }

  statement {
    sid       = "ReadSources"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "ReadExecutions"
    actions   = ["codepipeline:GetPipelineExecution", "codepipeline:ListPipelineExecutions", "codepipeline:ListActionExecutions"]
    resources = ["arn:aws:codepipeline:${local.region}:${local.account_id}:${local.names.pipeline}"]
  }

  # Jobs have no ARN of their own.
  statement {
    sid       = "ReportResult"
    actions   = ["codepipeline:PutJobFailureResult", "codepipeline:PutJobSuccessResult"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "change_check" {
  count = local.skip_unchanged ? 1 : 0

  name   = "${local.names.iam_role_prefix}ChangeCheckPolicy"
  role   = aws_iam_role.change_check[0].id
  policy = data.aws_iam_policy_document.change_check[0].json
}

resource "aws_lambda_function" "change_check" {
  count = local.skip_unchanged ? 1 : 0

  function_name    = local.names.change_check_function
  description      = "Skips the stages of ${local.names.pipeline} when ${coalesce(local.source_directory, "the repository")} did not change."
  role             = aws_iam_role.change_check[0].arn
  runtime          = "python3.13"
  handler          = "index.handler"
  filename         = data.archive_file.change_check[0].output_path
  source_code_hash = data.archive_file.change_check[0].output_base64sha256
  memory_size      = 256
  timeout          = 60
  tags             = merge(local.tags, { Name = local.names.change_check_function })

  depends_on = [aws_cloudwatch_log_group.change_check, aws_iam_role_policy.change_check]

  lifecycle {
    precondition {
      condition     = length(local.names.change_check_function) <= 64
      error_message = "The Lambda function name \"${local.names.change_check_function}\" exceeds 64 characters; set resource_names.change_check_function."
    }
  }
}
