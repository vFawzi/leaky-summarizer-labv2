output "agent_url" {
  description = "The URL of the deployed Cloud Run agent service."
  value       = google_cloud_run_v2_service.leaky_summarizer.uri
}

output "project_id" {
  description = "The project ID used for deployment."
  value       = var.project_id
}
