# Outputs for Vector Configuration
# =================================

output "vector_dcr_uri" {
  description = "Complete DCR URI"
  value       = "${azapi_resource.dcr.output.properties.endpoints.logsIngestion}/dataCollectionRules/${azapi_resource.dcr.output.properties.immutableId}/streams/${local.stream_name}?api-version=2023-01-01"
}

# Service Principal Credentials for Vector
# ========================================

output "tenant_id" {
  description = "Azure AD Tenant ID"
  value       = data.azuread_client_config.current.tenant_id
}

output "client_id" {
  description = "Service Principal Client ID (Application ID)"
  value       = azuread_application.vector.client_id
}

output "client_secret" {
  description = "Service Principal Client Secret"
  value       = azuread_application_password.vector.value
  sensitive   = true
}

# Curl test command
output "curl_test_command" {
  description = "Command to test the endpoint with the service principal"
  value       = <<-EOT
    # Get token using service principal
    TOKEN=$(curl -s -X POST "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=${azuread_application.vector.client_id}" \
      -d "client_secret=$(terraform output -raw client_secret)" \
      -d "scope=https://monitor.azure.com/.default" \
      -d "grant_type=client_credentials" | jq -r '.access_token')

    # Send test event
    curl -X POST "${azapi_resource.dcr.output.properties.endpoints.logsIngestion}/dataCollectionRules/${azapi_resource.dcr.output.properties.immutableId}/streams/${local.stream_name}?api-version=2023-01-01" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '[{"TimeGenerated": "'$(date -u +%%Y-%%m-%%dT%%H:%%M:%%SZ)'", "DeviceVendor": "Test", "DeviceProduct": "Test", "Message": "Hello from curl"}]'
  EOT
}
