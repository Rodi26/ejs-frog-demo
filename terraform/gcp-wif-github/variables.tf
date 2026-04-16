variable "project_id" {
  type        = string
  description = "GCP project ID (string, e.g. my-prod-project)."
}

variable "region" {
  type        = string
  description = "Region for the provider block (WIF pool is still global)."
  default     = "europe-west1"
}

variable "pool_id" {
  type        = string
  description = "Workload Identity Pool ID (immutable once created)."
  default     = "github-actions-pool"
}

variable "provider_id" {
  type        = string
  description = "OIDC provider ID inside the pool (GitHub)."
  default     = "github-provider"
}

variable "github_org" {
  type        = string
  description = "GitHub organization or username (used in attribute_condition)."
}

variable "github_repo_full" {
  type        = string
  description = "Optional. Restrict tokens to one repo, format ORG/NAME (e.g. Rodi26/ejs-frog-demo). Leave empty to allow any repo in the org matching github_org."
  default     = ""
}

variable "service_account_id" {
  type        = string
  description = "Short ID for the service account (e.g. github-ci-iap)."
  default     = "github-ci-iap"
}

variable "service_account_display_name" {
  type    = string
  default = "GitHub Actions — WIF + IAP CI"
}

variable "restrict_to_single_repo" {
  type        = bool
  description = "If true, attribute_condition uses assertion.repository == github_repo_full. If false, uses assertion.repository_owner == github_org."
  default     = false
}
