#!/usr/bin/env bash
# Idempotent one-shot setup for a GCP project to host a single Cloud Run
# service deployed via GitHub Actions + Workload Identity Federation.
#
# Required env vars:
#   PROJECT_ID       — globally unique GCP project ID to create/use
#   ORG_ID           — numeric GCP organization ID (gcloud organizations list)
#   BILLING_ACCOUNT  — billing account ID (gcloud billing accounts list)
#   GITHUB_REPO      — OWNER/REPO this WIF binding will be scoped to
#
# Optional env vars:
#   SERVICE_NAME     — Cloud Run service + Artifact Registry repo name.
#                      Defaults to PROJECT_ID.
#   REGION           — Cloud Run + Artifact Registry region.
#                      Defaults to northamerica-northeast1 (Montréal).
#
# Re-running is safe — every step is gated by an existence check.
#
# Required local CLIs:
#   gcloud (authenticated with org-level "Project Creator" and
#           "Organization Policy Administrator" roles)

set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID required (globally unique GCP project ID)}"
: "${ORG_ID:?ORG_ID required (numeric — see 'gcloud organizations list')}"
: "${BILLING_ACCOUNT:?BILLING_ACCOUNT required (XXXXXX-XXXXXX-XXXXXX)}"
: "${GITHUB_REPO:?GITHUB_REPO required (OWNER/REPO)}"

REGION="${REGION:-northamerica-northeast1}"
SERVICE_NAME="${SERVICE_NAME:-${PROJECT_ID}}"

echo "=================================================================="
echo "Bootstrapping GCP project for Cloud Run deploy"
echo "  PROJECT_ID    = ${PROJECT_ID}"
echo "  REGION        = ${REGION}"
echo "  SERVICE_NAME  = ${SERVICE_NAME}"
echo "  GITHUB_REPO   = ${GITHUB_REPO}"
echo "=================================================================="

# ─── 1. Project ────────────────────────────────────────────────────────
if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  echo "[1/12] Project ${PROJECT_ID} already exists, skipping create."
else
  echo "[1/12] Creating project ${PROJECT_ID}…"
  gcloud projects create "$PROJECT_ID" \
    --name="${PROJECT_ID}" \
    --organization="$ORG_ID"
fi

# ─── 2. Link billing ───────────────────────────────────────────────────
echo "[2/12] Linking billing account…"
gcloud billing projects link "$PROJECT_ID" \
  --billing-account="$BILLING_ACCOUNT" >/dev/null

# ─── 3. Set as active project ──────────────────────────────────────────
gcloud config set project "$PROJECT_ID" >/dev/null
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
echo "[3/12] Active project set. PROJECT_NUMBER=${PROJECT_NUMBER}"

# ─── 4. Enable APIs ────────────────────────────────────────────────────
echo "[4/12] Enabling required APIs (this can take ~30s)…"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  --project="$PROJECT_ID"

# ─── 5. Artifact Registry repo ─────────────────────────────────────────
if gcloud artifacts repositories describe "$SERVICE_NAME" \
     --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "[5/12] Artifact Registry repo ${SERVICE_NAME} already exists, skipping."
else
  echo "[5/12] Creating Artifact Registry repo ${SERVICE_NAME}…"
  gcloud artifacts repositories create "$SERVICE_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="${SERVICE_NAME} images" \
    --project="$PROJECT_ID"
fi

# ─── 6. Cloud Build SA bundle role ─────────────────────────────────────
echo "[6/12] Granting Cloud Build SA the builds.builder role…"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.builder" \
  --condition=None --quiet >/dev/null

# ─── 7. DSS org-policy override ────────────────────────────────────────
# Needed so --allow-unauthenticated actually attaches an allUsers binding
# in Workspace orgs that ship with Domain Restricted Sharing enforced.
echo "[7/12] Overriding DSS org policy at the project level…"
cat > /tmp/dss-override.yaml <<EOF
constraint: constraints/iam.allowedPolicyMemberDomains
listPolicy:
  allValues: ALLOW
EOF
if gcloud resource-manager org-policies set-policy /tmp/dss-override.yaml \
     --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "        DSS override applied."
else
  echo "        WARN: DSS override failed. Need 'roles/orgpolicy.policyAdmin'"
  echo "              at the org level. Without this, --allow-unauthenticated"
  echo "              will silently fail. Re-run after the role is granted,"
  echo "              or apply the binding manually (see gotchas.md #5)."
fi
rm -f /tmp/dss-override.yaml

# ─── 8. Deployer SA ────────────────────────────────────────────────────
SA_EMAIL="gh-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA_EMAIL" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "[8/12] Deployer SA ${SA_EMAIL} already exists, skipping create."
else
  echo "[8/12] Creating deployer SA…"
  gcloud iam service-accounts create gh-actions-deployer \
    --display-name="GitHub Actions deploy SA" \
    --project="$PROJECT_ID"
fi

# ─── 9. Deployer SA roles ──────────────────────────────────────────────
echo "[9/12] Granting deployer SA the deploy bundle…"
for role in roles/run.admin roles/cloudbuild.builds.editor \
            roles/artifactregistry.writer roles/iam.serviceAccountUser \
            roles/storage.admin roles/logging.viewer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$role" \
    --condition=None --quiet >/dev/null
done

# ─── 10. WIF pool ──────────────────────────────────────────────────────
if gcloud iam workload-identity-pools describe github-pool \
     --location=global --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "[10/12] WIF pool 'github-pool' already exists, skipping."
else
  echo "[10/12] Creating WIF pool 'github-pool'…"
  gcloud iam workload-identity-pools create github-pool \
    --location=global \
    --display-name="GitHub Actions Pool" \
    --project="$PROJECT_ID"
fi

# ─── 11. WIF provider ──────────────────────────────────────────────────
if gcloud iam workload-identity-pools providers describe github-provider \
     --location=global --workload-identity-pool=github-pool \
     --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "[11/12] WIF provider 'github-provider' already exists."
  echo "        If you're adding a second repo, update the attribute"
  echo "        condition manually — see gotchas.md #6."
else
  echo "[11/12] Creating WIF provider 'github-provider' pinned to ${GITHUB_REPO}…"
  gcloud iam workload-identity-pools providers create-oidc github-provider \
    --location=global \
    --workload-identity-pool=github-pool \
    --display-name="GitHub OIDC" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository == '${GITHUB_REPO}'" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --project="$PROJECT_ID"
fi

# ─── 12. PrincipalSet binding ──────────────────────────────────────────
echo "[12/12] Binding WIF principalSet for ${GITHUB_REPO} to deployer SA…"
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${GITHUB_REPO}" \
  --project="$PROJECT_ID" >/dev/null

# ─── Output ────────────────────────────────────────────────────────────
cat <<EOF

==================================================================
✓ GCP bootstrap complete.

Set these in the GitHub repo Variables tab
(Settings → Secrets and variables → Actions → Variables):

  GCP_PROJECT_ID                 = ${PROJECT_ID}
  GCP_DEPLOYER_SA                = ${SA_EMAIL}
  GCP_WORKLOAD_IDENTITY_PROVIDER = projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/providers/github-provider

Or run set-github-vars.sh to set them automatically via gh:

  PROJECT_ID=${PROJECT_ID} GITHUB_REPO=${GITHUB_REPO} \\
    bash \$(dirname "\$0")/set-github-vars.sh

Next: scaffold the deploy files into your repo (Dockerfile,
cloudbuild.yaml, deploy.sh, .github/workflows/*) from the
references/ folder of this skill, then push to trigger the first
deploy.
==================================================================
EOF
