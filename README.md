# aws_repository_with_ci
This Terraform code allows for creating all resources required in a CI environment using AWS CodePipeline V2 with branch inclusion/exclusion filters. It leverages the AWS Cloud Control (awscc) provider to define a single pipeline that triggers on pushes to specified branches without requiring Terraform updates when branches change.
