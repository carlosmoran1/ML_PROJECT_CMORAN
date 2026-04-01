data "google_project" "current" {
  project_id = var.project_id
}

locals {
  cloud_build_service_agent   = "service-${data.google_project.current.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  github_token_secret_version = "projects/${var.project_id}/secrets/${var.github_token_secret_id}/versions/${var.github_token_secret_version}"
}

resource "google_project_service" "apis" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "iam.googleapis.com"
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Bootstrap seguro:
# en vez de dar roles/secretmanager.admin a nivel proyecto,
# se otorga solo sobre el secreto que usa la conexión GitHub.
# Cuando la conexión quede COMPLETE, este bloque se puede cambiar
# por roles/secretmanager.secretAccessor sobre el mismo secreto.
resource "google_secret_manager_secret_iam_member" "cloudbuild_secret_admin" {
  project   = var.project_id
  secret_id = var.github_token_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.cloud_build_service_agent}"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "cicd_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${var.cicd_service_account_email}"
}

resource "google_project_iam_member" "cicd_artifactregistry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${var.cicd_service_account_email}"
}

resource "google_storage_bucket_iam_member" "cicd_bucket_object_admin" {
  bucket = var.bucket_raw
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.cicd_service_account_email}"
}

resource "google_service_account_iam_member" "cicd_act_as_runtime" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.runtime_service_account_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.cicd_service_account_email}"
}

resource "google_cloudbuildv2_connection" "github" {
  provider = google-beta
  project  = var.project_id
  location = var.region
  name     = var.connection_name

  github_config {
    app_installation_id = var.github_app_installation_id

    authorizer_credential {
      oauth_token_secret_version = local.github_token_secret_version
    }
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_iam_member.cloudbuild_secret_admin
  ]
}

resource "google_cloudbuildv2_repository" "repo" {
  provider          = google-beta
  project           = var.project_id
  location          = var.region
  name              = var.repository_resource_name
  parent_connection = google_cloudbuildv2_connection.github.name
  remote_uri        = "https://github.com/${var.github_owner}/${var.github_repo}.git"
}

resource "google_cloudbuild_trigger" "etl" {
  project         = var.project_id
  location        = var.region
  name            = "trigger-etl-market-data"
  description     = "Redeploy ETL when ETL code changes"
  filename        = "ci/cloudbuild.etl.yaml"
  service_account = "projects/${var.project_id}/serviceAccounts/${var.cicd_service_account_email}"

  included_files = [
    "src/pipelines/etl_market_data/**",
    "src/common/gcp_utils.py",
    "Dockerfile",
    "requirements.txt"
  ]

  substitutions = {
    _REGION           = var.region
    _AR_REPO          = var.artifact_repo
    _RUNTIME_SA_EMAIL = var.runtime_service_account_email
    _BUCKET_RAW       = var.bucket_raw
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.repo.id

    push {
      branch = var.branch_regex
    }
  }

  depends_on = [google_cloudbuildv2_repository.repo]
}

resource "google_cloudbuild_trigger" "sarimax" {
  project         = var.project_id
  location        = var.region
  name            = "trigger-sarimax"
  description     = "Redeploy SARIMAX when SARIMAX code changes"
  filename        = "ci/cloudbuild.sarimax.yaml"
  service_account = "projects/${var.project_id}/serviceAccounts/${var.cicd_service_account_email}"

  included_files = [
    "src/sarimax/**",
    "src/common/ml_gcp_utils.py",
    "Dockerfile",
    "requirements.txt"
  ]

  substitutions = {
    _REGION           = var.region
    _AR_REPO          = var.artifact_repo
    _RUNTIME_SA_EMAIL = var.runtime_service_account_email
    _BUCKET_RAW       = var.bucket_raw
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.repo.id

    push {
      branch = var.branch_regex
    }
  }

  depends_on = [google_cloudbuildv2_repository.repo]
}

resource "google_cloudbuild_trigger" "autogluon" {
  project         = var.project_id
  location        = var.region
  name            = "trigger-autogluon"
  description     = "Redeploy AutoGluon when AutoGluon code changes"
  filename        = "ci/cloudbuild.autogluon.yaml"
  service_account = "projects/${var.project_id}/serviceAccounts/${var.cicd_service_account_email}"

  included_files = [
    "src/autogluon_chronos_ii/**",
    "src/common/ml_gcp_utils.py",
    "Dockerfile",
    "requirements.txt"
  ]

  substitutions = {
    _REGION           = var.region
    _AR_REPO          = var.artifact_repo
    _RUNTIME_SA_EMAIL = var.runtime_service_account_email
    _BUCKET_RAW       = var.bucket_raw
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.repo.id

    push {
      branch = var.branch_regex
    }
  }

  depends_on = [google_cloudbuildv2_repository.repo]
}

resource "google_cloudbuild_trigger" "features" {
  project         = var.project_id
  location        = var.region
  name            = "trigger-features-sync"
  description     = "Sync features CSV to GCS when model features file changes"
  filename        = "ci/cloudbuild.features.yaml"
  service_account = "projects/${var.project_id}/serviceAccounts/${var.cicd_service_account_email}"

  included_files = [
    "config/model_features/**"
  ]

  substitutions = {
    _BUCKET_RAW = var.bucket_raw
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.repo.id

    push {
      branch = var.branch_regex
    }
  }

  depends_on = [google_cloudbuildv2_repository.repo]
}
