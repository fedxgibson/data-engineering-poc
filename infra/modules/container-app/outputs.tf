output "fqdn" {
  value = "${azurerm_container_app.this.name}.${var.environment_default_domain}"
  description = <<-EOT
    Public URL of the deployed app (domain/08-phases.md, Phase 5 gate: a real
    URL, not a claim). Deliberately NOT `latest_revision_fqdn` -- that
    attribute is the *per-revision* hostname (e.g. "app--abc123.env-domain"),
    which goes 404 the moment a new revision replaces the one it points to
    (revision_mode = "Single" tears down the old one). The env-domain-only
    hostname built here ("app.env-domain") is Container Apps' actual stable
    address, unaffected by which revision is currently active -- found the
    hard way when a manual `az containerapp update --revision-suffix ...`
    broke the previously-recorded live URL (domain/08-phases.md).
  EOT
}

output "id" {
  value = azurerm_container_app.this.id
}

output "identity_principal_id" {
  value = azurerm_user_assigned_identity.acr_pull.principal_id
}
