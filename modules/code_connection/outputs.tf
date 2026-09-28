output "arn" {
  description = "ARN of the connection, for source_repository.connection_arn."
  value       = aws_codeconnections_connection.this.arn
}

output "status" {
  description = "PENDING until the handshake is completed in the AWS console, AVAILABLE afterwards."
  value       = aws_codeconnections_connection.this.connection_status
}
