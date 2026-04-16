variable "github_owner" {
  type        = string
  description = "GitHub organization or user that owns the repository (same idea as WIF github_org)."
}

variable "github_repository" {
  type        = string
  description = "Repository name only, e.g. ejs-frog-demo (not ORG/NAME)."
}

variable "github_token" {
  type        = string
  description = "PAT with repo scope (classic) or fine-grained token with Variables read/write on the repo. Use TF_VAR_github_token or env, do not commit."
  sensitive   = true
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID — sets repository variable GCP_PROJECT_ID (workflows / IAP)."
}

variable "jf_host" {
  type        = string
  description = "Artifactory public hostname only (no https://), e.g. artifactory.example.org — sets JF_HOST."
}

variable "jf_project_key" {
  type        = string
  description = "JFrog Platform project key — sets JF_PROJECT_KEY."
}

variable "iap_oauth_client_id" {
  type        = string
  description = "Google OAuth 2.0 Client ID used as IAP audience (*.apps.googleusercontent.com) — sets IAP_OAUTH_CLIENT_ID."
}

variable "iap_use_wif" {
  type        = string
  description = "Repository variable IAP_USE_WIF; use \"true\" to run WIF + IAP steps in workflows."
  default     = "true"
}

variable "jf_host_cli" {
  type        = string
  description = "Optional second hostname for jf when IAP blocks Authorization alone. If empty, variable JF_HOST_CLI is not created."
  default     = ""
}

variable "jf_docker_username" {
  type        = string
  description = "Optional Artifactory user for Docker Basic auth via proxy. If empty, JF_DOCKER_USERNAME is not created."
  default     = ""
}
