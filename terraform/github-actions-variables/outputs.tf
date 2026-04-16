output "variables_created" {
  description = "Repository variable names applied (GitHub Actions configuration variables)."
  value       = keys(local.github_actions_vars)
}

output "repository" {
  description = "Target repository (owner/name)."
  value       = "${var.github_owner}/${var.github_repository}"
}
