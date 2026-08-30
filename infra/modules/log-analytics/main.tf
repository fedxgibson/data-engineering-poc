# Required by Container Apps Environment for platform logs (revision starts/stops,
# ingress logs, console output from the container). Not wired into the app's own
# OpenTelemetry traces (agent/tracing.py) -- those stay on the console/Jaeger
# exporters documented in domain/08-phases.md; this workspace is Azure's own
# infrastructure-level logging, a separate concern.
resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  retention_in_days    = var.retention_in_days
  tags                = var.tags
}
