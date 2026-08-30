output "fqdn" {
  value       = azurerm_container_app.this.latest_revision_fqdn
  description = "Public URL of the deployed API (domain/08-phases.md, Phase 5 gate: a real URL, not a claim)."
}

output "id" {
  value = azurerm_container_app.this.id
}

output "identity_principal_id" {
  value = azurerm_user_assigned_identity.acr_pull.principal_id
}
