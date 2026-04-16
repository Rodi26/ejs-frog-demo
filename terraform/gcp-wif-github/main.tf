data "google_project" "current" {
  project_id = var.project_id
}

locals {
  # GitHub Actions OIDC attribute condition (CEL). See:
  # https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines
  attribute_condition = (
    var.restrict_to_single_repo && var.github_repo_full != ""
    ? "assertion.repository=='${var.github_repo_full}'"
    : "assertion.repository_owner=='${var.github_org}'"
  )

  # Federated principals that may impersonate the SA: entire pool subject to provider condition.
  wif_principal_set = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/*"
}

resource "google_project_service" "required_apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = var.pool_display_name
  description               = "OIDC federation for GitHub Actions (IAP + CI)."
  disabled                  = false

  depends_on = [google_project_service.required_apis]
}

resource "google_iam_workload_identity_pool_provider" "github_oidc" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub OIDC"
  description                        = "token.actions.githubusercontent.com"
  disabled                           = false

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  attribute_condition = local.attribute_condition

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_ci" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = var.service_account_display_name
}

# Allow GitHub OIDC identities (matching provider condition) to impersonate this SA.
resource "google_service_account_iam_member" "wif_impersonate" {
  service_account_id = google_service_account.github_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.wif_principal_set
}

# Required for IAM Credentials API generateIdToken (IAP OIDC audience) when acting as this SA.
# Without it: Permission iam.serviceAccounts.getOpenIdToken denied.
resource "google_service_account_iam_member" "github_ci_openid_token_self" {
  service_account_id = google_service_account.github_ci.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.github_ci.email}"
}
