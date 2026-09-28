# One connection serves every repository the provider account can see, so it is created once per
# AWS account and provider and shared by all pipelines.
#
# AWS creates it in the PENDING state. It becomes usable only after someone completes the handshake
# in the AWS console (Developer Tools > Settings > Connections > Update pending connection), which
# installs the AWS connector app in the provider account and therefore needs administrative rights
# there.
resource "aws_codeconnections_connection" "this" {
  name          = var.name
  provider_type = var.provider_type
  host_arn      = var.host_arn
  tags          = var.tags
}
