#!/bin/bash
# Hugging Face Spaces deploy adapter -----------------------------------------
# League container naming: <owner>/<slug> served at
# https://<owner>-<slug>.hf.space (embed the .hf.space URL).
# Requires HUGGINGFACE_TOKEN unless DRY_RUN=1.

: "${HF_OWNER:=shaggycamel}"
: "${HF_IMAGE_BASENAME:=scs.nba.fty.league_dash}"
HF_DEPLOY_INI="${HF_DEPLOY_INI:-$HOME/.config/scs_hf_league_deploy.ini}"
HF_HANDOFF_KEY="${HF_HANDOFF_KEY:-NBA_HANDOFF_SECRET}"

hf_space_id() {
  echo "${HF_OWNER}/${1}"
}

adapter_url() {
  echo "https://${HF_OWNER}-${1}.hf.space"
}

hf_space_exists() {
  local repo="$1"
  local status
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
    "https://huggingface.co/api/spaces/${repo}")"
  [ "$status" = "200" ]
}

hf_space_keys() {
  local repo="$1" kind="$2"
  curl -s -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
    "https://huggingface.co/api/spaces/${repo}/${kind}" \
    | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    print("\n".join(sorted(data.keys())))'
}

hf_space_variable_value() {
  local repo="$1" key="$2"
  curl -s -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
    "https://huggingface.co/api/spaces/${repo}/variables" \
    | python3 -c 'import json,sys
key = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
value = data.get(key, {})
print(value.get("value", "") if isinstance(value, dict) else "")' "$key"
}

hf_space_secret_json() {
  python3 - "$HF_DEPLOY_INI" "$HF_HANDOFF_KEY" <<'PY'
import configparser
import json
import sys

ini, key = sys.argv[1], sys.argv[2]
parser = configparser.ConfigParser()
if not parser.read(ini):
    sys.exit(f"deploy INI not found: {ini}")
if not parser.has_section("handoff") or not parser.has_option("handoff", key):
    sys.exit(f"[handoff] {key} missing from {ini}")
value = parser.get("handoff", key).strip()
if not value:
    sys.exit(f"[handoff] {key} is empty in {ini}")
print(json.dumps({"key": key, "value": value, "description": "handoff HMAC key"}))
PY
}

hf_space_set_secret() {
  local repo="$1"
  local json
  json="$(hf_space_secret_json)" || return 1
  printf '%s' "$json" | curl -sf -X POST "https://huggingface.co/api/spaces/${repo}/secrets" \
    -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @- >/dev/null || return 1
  unset json
}

hf_space_set_variable() {
  local repo="$1" key="$2" value="$3"
  local json
  json="$(python3 -c 'import json,sys; print(json.dumps({"key": sys.argv[1], "value": sys.argv[2]}))' "$key" "$value")" || return 1
  printf '%s' "$json" | curl -sf -X POST "https://huggingface.co/api/spaces/${repo}/variables" \
    -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @- >/dev/null || return 1
  unset json
}

hf_space_delete_variable() {
  local repo="$1" key="$2"
  local json
  json="$(python3 -c 'import json,sys; print(json.dumps({"key": sys.argv[1]}))' "$key")" || return 1
  printf '%s' "$json" | curl -sf -X DELETE "https://huggingface.co/api/spaces/${repo}/variables" \
    -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @- >/dev/null || return 1
  unset json
}

hf_apply_space_config() {
  local repo="$1" role="$2"
  local keys
  keys="$(hf_space_keys "$repo" secrets)"
  if [ "${ROTATE_HANDOFF_SECRET:-0}" = "1" ] \
    || ! printf '%s\n' "$keys" | grep -qx "$HF_HANDOFF_KEY"; then
    echo "[hf] setting handoff secret on ${repo}"
    hf_space_set_secret "$repo" || return 1
  fi
  if [ "$role" = "league" ] && [ "$(hf_space_variable_value "$repo" NBA_REQUIRE_HANDOFF)" != "1" ]; then
    echo "[hf] setting NBA_REQUIRE_HANDOFF on ${repo}"
    hf_space_set_variable "$repo" NBA_REQUIRE_HANDOFF 1 || return 1
  fi
}

hf_cleanup_legacy_vars() {
  local repo="$1" role="$2"
  local keys key
  keys="$(hf_space_keys "$repo" variables)"
  for key in NBA_SEASON; do
    if printf '%s\n' "$keys" | grep -qx "$key"; then
      echo "[hf] removing ${key} from ${repo}"
      hf_space_delete_variable "$repo" "$key" || return 1
    fi
  done
  if [ "$role" = "entry" ]; then
    for key in NBA_DB_SSLMODE NBA_HF_SPACE_PREFIX; do
      if printf '%s\n' "$keys" | grep -qx "$key"; then
        echo "[hf] removing ${key} from ${repo}"
        hf_space_delete_variable "$repo" "$key" || return 1
      fi
    done
  fi
}

# Resolve an image tag to its immutable digest (repo@sha256:...) via the Docker
# Hub registry API. Pinning the digest is what guarantees the Space is never
# served a stale image: a `FROM image:latest` can hit a cached layer, but a
# digest is content-addressed, so a changed image (new data baked into every
# league build) forces a real pull. Retries the registry lookup; if it still
# cannot resolve a digest it FAILS the deploy rather than committing a
# tag-based `FROM` that Docker/HF can silently cache (the cause of stale Spaces
# serving an old app until a manual factory reboot).
hf_image_ref() {
  local image="$1"

  case "$image" in
    *@sha256:*) printf '%s' "$image"; return 0 ;;
  esac

  local repo tag
  repo="${image%:*}"
  tag="${image##*:}"
  if [ "$tag" = "$image" ]; then tag="latest"; fi

  # Docker Hub registry path (bare names live under library/).
  local path="$repo"
  case "$repo" in
    */*) ;;
    *) path="library/$repo" ;;
  esac

  local attempt token digest
  for attempt in 1 2 3; do
    token="$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${path}:pull" \
      | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
    if [ -n "$token" ]; then
      digest="$(curl -sI \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
        "https://registry-1.docker.io/v2/${path}/manifests/${tag}" \
        | tr -d '\r' \
        | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest:[[:space:]]*\(.*\)$/\1/p')"
      if [ -n "$digest" ]; then
        printf '%s@%s' "${repo}" "${digest}"
        return 0
      fi
    fi
    sleep $((attempt * 2))
  done

  echo "[hf] ERROR: could not resolve a digest for ${image} after 3 attempts" >&2
  return 1
}

# Print the commit the Space's main branch currently points at.
hf_space_head() {
  local repo="$1"
  curl -s -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
    "https://huggingface.co/api/spaces/${repo}/refs" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(next((b["targetCommit"] for b in d.get("branches",[]) if b["name"]=="main"), ""))'
}

# Print "<runtime_sha> <stage>" for the Space (the commit actually being served).
hf_runtime() {
  local repo="$1"
  curl -s -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
    "https://huggingface.co/api/spaces/${repo}" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d.get("runtime") or {}; print(r.get("sha",""), r.get("stage",""))'
}

# Wait until the Space is serving the expected commit and its HTTP endpoint
# responds. HF sometimes leaves a Space RUNNING on its previous build (it did
# not rebuild), which serves a stale image; this detects that and forces a
# factory reboot, then keeps waiting. Returns non-zero if it never converges.
hf_wait_healthy() {
  local repo="$1" expected="$2" timeout="${3:-900}" grace="${HF_HEAL_GRACE:-90}"
  local waited=0 healed=0 woke=0 runtime sha stage url last_sha="" last_stage="" http_timeout="${HF_HTTP_TIMEOUT:-10}"
  url="$(adapter_url "${repo##*/}")"

  while [ "$waited" -lt "$timeout" ]; do
    runtime="$(hf_runtime "$repo" 2>/dev/null || true)"
    sha="${runtime%% *}"
    stage="${runtime##* }"
    last_sha="$sha"
    last_stage="$stage"

    if [ -n "$expected" ] && [ "$sha" = "$expected" ] && [ "$stage" = "RUNNING" ]; then
      if curl -fsSL --max-time "$http_timeout" -o /dev/null "${url}/" 2>/dev/null; then
        return 0
      fi
    fi

    if { [ "$stage" = "PAUSED" ] || [ "$stage" = "STOPPED" ]; } && [ "$woke" = "0" ]; then
      echo "[hf] WARN: ${repo} is ${stage}; restarting" >&2
      curl -sf -X POST "https://huggingface.co/api/spaces/${repo}/restart" \
        -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" >/dev/null 2>&1 || true
      woke=1
    fi

    # Only heal a Space that is up but stuck on its previous commit. While it is
    # BUILDING, leave it alone so we do not interrupt an in-flight rebuild.
    if [ -n "$expected" ] && [ "$stage" = "RUNNING" ] && [ "$sha" != "$expected" ] \
      && [ "$waited" -ge "$grace" ] && [ "$healed" = "0" ]; then
      echo "[hf] WARN: ${repo} still on ${sha:-?} (${stage:-?}), expected ${expected:-?}; forcing factory reboot" >&2
      curl -sf -X POST "https://huggingface.co/api/spaces/${repo}/restart?factory=true" \
        -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" >/dev/null 2>&1 || true
      healed=1
    fi

    sleep 10
    waited=$((waited + 10))
  done

  if [ "$last_sha" = "$expected" ] && [ "$last_stage" = "RUNNING" ]; then
    echo "[hf] ERROR: ${repo} is running ${expected}, but ${url}/ did not respond within ${timeout}s" >&2
  else
    echo "[hf] ERROR: ${repo} did not converge to ${expected:-?} (last runtime ${last_sha:-?} ${last_stage:-?}) within ${timeout}s" >&2
  fi
  return 1
}

# Commit the Space's Dockerfile pinned to the pushed image's digest, with a
# fresh cache-busting build arg. HF only rebuilds a Docker Space when its
# repository changes, and a bare restart keeps serving the previously built
# image -- so a freshly pushed image is otherwise never picked up. The digest pin
# (never stale) plus the changing ARG/RUN (always a repo change) together force a
# clean rebuild. library() is required so LazyData objects are attached.
hf_configure_space() {
  local repo="$1"
  local image="$2"
  local app="$3"

  local image_ref
  image_ref="$(hf_image_ref "$image")" || return 1

  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}${RANDOM}"

  local df_json="FROM ${image_ref}\\nARG SPACE_REBUILD=${stamp}\\nRUN echo \\\"space rebuild ${stamp}\\\"\\nHEALTHCHECK --interval=30s --timeout=5s --start-period=60s CMD curl -fsS http://localhost:7860/ >/dev/null || exit 1\\nEXPOSE 7860\\nUSER rstudio\\nCMD [\\\"R\\\", \\\"-e\\\", \\\"options('shiny.port'=7860, 'shiny.host'='0.0.0.0'); library(${app}); ${app}::run_app()\\\"]"

  printf '%s\n' \
    '{"key":"header","value":{"summary":"provision space"}}' \
    "{\"key\":\"file\",\"value\":{\"path\":\"Dockerfile\",\"content\":\"${df_json}\",\"encoding\":\"utf-8\"}}" |
    curl -sf -X POST "https://huggingface.co/api/spaces/${repo}/commit/main" \
      -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
      -H "Content-Type: application/x-ndjson" \
      --data-binary @- >/dev/null || return 1

  echo "[hf] ${repo} -> ${image_ref}"
}

# Create the Space if missing, then configure its Dockerfile.
adapter_provision() {
  local slug="$1"
  local image="$2"
  local app="${3:-league}"
  local name="${slug}"
  local repo="${HF_OWNER}/${name}"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] provision HF space ${repo} (FROM ${image}, app ${app})"
    return 0
  fi

  : "${HUGGINGFACE_TOKEN:?HUGGINGFACE_TOKEN is required for HF provisioning}"

  local status
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
    "https://huggingface.co/api/spaces/${repo}")"

  if [ "$status" != "200" ]; then
    echo "[hf] creating ${repo}"
    curl -sf -X POST "https://huggingface.co/api/repos/create" \
      -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"type\":\"space\",\"name\":\"${name}\",\"private\":false,\"sdk\":\"docker\"}" >/dev/null || return 1
  fi

  hf_apply_space_config "$repo" "$app" || return 1
  hf_configure_space "$repo" "$image" "$app" || return 1
  echo "[hf] configured ${repo} (FROM ${image})"
  hf_wait_healthy "$repo" "$(hf_space_head "$repo")" "${HF_HEALTH_TIMEOUT:-900}" || return 1
}

# Deploy: commit a Dockerfile pinned to the just-pushed image digest (which makes
# HF rebuild and re-pull exactly what was pushed), then WAIT until the Space is
# actually serving that new commit. HF sometimes leaves a Space RUNNING on its
# previous build, which serves a stale image (e.g. an old entry that rejects a
# valid password); hf_wait_healthy detects that and forces a factory reboot, so
# a manual one is never needed.
adapter_deploy() {
  local slug="$1"
  local image="$2"
  local app="${3:-league}"
  local repo
  repo="$(hf_space_id "$slug")"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] rebuild + restart HF space ${repo} (image ${image:-<none>}, app ${app}) -> $(adapter_url "$slug")"
    return 0
  fi

  : "${HUGGINGFACE_TOKEN:?HUGGINGFACE_TOKEN is required for HF deploys}"

  hf_apply_space_config "$repo" "$app" || return 1

  # The commit is what guarantees a fresh image; it must succeed.
  hf_configure_space "$repo" "$image" "$app" || return 1

  # Verify the Space converges onto the commit we just pushed, healing a stale
  # (RUNNING-but-old) Space with a factory reboot if HF did not rebuild.
  local expected
  expected="$(hf_space_head "$repo")"
  hf_wait_healthy "$repo" "$expected" "${HF_HEALTH_TIMEOUT:-900}" || return 1
  echo "[hf] ${repo} serving ${expected:0:12}"
}

adapter_teardown() {
  local slug="$1"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] teardown HF space $(hf_space_id "$slug")"
    return 0
  fi
  echo "hf adapter: teardown for $(hf_space_id "$slug") is not automated (pause it in the Hub UI)" >&2
}
