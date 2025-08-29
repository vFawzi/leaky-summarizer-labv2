#!/bin/bash

# A script to verify the GCP environment setup for the Leaky Summarizer lab.
# VERSION 2.0 - With robust gcloud-based IAM checks.
# Usage: ./verify_setup.sh <PROJECT_ID>
# -----------------------------------------------------------------------------

# --- Colors for Output ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Check for Project ID ---
if [ -z "$1" ]; then
    echo -e "${RED}ERROR: Project ID is required.${NC}"
    echo "Usage: ./verify_setup.sh <PROJECT_ID>"
    exit 1
fi

PROJECT_ID=$1
REGION="us-central1"
SA_EMAIL="leaky-agent-sa@${PROJECT_ID}.iam.gserviceaccount.com"
SA_MEMBER="serviceAccount:${SA_EMAIL}"

# --- Helper Function ---
print_check() {
    # $1: Message
    # $2: Status (0 for success, 1 for failure)
    if [ "$2" -eq 0 ]; then
        echo -e "[ ${GREEN}PASS${NC} ] $1"
    else
        echo -e "[ ${RED}FAIL${NC} ] $1"
        exit 1 # Exit on first failure
    fi
}

echo -e "${YELLOW}=====================================================${NC}"
echo -e "${YELLOW}  Verifying Lab Setup for Project: ${PROJECT_ID}${NC}"
echo -e "${YELLOW}=====================================================${NC}"

# --- 1. Verify APIs ---
echo -e "\n${YELLOW}--- Verifying Enabled APIs... ---${NC}"
ENABLED_APIS=$(gcloud services list --enabled --project=${PROJECT_ID} --format="value(config.name)")
APIS_TO_CHECK=(
    "run.googleapis.com"
    "storage.googleapis.com"
    "aiplatform.googleapis.com"
    "compute.googleapis.com"
    "vpcaccess.googleapis.com"
)
for api in "${APIS_TO_CHECK[@]}"; do
    echo "$ENABLED_APIS" | grep -q "$api"
    print_check "API '${api}' is enabled." $?
done

# --- 2. Verify GCS Buckets and Objects ---
echo -e "\n${YELLOW}--- Verifying Cloud Storage... ---${NC}"
STAGING_BUCKET="gs://corp-staging-bucket-${PROJECT_ID}"
gsutil ls "${STAGING_BUCKET}" > /dev/null 2>&1
print_check "Staging bucket '${STAGING_BUCKET}' exists." $?

SUMMARIES_BUCKET="gs://approved-summaries-bucket-${PROJECT_ID}"
gsutil ls "${SUMMARIES_BUCKET}" > /dev/null 2>&1
print_check "Summaries bucket '${SUMMARIES_BUCKET}' exists." $?

gsutil ls "${STAGING_BUCKET}/project_alpha_plan.txt" > /dev/null 2>&1
print_check "File 'project_alpha_plan.txt' exists in staging bucket." $?

gsutil ls "${STAGING_BUCKET}/pr_boilerplate.txt" > /dev/null 2>&1
print_check "File 'pr_boilerplate.txt' exists in staging bucket." $?

# --- 3. Verify IAM Permissions (NEW ROBUST METHOD) ---
echo -e "\n${YELLOW}--- Verifying IAM Permissions... ---${NC}"

# Check Reader role on staging bucket
IAM_CHECK_STAGING=$(gcloud storage buckets get-iam-policy "${STAGING_BUCKET}" --format="json" | \
    jq -r --arg MEMBER "$SA_MEMBER" '.bindings[] | select(.role == "roles/storage.objectViewer" and (.members[] | contains($MEMBER))) | .role')
[ "$IAM_CHECK_STAGING" == "roles/storage.objectViewer" ]
print_check "Service Account has ObjectViewer role on staging bucket." $?

# Check Creator role on summaries bucket
IAM_CHECK_SUMMARIES=$(gcloud storage buckets get-iam-policy "${SUMMARIES_BUCKET}" --format="json" | \
    jq -r --arg MEMBER "$SA_MEMBER" '.bindings[] | select(.role == "roles/storage.objectCreator" and (.members[] | contains($MEMBER))) | .role')
[ "$IAM_CHECK_SUMMARIES" == "roles/storage.objectCreator" ]
print_check "Service Account has ObjectCreator role on summaries bucket." $?

# --- 4. Verify Networking ---
echo -e "\n${YELLOW}--- Verifying Networking... ---${NC}"
gcloud compute networks describe leaky-agent-vpc --project=${PROJECT_ID} > /dev/null 2>&1
print_check "VPC 'leaky-agent-vpc' exists." $?

gcloud compute networks vpc-access connectors describe ls-vpc-connector --region=${REGION} --project=${PROJECT_ID} --format="value(state)" | grep -q "READY"
print_check "VPC Connector 'ls-vpc-connector' is READY." $?

# --- 5. Verify Cloud Run Service ---
echo -e "\n${YELLOW}--- Verifying Cloud Run Service... ---${NC}"
SERVICE_SA_CHECK=$(gcloud run services describe leaky-summarizer --region=${REGION} --project=${PROJECT_ID} --format="value(template.serviceAccount)")
[ "$SERVICE_SA_CHECK" == "$SA_EMAIL" ]
print_check "Cloud Run service is configured with the correct Service Account." $?

gcloud run services get-iam-policy leaky-summarizer --region=${REGION} --project=${PROJECT_ID} --format="json" | \
    jq -r '.bindings[] | select(.role == "roles/run.invoker" and (.members[] | contains("allUsers"))) | .role' | grep -q "roles/run.invoker"
print_check "Cloud Run service is publicly accessible (allUsers can invoke)." $?


echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}  ✅ All checks passed. Lab environment is ready!${NC}"
echo -e "${GREEN}=====================================================${NC}"

# Print the agent URL for the trainer to copy
AGENT_URL=$(gcloud run services describe leaky-summarizer --region=${REGION} --project=${PROJECT_ID} --format='value(status.url)')
echo -e "\n${YELLOW}Student Agent URL:${NC} ${AGENT_URL}"

