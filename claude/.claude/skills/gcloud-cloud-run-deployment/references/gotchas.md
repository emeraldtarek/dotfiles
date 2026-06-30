# Cloud Run Deployment Gotchas

Seven recurring failure modes captured from real deploys. **Read this
file before debugging any deploy issue** — most production-on-Cloud-Run
mysteries land somewhere in this list.

---

## 1. Next.js `public/` files 404 after deploy

**Symptom**
App deploys cleanly. Pages render. Anything under `public/` (images,
favicons, fonts, robots.txt) returns 404. Browser network tab shows
`/hm.jpg → 404`, even though the file is committed and visible locally.

**Cause**
`output: 'standalone'` in `next.config.{js,ts,mjs}` produces
`.next/standalone` + `.next/static`, but does **not** include `public/`.
[The Next docs](https://nextjs.org/docs/app/api-reference/config/next-config-js/output#automatically-copying-traced-files)
explicitly require you to copy `public/` yourself in the Dockerfile.

**Fix**
Add this line to the runner stage of the Dockerfile:
```dockerfile
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
```
Rebuild + redeploy. The `dockerfile-nextjs.template` in this skill
already includes it.

---

## 2. `gcloud builds submit` ignores the build region

**Symptom**
Cloud Build run shows up in a different region from your Cloud Run
service. Possibly violates compliance constraints (data residency).
Cloud Build console shows the build executing in `global` or another
region.

**Cause**
Without `--region`, `gcloud builds submit` defaults to the "global"
Cloud Build worker pool, which can execute in any region. The image is
still pushed to the AR repo in the region you specified, but the build
itself isn't pinned.

**Fix**
Always pass `--region "${REGION}"` to `gcloud builds submit`. The
bundled `deploy.sh.template` already does this.

---

## 3. Prod deploys silently land on revisions that never receive traffic

**Symptom**
`gcloud run deploy` succeeds. New revision appears in the console with
your new image. Service URL still serves the old code. `gcloud run
services describe` shows traffic pinned to an older revision name.

**Cause**
A previous preview deploy used `--tag <name> --no-traffic`, which froze
the traffic config to a specific named revision (e.g. `myservice-00042-xyz`).
Subsequent `gcloud run deploy` calls create new revisions but never
redirect traffic to them. There is no `--traffic` flag on `run deploy`,
so the deploy command alone can't fix this.

**Fix**
After every prod deploy (i.e. whenever `PREVIEW_TAG` is unset), follow
up with:
```bash
gcloud run services update-traffic "${SERVICE}" \
  --region "${REGION}" --to-latest --quiet
```
The bundled `deploy.sh.template` already does this when `PREVIEW_TAG` is
empty.

---

## 4. `--allow-unauthenticated` silently fails inside Workspace orgs

**Symptom**
Service deploys with `--allow-unauthenticated`. Visiting the Cloud Run
URL returns `Error: Forbidden` (a Google-branded page, not your app).
`gcloud run services get-iam-policy` shows no `allUsers` binding even
though deploy logs said the flag was set.

**Cause**
Google Workspace orgs ship with `constraints/iam.allowedPolicyMemberDomains`
(Domain Restricted Sharing, DSS) on by default, which blocks IAM bindings
to `allUsers` outside the org. The deploy command silently strips the
binding when the policy rejects it.

**Fix**
Override the policy at the project level (requires **Organization Policy
Administrator** at the org — granted via the IAM console with the org
selector active):
```bash
PROJECT_ID=$(gcloud config get-value project)

cat > /tmp/dss-override.yaml <<EOF
constraint: constraints/iam.allowedPolicyMemberDomains
listPolicy:
  allValues: ALLOW
EOF

gcloud resource-manager org-policies set-policy /tmp/dss-override.yaml \
  --project="$PROJECT_ID"
```
The `bootstrap-gcp.sh` script attempts this and warns if it fails.

---

## 5. Public IAM binding never applied (service deployed before DSS override)

**Symptom**
You applied the DSS override (gotcha #4), but the previously-deployed
service is still returning `Error: Forbidden`. Re-running `./deploy.sh`
doesn't help.

**Cause**
`--allow-unauthenticated` only tries to apply the `allUsers` binding
**during** a deploy. If the binding failed at deploy time (because DSS
was still enforcing), the next `deploy.sh` run doesn't retry it — Cloud
Run thinks "public access" is already at its desired state for this
revision.

**Fix**
Apply the binding explicitly:
```bash
gcloud run services add-iam-policy-binding "${SERVICE}" \
  --region="${REGION}" \
  --member="allUsers" \
  --role="roles/run.invoker"
```
This is one-time per service. Future deploys behave correctly once the
binding exists.

---

## 6. WIF auth rejected after extending CI/CD to a second repo

**Symptom**
`google-github-actions/auth@v2` step fails with:
```
unauthorized_client: The given credential is rejected by the attribute condition.
```
First repo's CI works fine; second repo gets this error.

**Cause**
The WIF provider's `--attribute-condition` is pinned to one repo (e.g.
`assertion.repository == 'org/repo-a'`). Tokens from any other repo are
rejected at the OIDC exchange. Also, the deployer SA's principalSet
binding only allows the original repo's principal.

**Fix — preferred (new project per repo)**
Create a fresh GCP project and re-run `bootstrap-gcp.sh` against it.
Gives clean blast-radius / IAM separation — a compromised second repo
can't touch the first project's resources.

**Fix — if you must share one project**
Two updates needed:
```bash
# 1. Allow both repos through the OIDC attribute condition
gcloud iam workload-identity-pools providers update-oidc github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --attribute-condition="assertion.repository == 'org/repo-a' || assertion.repository == 'org/repo-b'"

# 2. Bind the second repo's principalSet to the existing deployer SA
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
gcloud iam service-accounts add-iam-policy-binding \
  gh-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/org/repo-b"
```

---

## 7. `bun install --frozen-lockfile` fails in CI

**Symptom**
GitHub Actions step `bun install --frozen-lockfile` fails immediately
with one of:
- `error: lockfile is empty`
- `error: lockfile is not up to date with package.json`
- `bun.lock not found`

**Cause**
`bun.lock` was either never committed, listed in `.gitignore`, or is out
of sync with `package.json`. CI has no lockfile to be frozen against, or
the one it has doesn't match the manifest.

**Fix**
Locally:
```bash
bun install                       # regenerate bun.lock if needed
git add bun.lock package.json
git commit -m "sync bun.lock"
```
Also remove `bun.lock` from `.gitignore` if it's listed there. The first
deploy that exercises the lockfile will catch any future drift.

---

## Misc gotchas worth knowing (not numbered)

- **`gcloud config set project` is per-shell-session-ish** — but it's actually persistent for your gcloud CLI install. Be careful when bouncing between projects manually; commands run in the wrong project can be hard to undo. Prefer explicit `--project=` flags in scripts.
- **Cloud Run cold starts at min-instances=0** typically run 1–3s for a Next standalone server. If that's not acceptable, bump min-instances to 1 in `deploy.sh` (note: you'll be billed even when idle).
- **`gcloud run deploy` is not transactional** — if it fails halfway, you can end up with a half-rolled-out new revision plus the IAM bindings still attempting to update. Re-running usually converges, but check `gcloud run services describe` if behavior is weird.
- **Cloud Build logs default to the `_default_` GCS bucket** — if `gcloud logging write` permissions are missing on the build SA, builds silently lose logs. The bootstrap script adds `roles/cloudbuild.builds.builder` which covers this.
