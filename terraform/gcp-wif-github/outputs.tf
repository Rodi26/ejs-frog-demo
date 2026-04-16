output "project_number" {
  description = "Project number (used in WIF resource names)."
  value       = data.google_project.current.number
}

output "service_account_email" {
  description = "Set GitHub secret GCP_WIF_SERVICE_ACCOUNT to this value."
  value       = google_service_account.github_ci.email
}

output "workload_identity_provider" {
  description = "Set GitHub secret WORKLOAD_IDENTITY_PROVIDER to this full resource name."
  value       = google_iam_workload_identity_pool_provider.github_oidc.name
}

output "github_actions_vars_hint" {
  description = "Suggested repository variables (create manually or use terraform/github-actions-variables/)."
  value       = <<-EOT
    IAP_USE_WIF=true
    GCP_PROJECT_ID=${var.project_id}
    JF_HOST=<Artifactory hostname only, e.g. artifactory.example.org>
    JF_PROJECT_KEY=<JFrog Platform project key>
    IAP_OAUTH_CLIENT_ID=<OAuth 2.0 Client ID from IAP / APIs Credentials — *.apps.googleusercontent.com>
    (optional) JF_HOST_CLI=<second hostname for jf when IAP blocks Bearer-only>
    (optional) JF_DOCKER_USERNAME=<Artifactory user for Docker Basic auth via proxy>
  EOT
}
