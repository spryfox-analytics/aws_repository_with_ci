resource "aws_cloudwatch_event_rule" "this" {
  name = "${aws_codecommit_repository.this.repository_name}-trigger"
  event_pattern = jsonencode({
    source        = ["aws.codecommit"]
    "detail-type" = ["CodeCommit Repository State Change"]
    resources     = [aws_codecommit_repository.this.arn]
    detail = {
      referenceType = ["branch"]
    }
  })
}

resource "aws_cloudwatch_event_target" "this" {
  rule     = aws_cloudwatch_event_rule.this.name
  arn      = aws_codepipeline.this.arn
  role_arn = aws_iam_role.cloudwatch_event.arn
  input_transformer {
    input_paths = {
      branch = "$.detail.referenceName"
    }
    input_template = <<TEMPLATE
{
  "name":"${aws_codepipeline.this.name}",
  "environmentVariablesOverride":[
    {"name":"TRIGGER_BRANCH","value":"<branch>","type":"PLAINTEXT"}
  ]
}
TEMPLATE
  }
}
