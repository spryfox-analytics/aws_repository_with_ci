# Keeps at most one run waiting at each manual approval of the deploy stages, the newest one, when
# supersede_waiting_approvals is on. Every approval action is a gate whose trigger is the stage in
# front of the approval's stage. One function and one EventBridge rule serve all gates of the
# pipeline. See approval_superseder/index.py.

locals {
  approval_gates = flatten([
    for i, stage in local.stages : [
      for action in stage.actions : {
        previous_stage  = i == 0 ? "Source" : local.stages[i - 1].name
        previous_action = i == 0 ? "Source" : local.stages[i - 1].actions[length(local.stages[i - 1].actions) - 1].name
        approval_stage  = stage.name
        approval_action = action.name
      } if action.category == "Approval"
    ]
  ])
  supersede_approvals = var.supersede_waiting_approvals && length(local.approval_gates) > 0
  pipeline_arn        = "arn:aws:codepipeline:${local.region}:${local.account_id}:${local.names.pipeline}"
}

data "archive_file" "approval_superseder" {
  count = local.supersede_approvals ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/approval_superseder/index.py"
  output_path = "${path.root}/.terraform/tmp/${local.names.approval_superseder_function}.zip"
}

resource "aws_cloudwatch_log_group" "approval_superseder" {
  count = local.supersede_approvals ? 1 : 0

  name              = "/aws/lambda/${local.names.approval_superseder_function}"
  retention_in_days = 30
  tags              = local.tags
}

resource "aws_iam_role" "approval_superseder" {
  count = local.supersede_approvals ? 1 : 0

  name               = "${local.names.iam_role_prefix}ApprovalSupersederRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "approval_superseder" {
  count = local.supersede_approvals ? 1 : 0

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.approval_superseder[0].arn}:*"]
  }

  statement {
    sid       = "SupersedeRuns"
    actions   = ["codepipeline:GetPipelineState", "codepipeline:ListPipelineExecutions", "codepipeline:ListActionExecutions", "codepipeline:StopPipelineExecution"]
    resources = [local.pipeline_arn, "${local.pipeline_arn}/*"]
  }
}

resource "aws_iam_role_policy" "approval_superseder" {
  count = local.supersede_approvals ? 1 : 0

  name   = "${local.names.iam_role_prefix}ApprovalSupersederPolicy"
  role   = aws_iam_role.approval_superseder[0].id
  policy = data.aws_iam_policy_document.approval_superseder[0].json
}

resource "aws_lambda_function" "approval_superseder" {
  count = local.supersede_approvals ? 1 : 0

  function_name    = local.names.approval_superseder_function
  description      = "Stops a run of ${local.names.pipeline} waiting at an approval once a newer run has finished the stage in front of it."
  role             = aws_iam_role.approval_superseder[0].arn
  runtime          = "python3.13"
  handler          = "index.handler"
  filename         = data.archive_file.approval_superseder[0].output_path
  source_code_hash = data.archive_file.approval_superseder[0].output_base64sha256
  timeout          = 30
  tags             = merge(local.tags, { Name = local.names.approval_superseder_function })

  environment {
    variables = {
      PIPELINE_NAME = local.names.pipeline
      GATES         = jsonencode(local.approval_gates)
    }
  }

  depends_on = [aws_cloudwatch_log_group.approval_superseder, aws_iam_role_policy.approval_superseder]

  lifecycle {
    precondition {
      condition     = length(local.names.approval_superseder_function) <= 64
      error_message = "The Lambda function name \"${local.names.approval_superseder_function}\" exceeds 64 characters; set resource_names.approval_superseder_function."
    }
  }
}

# Runs the function when a run finishes a stage in front of an approval and when a run reaches an
# approval.
resource "aws_cloudwatch_event_rule" "approval_superseder" {
  count = local.supersede_approvals ? 1 : 0

  name        = local.names.approval_superseder_function
  description = "Supersedes a run waiting at an approval of ${local.names.pipeline} by a newer run"
  event_pattern = jsonencode({
    source = ["aws.codepipeline"]
    "$or" = [
      {
        "detail-type" = ["CodePipeline Stage Execution State Change"]
        detail        = { pipeline = [local.names.pipeline], stage = distinct([for gate in local.approval_gates : gate.previous_stage]), state = ["SUCCEEDED"] }
      },
      {
        "detail-type" = ["CodePipeline Action Execution State Change"]
        detail        = { pipeline = [local.names.pipeline], action = [for gate in local.approval_gates : gate.approval_action], state = ["STARTED"] }
      },
    ]
  })
  tags = merge(local.tags, { Name = local.names.approval_superseder_function })
}

resource "aws_cloudwatch_event_target" "approval_superseder" {
  count = local.supersede_approvals ? 1 : 0

  rule = aws_cloudwatch_event_rule.approval_superseder[0].name
  arn  = aws_lambda_function.approval_superseder[0].arn
}

resource "aws_lambda_permission" "approval_superseder" {
  count = local.supersede_approvals ? 1 : 0

  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.approval_superseder[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.approval_superseder[0].arn
}
