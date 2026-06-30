#!/usr/bin/env bash
# Populate the three GitHub Actions Variables this skill's workflows need.
#
# Required env vars:
#   PROJECT_ID   — same value used during bootstrap-gcp.sh
#   GITHUB_REPO  — OWNER/REPO to set the variables on
#
# Requires gh CLI authenticated against the org (`gh auth status`).

set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID required}"
: "${GITHUB_REPO:?GITHUB_REPO required (OWNER/REPO)}"

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
SA_EMAIL="gh-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
WIF="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"

echo "Setting Variables on ${GITHUB_REPO}…"

gh variable set GCP_PROJECT_ID                 --repo "$GITHUB_REPO" --body "$PROJECT_ID"
gh variable set GCP_DEPLOYER_SA                --repo "$GITHUB_REPO" --body "$SA_EMAIL"
gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --repo "$GITHUB_REPO" --body "$WIF"

echo "✓ Set 3 Variables on ${GITHUB_REPO}:"
echo "    GCP_PROJECT_ID                 = ${PROJECT_ID}"
echo "    GCP_DEPLOYER_SA                = ${SA_EMAIL}"
echo "    GCP_WORKLOAD_IDENTITY_PROVIDER = ${WIF}"
