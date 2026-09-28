terraform {
  # Cross-variable references in validation blocks need 1.9.
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.8.0 is the first release whose CodeConnections client knows the AzureDevOps provider type.
      version = ">= 6.8.0"
    }
  }
}
