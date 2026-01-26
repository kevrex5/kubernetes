# Variables for Vector Test Infrastructure
# =========================================

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group containing the Log Analytics workspace"
  type        = string
}

variable "log_analytics_workspace_name" {
  description = "Name of the existing Log Analytics workspace"
  type        = string
}

variable "dcr_name" {
  description = "Name of the Data Collection Rule"
  type        = string
  default     = "dcr-vector-cef-test"
}

variable "table_name" {
  description = "Name of the custom table (without _CL suffix)"
  type        = string
  default     = "VectorCEF"
}

variable "table_plan" {
  description = "Table plan: Analytics or Basic"
  type        = string
  default     = "Analytics"

  validation {
    condition     = contains(["Analytics", "Basic"], var.table_plan)
    error_message = "Table plan must be either 'Analytics' or 'Basic'."
  }
}

variable "retention_in_days" {
  description = "Data retention in days (minimum 4 for Basic, 30 for Analytics)"
  type        = number
  default     = 30
}

variable "total_retention_in_days" {
  description = "Total retention in days including archive"
  type        = number
  default     = 30
}

variable "transform_kql" {
  description = "KQL transformation query applied to incoming data"
  type        = string
  default     = "source"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Purpose     = "Vector Testing"
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

variable "service_principal_name" {
  description = "Display name for the Azure AD application/service principal"
  type        = string
  default     = "sp-vector-logs-ingestion-test"
}
