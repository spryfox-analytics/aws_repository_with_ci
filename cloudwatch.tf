resource "aws_cloudwatch_event_rule" "trigger" {
  for_each = aws_codepipeline.this
  name = "${each.value.name}-trigger"
  // if ["all"], don't filter on branch; otherwise only fire on that branch
  event_pattern = var.trigger_branches[0] == "all"
    ? jsonencode({
        source      = ["aws.codecommit"]
        "detail-type" = ["CodeCommit Repository State Change"]
        resources   = [aws_codecommit_repository.this.arn]
      })
    : jsonencode({
        source      = ["aws.codecommit"]
        "detail-type" = ["CodeCommit Repository State Change"]
        resources   = [aws_codecommit_repository.this.arn]
        detail = {
          referenceType = ["branch"]
          referenceName = [each.key]
        }
      })
}

resource "aws_cloudwatch_event_target" "start_pipeline" {
  for_each = aws_cloudwatch_event_rule.trigger
  rule      = each.value.name
  arn       = aws_codepipeline.this[each.key].arn
  role_arn  = aws_iam_role.cloudwatch_event.arn
  // we need to tell StartPipelineExecution which pipeline to kick off
  input     = jsonencode({ name = aws_codepipeline.this[each.key].name })
}
