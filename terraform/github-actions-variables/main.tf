locals {
  base_github_actions_vars = {
    IAP_USE_WIF         = var.iap_use_wif
    GCP_PROJECT_ID      = var.gcp_project_id
    JF_HOST             = var.jf_host
    JF_PROJECT_KEY      = var.jf_project_key
    IAP_OAUTH_CLIENT_ID = var.iap_oauth_client_id
  }

  optional_github_actions_vars = merge(
    trimspace(var.jf_host_cli) == "" ? {} : { JF_HOST_CLI = trimspace(var.jf_host_cli) },
    trimspace(var.jf_docker_username) == "" ? {} : { JF_DOCKER_USERNAME = trimspace(var.jf_docker_username) },
  )

  github_actions_vars = merge(local.base_github_actions_vars, local.optional_github_actions_vars)
}

resource "github_actions_variable" "repo" {
  for_each = local.github_actions_vars

  repository    = var.github_repository
  variable_name = each.key
  value         = each.value
}
