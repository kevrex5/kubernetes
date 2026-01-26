# Vector Test Infrastructure - Azure Log Analytics DCR
# ====================================================
# Creates a Data Collection Rule with kind=Direct for testing Vector
# The Direct kind automatically creates a log ingestion endpoint

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.90.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 1.12.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "azuread" {}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_workspace_name
  resource_group_name = var.resource_group_name
}

# -----------------------------------------------------------------------------
# Custom Table (CEF logs stored in custom table)
# -----------------------------------------------------------------------------

resource "azapi_resource" "custom_table" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "${var.table_name}_CL"
  parent_id = data.azurerm_log_analytics_workspace.this.id

  body = {
    properties = {
      plan = var.table_plan
      schema = {
        name    = "${var.table_name}_CL"
        columns = local.cef_schema_columns
      }
      retentionInDays      = var.retention_in_days
      totalRetentionInDays = var.total_retention_in_days
    }
  }

  lifecycle {
    ignore_changes = [
      # Table schema updates can be tricky, ignore after creation
      body["properties"]["schema"]["columns"]
    ]
  }
}

# -----------------------------------------------------------------------------
# Data Collection Rule (kind=Direct with built-in logsIngestion endpoint)
# Note: logsIngestion property available since March 31, 2024 - no DCE required
# -----------------------------------------------------------------------------

resource "azapi_resource" "dcr" {
  type                   = "Microsoft.Insights/dataCollectionRules@2024-03-11"
  name                   = var.dcr_name
  location               = data.azurerm_resource_group.this.location
  parent_id              = data.azurerm_resource_group.this.id
  tags                   = var.tags
  response_export_values = ["properties.immutableId", "properties.endpoints"]

  depends_on = [azapi_resource.custom_table]

  body = {
    kind = "Direct"
    properties = {
      destinations = {
        logAnalytics = [
          {
            workspaceResourceId = data.azurerm_log_analytics_workspace.this.id
            name                = "law-destination"
          }
        ]
      }
      dataFlows = [
        {
          streams      = [local.stream_name]
          destinations = ["law-destination"]
          transformKql = var.transform_kql
          outputStream = "Custom-${var.table_name}_CL"
        }
      ]
      streamDeclarations = {
        (local.stream_name) = {
          columns = local.cef_schema_columns
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  stream_name = "Custom-${var.table_name}"

  # CEF (Common Event Format) schema for CommonSecurityLog-style table
  # Microsoft Sentinel standard schema
  cef_schema_columns = [
    { name = "TimeGenerated", type = "datetime" },
    { name = "Computer", type = "string" },
    { name = "DeviceVendor", type = "string" },
    { name = "DeviceProduct", type = "string" },
    { name = "DeviceVersion", type = "string" },
    { name = "DeviceEventClassID", type = "string" },
    { name = "Activity", type = "string" },
    { name = "LogSeverity", type = "string" },
    { name = "AdditionalExtensions", type = "string" },
    { name = "ApplicationProtocol", type = "string" },
    { name = "CommunicationDirection", type = "string" },
    { name = "DestinationDnsDomain", type = "string" },
    { name = "DestinationHostName", type = "string" },
    { name = "DestinationIP", type = "string" },
    { name = "DestinationNTDomain", type = "string" },
    { name = "DestinationPort", type = "int" },
    { name = "DestinationProcessId", type = "int" },
    { name = "DestinationProcessName", type = "string" },
    { name = "DestinationServiceName", type = "string" },
    { name = "DestinationTranslatedAddress", type = "string" },
    { name = "DestinationTranslatedPort", type = "int" },
    { name = "DestinationUserName", type = "string" },
    { name = "DestinationUserPrivileges", type = "string" },
    { name = "DeviceAction", type = "string" },
    { name = "DeviceAddress", type = "string" },
    { name = "DeviceCustomDate1", type = "string" },
    { name = "DeviceCustomDate1Label", type = "string" },
    { name = "DeviceCustomDate2", type = "string" },
    { name = "DeviceCustomDate2Label", type = "string" },
    { name = "DeviceCustomFloatingPoint1", type = "real" },
    { name = "DeviceCustomFloatingPoint2", type = "real" },
    { name = "DeviceCustomFloatingPoint3", type = "real" },
    { name = "DeviceCustomFloatingPoint4", type = "real" },
    { name = "DeviceCustomIPv6Address1", type = "string" },
    { name = "DeviceCustomIPv6Address1Label", type = "string" },
    { name = "DeviceCustomIPv6Address2", type = "string" },
    { name = "DeviceCustomIPv6Address2Label", type = "string" },
    { name = "DeviceCustomIPv6Address3", type = "string" },
    { name = "DeviceCustomIPv6Address3Label", type = "string" },
    { name = "DeviceCustomIPv6Address4", type = "string" },
    { name = "DeviceCustomIPv6Address4Label", type = "string" },
    { name = "DeviceCustomNumber1", type = "int" },
    { name = "DeviceCustomNumber1Label", type = "string" },
    { name = "DeviceCustomNumber2", type = "int" },
    { name = "DeviceCustomNumber2Label", type = "string" },
    { name = "DeviceCustomNumber3", type = "int" },
    { name = "DeviceCustomNumber3Label", type = "string" },
    { name = "DeviceDnsDomain", type = "string" },
    { name = "DeviceEventCategory", type = "string" },
    { name = "DeviceFacility", type = "string" },
    { name = "DeviceInboundInterface", type = "string" },
    { name = "DeviceMacAddress", type = "string" },
    { name = "DeviceName", type = "string" },
    { name = "DeviceNtDomain", type = "string" },
    { name = "DeviceOutboundInterface", type = "string" },
    { name = "DevicePayloadId", type = "string" },
    { name = "DeviceTimeZone", type = "string" },
    { name = "DeviceTranslatedAddress", type = "string" },
    { name = "EventCount", type = "int" },
    { name = "EventOutcome", type = "string" },
    { name = "EventType", type = "int" },
    { name = "ExternalID", type = "int" },
    { name = "FileCreateTime", type = "string" },
    { name = "FileHash", type = "string" },
    { name = "FileID", type = "string" },
    { name = "FileModificationTime", type = "string" },
    { name = "FileName", type = "string" },
    { name = "FilePath", type = "string" },
    { name = "FilePermission", type = "string" },
    { name = "FileSize", type = "int" },
    { name = "FileType", type = "string" },
    { name = "FlexDate1", type = "string" },
    { name = "FlexDate1Label", type = "string" },
    { name = "FlexNumber1", type = "int" },
    { name = "FlexNumber1Label", type = "string" },
    { name = "FlexNumber2", type = "int" },
    { name = "FlexNumber2Label", type = "string" },
    { name = "FlexString1", type = "string" },
    { name = "FlexString1Label", type = "string" },
    { name = "FlexString2", type = "string" },
    { name = "FlexString2Label", type = "string" },
    { name = "Message", type = "string" },
    { name = "OldFileCreateTime", type = "string" },
    { name = "OldFileHash", type = "string" },
    { name = "OldFileModificationTime", type = "string" },
    { name = "OldFileName", type = "string" },
    { name = "OldFilePath", type = "string" },
    { name = "OldFilePermission", type = "string" },
    { name = "OldFileSize", type = "int" },
    { name = "OldFileType", type = "string" },
    { name = "ProcessName", type = "string" },
    { name = "Protocol", type = "string" },
    { name = "Reason", type = "string" },
    { name = "ReceiptTime", type = "string" },
    { name = "ReceivedBytes", type = "long" },
    { name = "RequestClientApplication", type = "string" },
    { name = "RequestContext", type = "string" },
    { name = "RequestCookies", type = "string" },
    { name = "RequestMethod", type = "string" },
    { name = "RequestURL", type = "string" },
    { name = "SentBytes", type = "long" },
    { name = "SourceDnsDomain", type = "string" },
    { name = "SourceHostName", type = "string" },
    { name = "SourceIP", type = "string" },
    { name = "SourceNTDomain", type = "string" },
    { name = "SourcePort", type = "int" },
    { name = "SourceProcessId", type = "int" },
    { name = "SourceProcessName", type = "string" },
    { name = "SourceServiceName", type = "string" },
    { name = "SourceTranslatedAddress", type = "string" },
    { name = "SourceTranslatedPort", type = "int" },
    { name = "SourceUserID", type = "string" },
    { name = "SourceUserName", type = "string" },
    { name = "SourceUserPrivileges", type = "string" },
  ]
}

# -----------------------------------------------------------------------------
# Azure AD Application & Service Principal for Vector
# -----------------------------------------------------------------------------

data "azuread_client_config" "current" {}

resource "azuread_application" "vector" {
  display_name = var.service_principal_name
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "vector" {
  client_id                    = azuread_application.vector.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "time_rotating" "secret_rotation" {
  rotation_days = 90
}

resource "azuread_application_password" "vector" {
  application_id = azuread_application.vector.id
  display_name   = "vector-test-secret"
  rotate_when_changed = {
    rotation = time_rotating.secret_rotation.id
  }
}

# -----------------------------------------------------------------------------
# Role Assignment - Monitoring Metrics Publisher on DCR
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "vector_metrics_publisher" {
  scope                = azapi_resource.dcr.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azuread_service_principal.vector.object_id
}
