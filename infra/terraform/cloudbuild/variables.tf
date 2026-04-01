variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_app_installation_id" {
  type = number
}

variable "github_token_secret_id" {
  type = string
}

variable "github_token_secret_version" {
  type    = string
  default = "latest"
}

variable "connection_name" {
  type    = string
  default = "github-ml-project-cmoran"
}

variable "repository_resource_name" {
  type    = string
  default = "ml-project-cmoran"
}

variable "branch_regex" {
  type    = string
  default = "^main$"
}

variable "artifact_repo" {
  type = string
}

variable "bucket_raw" {
  type = string
}

variable "runtime_service_account_email" {
  type = string
}

variable "cicd_service_account_email" {
  type = string
}