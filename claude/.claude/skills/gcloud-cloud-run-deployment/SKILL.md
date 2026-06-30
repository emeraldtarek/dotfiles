---
name: gcloud-cloud-run-deployment
description: End-to-end scaffolding to deploy a container-buildable app (Next.js or generic Node/Bun) to Google Cloud Run with GitHub Actions CI/CD authenticated via Workload Identity Federation, including push-to-main prod deploy, per-PR preview revisions with sticky URL comments, and a one-shot idempotent GCP bootstrap script. Use when the user has (a) a git repo they want to deploy and (b) a gcloud account, and they want first-class Cloud Run + GitHub Actions CI/CD. Triggers on phrases like "deploy to Cloud Run", "set up GCP CI/CD", "host this on GCP", "Cloud Run deploy with GitHub Actions", "GCP Workload Identity Federation", "deploy this repo to gcloud". Do NOT use for App Engine, GKE, Compute Engine, non-GCP deploys, or existing Cloud Run services that only need a config tweak (edit those directly).
---

# GCP Cloud Run Deployment with GitHub Actions CI/CD

Drops a Dockerfile, `cloudbuild.yaml`, `deploy.sh`, and two GitHub workflows into the target repo; one-shot script bootstraps the GCP side (project → APIs → AR repo → SAs → WIF). Produces a working push-to-main prod deploy + PR preview revisions with sticky comment URLs.

## When to use
- User wants Cloud Run + GitHub Actions CI/CD for a containerizable app
- Fresh deploy (no existing Cloud Run service to preserve)
- User has gcloud authenticated locally and `gh` CLI authenticated

## When NOT to use
- Non-Cloud-Run targets: App Engine, GKE, Compute Engine, Cloud Functions
- Non-GCP deploys (AWS, Azure, Fly, Vercel, etc.)
- Existing Cloud Run service that just needs a config tweak — patch directly
- Monorepo with multiple services — this scaffold is single-service (see "Adapting" below)

## Workflow (5 stages)

### 1. Detect / prep the repo
- Confirm git repo at the target path.
- Detect framework. Default templates are Next.js; use `dockerfile-generic.template` for non-Next Node/Bun apps and adjust the `CMD`.
- For Next.js: confirm `next.config.{ts,js,mjs}` sets `output: 'standalone'` — add it if missing.
- For Bun-based repos: commit `bun.lock` (CI uses `--frozen-lockfile`). See [gotchas.md](references/gotchas.md) #7.

### 2. Scaffold deploy files into the repo
Copy the templates from `references/` into the repo root, substituting `{{SERVICE_NAME}}`, `{{REGION}}`, `{{GITHUB_REPO}}` placeholders:

- `Dockerfile` ← `references/dockerfile-nextjs.template` (or `dockerfile-generic.template`)
- `cloudbuild.yaml` ← `references/cloudbuild.yaml.template`
- `deploy.sh` ← `references/deploy.sh.template` (run `chmod +x deploy.sh`)
- `DEPLOY.md` ← `references/DEPLOY.md.template`
- `.github/workflows/deploy.yml` ← `references/workflows/deploy.yml.template`
- `.github/workflows/pr.yml` ← `references/workflows/pr.yml.template`

### 3. Bootstrap GCP (one-time per project)
```bash
PROJECT_ID=elevationlabs-landing \
ORG_ID=123456789012 \
BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX \
GITHUB_REPO=OWNER/REPO \
SERVICE_NAME=my-service \
REGION=northamerica-northeast1 \
  bash ~/Documents/dotfiles/claude/.claude/skills/gcloud-cloud-run-deployment/scripts/bootstrap-gcp.sh
```
Idempotent — safe to re-run. Prints the three GitHub Variables at the end.

### 4. Set GitHub Variables
```bash
PROJECT_ID=elevationlabs-landing GITHUB_REPO=OWNER/REPO \
  bash ~/Documents/dotfiles/claude/.claude/skills/gcloud-cloud-run-deployment/scripts/set-github-vars.sh
```
Or set manually at Settings → Secrets and variables → Actions → **Variables** tab. (Variables, not Secrets — none of these are sensitive.)

### 5. Push + watch
```bash
git add -A && git commit -m "scaffold cloud run deploy" && git push
gh run watch --repo OWNER/REPO
```
First deploy: 5–7 min. Subsequent: 1–2 min thanks to layer caching.

## Defaults

- **Region:** `northamerica-northeast1` (Montréal). Override via `REGION=…` env var or by editing the templates.
- **Cloud Run service:** 512Mi, 1 vCPU, min=0, max=10, gen2 execution env, port 8080, `--allow-unauthenticated`.
- **Image registry:** per-project Artifact Registry repo named after the service.
- **Auth model:** Workload Identity Federation, OIDC binding pinned to a single GitHub repo.

## Recommended: one GCP project per deployed repo

The deployer SA gets `roles/run.admin` plus 5 others — broad enough that a compromised repo in a shared project can wipe other Cloud Run services. A fresh project per app gives clean blast-radius / IAM separation. Per-project setup adds ~10 min via the bootstrap script.

If you must share a project across repos, see [gotchas.md](references/gotchas.md) #6 for how to extend the WIF provider's attribute condition.

## When a deploy breaks

**Always read [references/gotchas.md](references/gotchas.md) before debugging.** Seven recurring failure modes are catalogued there with exact symptom→fix pairs:

1. Next.js `public/` returning 404 after deploy
2. Cloud Build ignoring `--region` (data residency drift)
3. Prod deploys silently landing on revisions that never receive traffic
4. `--allow-unauthenticated` silently failing in Workspace orgs (DSS)
5. Public IAM binding never applied when service deployed before DSS override
6. WIF auth rejected when reusing setup across repos
7. `bun install --frozen-lockfile` failing because `bun.lock` was gitignored

## File map

```
gcloud-cloud-run-deployment/
├── SKILL.md
├── scripts/
│   ├── bootstrap-gcp.sh           # idempotent GCP one-time setup
│   └── set-github-vars.sh         # populate 3 repo Variables via gh
└── references/
    ├── dockerfile-nextjs.template
    ├── dockerfile-generic.template
    ├── cloudbuild.yaml.template
    ├── deploy.sh.template
    ├── DEPLOY.md.template
    ├── gotchas.md                 # READ THIS FIRST when debugging
    └── workflows/
        ├── deploy.yml.template
        └── pr.yml.template
```

## Adapting

- **Different region:** edit `deploy.sh`, `cloudbuild.yaml`, and both workflows in one pass.
- **Need runtime env vars:** add `--set-env-vars=KEY=VAL` to the `gcloud run deploy` block in `deploy.sh`.
- **Need runtime secrets:** create with `gcloud secrets create`, grant the deployer SA `roles/secretmanager.secretAccessor` on the secret, then mount via `--update-secrets=ENVVAR=secret-name:latest` in `deploy.sh`.
- **Build-time env (`NEXT_PUBLIC_*`):** add `--build-arg` to `cloudbuild.yaml`, declare `ARG` in the builder stage of the Dockerfile, pass via `--substitutions` from `deploy.sh`.
- **Multi-service monorepo:** this scaffold is single-service by design. For multi-app, see the joud reference setup (matrix workflow + per-app Dockerfile).
