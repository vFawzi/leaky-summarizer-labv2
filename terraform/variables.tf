variable "project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
}

variable "region" {
  description = "The GCP region for deployment."
  type        = string
  default     = "us-central1"
}
