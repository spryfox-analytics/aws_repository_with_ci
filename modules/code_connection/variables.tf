variable "name" {
  description = "Name of the connection, at most 32 characters."
  type        = string

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 32
    error_message = "A connection name must be between 1 and 32 characters long."
  }
}

variable "provider_type" {
  description = "Git provider hosting the repositories, for cloud-hosted providers. Mutually exclusive with host_arn."
  type        = string
  default     = null

  validation {
    condition     = var.provider_type == null ? true : contains(["AzureDevOps", "Bitbucket", "GitHub", "GitLab"], var.provider_type)
    error_message = "provider_type must be one of AzureDevOps, Bitbucket, GitHub or GitLab. Self-managed installations are connected through host_arn."
  }
}

variable "host_arn" {
  description = "ARN of a CodeConnections host, for self-managed providers such as GitHub Enterprise Server or GitLab self-managed. Mutually exclusive with provider_type."
  type        = string
  default     = null

  validation {
    condition     = (var.host_arn == null) != (var.provider_type == null)
    error_message = "Set exactly one of provider_type and host_arn."
  }
}

variable "tags" {
  description = "Tags for the connection."
  type        = map(string)
  default     = {}
}
