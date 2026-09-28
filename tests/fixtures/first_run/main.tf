# A new project: the connection and the pipeline are created in the same configuration.

module "connection" {
  source = "../../../modules/code_connection"

  name          = "my-provider"
  provider_type = "AzureDevOps"
}

module "ci" {
  source = "../../.."

  name = "my-service"
  source_repository = {
    connection_arn = module.connection.arn
    repository_id  = "my-organization/my-project/my-service"
  }
}
