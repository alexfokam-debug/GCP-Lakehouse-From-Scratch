moved {
  from = google_iam_workload_identity_pool.github
  to   = google_iam_workload_identity_pool.github[0]
}

moved {
  from = google_iam_workload_identity_pool_provider.github
  to   = google_iam_workload_identity_pool_provider.github[0]
}

moved {
  from = google_service_account_iam_member.github_cicd_wif
  to   = google_service_account_iam_member.github_cicd_wif[0]
}