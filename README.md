# aws_repository_with_ci

This Terraform module sets up a full CI environment in AWS:

- **Source**: AWS CodePipeline with **GitLab** via CodeStar Connections  
- **Build**: AWS CodeBuild projects  
- **Artifacts**: AWS CodeArtifact repository, Amazon ECR, and S3 artifact store  
- **IAM roles**: Least-privilege roles for CodePipeline, CodeBuild, ECR access  

## Usage

```hcl
module "ci" {
  source                     = "spryfox-analytics/aws_repository_with_ci/aws"
  version                    = "1.1.0"

  # --- identification ---
  customer                   = "acme"
  project                    = "my-app"
  application                = "backend"

  # --- AWS accounts & region ---
  aws_region                 = "eu-central-1"
  aws_development_account_number   = "111122223333"
  aws_integration_account_number   = "222233334444"
  aws_production_account_number    = "333344445555"

  # --- GitLab connection & repo ---
  gitlab_connection_name     = "acme-gitlab-conn"
  gitlab_provider_type       = "GitLab"
  gitlab_repository_path     = "acme-group/my-app"

  # You must have created a CodeStar Connection named "acme-gitlab-conn"
  # or else this module will create it (you must finish the auth handshake).

  # --- Terraform repo names for IAM naming ---
  repository_camel_case_name = "AcmeMyApp"

  # --- CodeArtifact & ECR names ---
  codeartifact_domain_name   = "acme-domain"
  ecr_repository_camel_case_name = "AcmeMyAppECR"

  # --- Pipeline actions (default: build only) ---
  pipeline_actions = [
    {
      name                   = "build"
      category               = "Build"
      provider               = "CodeBuild"
      input_artifacts        = ["SourceArtifact"]
      output_artifacts       = ["BuildArtifact"]
      buildspec              = "buildspec.yml"
      codebuild_project_index = 0
    }
  ]

  # --- Optional: extra env vars in CodeBuild ---
  additional_environment_variables = {
    FOO = "bar"
  }
}
