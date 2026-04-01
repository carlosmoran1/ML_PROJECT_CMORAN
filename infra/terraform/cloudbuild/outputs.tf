output "cloudbuild_connection_name" {
  value = google_cloudbuildv2_connection.github.name
}

output "cloudbuild_repository_id" {
  value = google_cloudbuildv2_repository.repo.id
}

output "trigger_names" {
  value = [
    google_cloudbuild_trigger.etl.name,
    google_cloudbuild_trigger.sarimax.name,
    google_cloudbuild_trigger.autogluon.name,
    google_cloudbuild_trigger.features.name
  ]
}