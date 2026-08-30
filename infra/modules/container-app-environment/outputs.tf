output "id" {
  value = azurerm_container_app_environment.this.id
}

output "default_domain" {
  value       = azurerm_container_app_environment.this.default_domain
  description = <<-EOT
    The environment's DNS suffix -- combined with a container app's name
    (never its `latest_revision_fqdn`) to build a URL that survives revision
    changes. See modules/container-app/outputs.tf for why this matters.
  EOT
}
