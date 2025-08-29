terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.51.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.1"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Enable all necessary APIs for the lab ---
resource "google_project_service" "apis" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "vpcaccess.googleapis.com",
    "dns.googleapis.com",
    "sourcerepo.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com"
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# --- Service Account for the Agent ---
resource "google_service_account" "leaky_agent_sa" {
  project      = var.project_id
  account_id   = "leaky-agent-sa"
  display_name = "Leaky Summarizer Agent Service Account"
  depends_on   = [google_project_service.apis["iam.googleapis.com"]]
}

# --- *** NEW RESOURCE: Introduce a delay to allow SA to propagate *** ---
# This resource waits for 30 seconds after the service account is created.
resource "time_sleep" "wait_for_sa_propagation" {
  create_duration = "30s"

  # This sleep timer depends on the service account, so it only starts
  # after the SA has been successfully created.
  depends_on = [google_service_account.leaky_agent_sa]
}


# --- Cloud Storage Buckets and Lab Data ---
resource "google_storage_bucket" "staging_bucket" {
  project                     = var.project_id
  name                        = "corp-staging-bucket-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
  depends_on                  = [google_project_service.apis["storage.googleapis.com"]]
}

resource "google_storage_bucket" "summaries_bucket" {
  project                     = var.project_id
  name                        = "approved-summaries-bucket-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
  depends_on                  = [google_project_service.apis["storage.googleapis.com"]]
}

resource "google_storage_bucket_object" "secret_file" {
  name   = "project_alpha_plan.txt"
  bucket = google_storage_bucket.staging_bucket.name
  source = "../data/project_alpha_plan.txt"
}

resource "google_storage_bucket_object" "vulnerable_file" {
  name   = "pr_boilerplate.txt"
  bucket = google_storage_bucket.staging_bucket.name
  source = "../data/pr_boilerplate.txt"
}

# --- Networking Resources for the Remediation Step ---
resource "google_compute_network" "vpc_network" {
  project                 = var.project_id
  name                    = "leaky-agent-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis["compute.googleapis.com"]]
}

resource "google_compute_subnetwork" "vpc_subnetwork" {
  project       = var.project_id
  name          = "leaky-agent-subnetwork"
  ip_cidr_range = "10.10.10.0/28"
  network       = google_compute_network.vpc_network.id
  region        = var.region
}

resource "google_vpc_access_connector" "connector" {
  project        = var.project_id
  name           = "ls-vpc-connector"
  subnet {
    name = google_compute_subnetwork.vpc_subnetwork.name
  }
  region         = var.region
  min_throughput = 200
  max_throughput = 300
  depends_on     = [google_project_service.apis["vpcaccess.googleapis.com"]]
}

# --- Cloud Run Service Definition ---
resource "google_cloud_run_v2_service" "leaky_summarizer" {
  project    = var.project_id
  name       = "leaky-summarizer"
  location   = var.region
  depends_on = [google_project_service.apis["run.googleapis.com"]]
  
  deletion_protection = false

  template {
    service_account = google_service_account.leaky_agent_sa.email
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }
}

# --- IAM Permissions ---
resource "google_cloud_run_v2_service_iam_member" "noauth" {
  project  = google_cloud_run_v2_service.leaky_summarizer.project
  location = google_cloud_run_v2_service.leaky_summarizer.location
  name     = google_cloud_run_v2_service.leaky_summarizer.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_storage_bucket_iam_member" "agent_read_staging" {
  bucket     = google_storage_bucket.staging_bucket.name
  role       = "roles/storage.objectViewer"
  member     = "serviceAccount:${google_service_account.leaky_agent_sa.email}"
  # *** UPDATED DEPENDENCY ***
  # Now, this resource waits for the sleep timer to finish.
  depends_on = [time_sleep.wait_for_sa_propagation]
}

resource "google_storage_bucket_iam_member" "agent_write_summaries" {
  bucket     = google_storage_bucket.summaries_bucket.name
  role       = "roles/storage.objectCreator"
  member     = "serviceAccount:${google_service_account.leaky_agent_sa.email}"
  # *** UPDATED DEPENDENCY ***
  # This resource also waits for the sleep timer to finish.
  depends_on = [time_sleep.wait_for_sa_propagation]
}
