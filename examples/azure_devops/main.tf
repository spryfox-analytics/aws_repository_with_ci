# A containerised service in Azure DevOps, built on every push to main and published to ECR.

provider "aws" {
  region = "eu-west-1"
}

module "azure_devops_connection" {
  source = "../../modules/code_connection"

  name          = "azure-devops"
  provider_type = "AzureDevOps"
}

module "my_service" {
  source = "../.."

  name = "my-service"
  source_repository = {
    connection_arn = module.azure_devops_connection.arn
    repository_id  = "my-organization/my-project/my-service"
  }

  environments = {
    dev  = "222222222222"
    prod = "444444444444"
  }

  tags = {
    Customer = "My Customer"
    Project  = "My Project"
  }
}
