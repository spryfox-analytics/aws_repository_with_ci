resource "aws_iam_role" "cloudwatch_event" {
  name = "${var.codecommit_repository_camel_case_name}CloudwatchEventRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eb_to_pipeline" {
  name = "${var.codecommit_repository_camel_case_name}CloudwatchEventPolicy"
  role = aws_iam_role.cloudwatch_event.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codepipeline:StartPipelineExecution"]
      Resource = [aws_codepipeline.this.arn]
    }]
  })
}
