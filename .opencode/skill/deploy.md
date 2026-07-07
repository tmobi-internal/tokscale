# /deploy

Deploy tokscale to production.

## Method 1: Jenkins (tmobi-internal, recommended for PRD)

### Configuration

- Jenkins URL: `https://jenkins.tmapadmin.com/job/pc.tokscale_prd/`
- Git remote: `tmobi` → `https://github.com/tmobi-internal/tokscale.git`
- Auth: Jenkins session cookies (JSESSIONID) from browser
- CSRF: Must fetch crumb before triggering builds

### Parameters

| Name | Default | Description |
|------|---------|-------------|
| BRANCH | main | Git branch to build |
| BUILD_VERSION | 0.0.0 | Docker image version tag (increment from last build!) |
| APP_NAME | tokscale | Application name |
| NAMESPACE | it | K8s namespace |
| GIT_NAME | tokscale | Repository name |
| DEPLOY_GIT | devops-deploy-it | Deploy manifest repo |
| ENV | prd | Environment |
| DOCKERFILE | self-host/Dockerfile | Dockerfile path |
| DEPLOY_PATH | it | Deploy path |

### Steps

1. **Check last build version** (ALWAYS do this first):

```bash
curl -s "https://jenkins.tmapadmin.com/job/pc.tokscale_prd/lastSuccessfulBuild/api/json" \
  -H "Cookie: $COOKIES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for action in data.get('actions', []):
    for p in action.get('parameters', []):
        print(f\"{p['name']} = {p['value']}\")
"
```

2. **Get CSRF crumb**:

```bash
CRUMB_RESPONSE=$(curl -s "https://jenkins.tmapadmin.com/crumbIssuer/api/json" -H "Cookie: $COOKIES")
CRUMB=$(echo "$CRUMB_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['crumb'])")
```

3. **Trigger build** (increment BUILD_VERSION from step 1):

```bash
curl -s -X POST "https://jenkins.tmapadmin.com/job/pc.tokscale_prd/buildWithParameters" \
  -H "Cookie: $COOKIES" \
  -H "Jenkins-Crumb: $CRUMB" \
  -d "BRANCH=deploy&BUILD_VERSION=<NEXT_VERSION>" \
  -w "\nHTTP_STATUS: %{http_code}"
```

HTTP 201 = success.

4. **Stop a running build** (if needed):

```bash
curl -s -X POST "https://jenkins.tmapadmin.com/job/pc.tokscale_prd/<BUILD_NUMBER>/stop" \
  -H "Cookie: $COOKIES" \
  -H "Jenkins-Crumb: $CRUMB"
```

### Important Notes

- **NEVER use BUILD_VERSION=0.0.0** — always check last build and increment.
- Push to `tmobi` remote before triggering (Jenkins pulls from tmobi-internal).
- gh auth must be `tmap-c` or `t1000040` to push to tmobi-internal.
- Cookies expire with browser session — get fresh ones if 401/403.

### Step 2: ArgoCD Sync (after Jenkins build completes)

- ArgoCD URL: `https://argocd.tmapadmin.com/applications/argocd/tokscale-prd`
- App Name: `tokscale-prd`
- Auth: Cookie `argocd.token=<JWT>` from browser (Cognito/AzureAD SSO, ~1h expiry)

**Sync via CLI (preferred):**

```bash
ARGOCD_AUTH_TOKEN="$ARGOCD_TOKEN" argocd app sync tokscale-prd \
  --server argocd.tmapadmin.com --grpc-web
```

**Check status via CLI:**

```bash
ARGOCD_AUTH_TOKEN="$ARGOCD_TOKEN" argocd app get tokscale-prd \
  --server argocd.tmapadmin.com --grpc-web
```

**Or via REST API:**

```bash
curl -s -X POST "https://argocd.tmapadmin.com/api/v1/applications/tokscale-prd/sync" \
  -H "Cookie: argocd.token=$ARGOCD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  -w "\nHTTP_STATUS: %{http_code}"
```

**Important:**
- ArgoCD token = browser cookie `argocd.token` (Cognito SSO, ~1h expiry).
- `argocd login --sso` does NOT work (invalid_client_secret — server-side OIDC issue).
- Use `ARGOCD_AUTH_TOKEN` env var for CLI, or `Cookie` header for REST API.
- Get fresh cookie from browser if 401.


