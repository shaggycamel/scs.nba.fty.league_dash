#!/bin/bash
# Hugging Face Spaces deploy adapter -----------------------------------------
# League container naming: <owner>/<slug> served at
# https://<owner>-<slug>.hf.space (embed the .hf.space URL).
# Requires HUGGINGFACE_TOKEN unless DRY_RUN=1.

: "${HF_OWNER:=shaggycamel}"
: "${HF_IMAGE_BASENAME:=scs.nba.fty.league_dash}"

hf_space_id() {
  echo "${HF_OWNER}/${1}"
}

adapter_url() {
  echo "https://${HF_OWNER}-${1}.hf.space"
}

# Resolve an image tag to its immutable digest (repo@sha256:...) via the Docker
# Hub registry API. Pinning the digest is what guarantees the Space is never
# served a stale image: a `FROM image:latest` can hit a cached layer, but a
# digest is content-addressed, so a changed image (new data baked into every
# league build) forces a real pull. Falls back to the tag as-is if the registry
# can't be reached, so a deploy never hard-fails on this.
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

  local token
  token="$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${path}:pull" \
    | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  if [ -z "$token" ]; then printf '%s' "$image"; return 0; fi

  local digest
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
  else
    echo "[hf] WARN: could not resolve a digest for ${image}; using the tag (may serve a stale build)" >&2
    printf '%s' "$image"
  fi
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
  image_ref="$(hf_image_ref "$image")"

  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}${RANDOM}"

  local df_json="FROM ${image_ref}\\nARG SPACE_REBUILD=${stamp}\\nRUN echo \\\"space rebuild ${stamp}\\\"\\nEXPOSE 7860\\nUSER rstudio\\nCMD [\\\"R\\\", \\\"-e\\\", \\\"options('shiny.port'=7860, 'shiny.host'='0.0.0.0'); library(${app}); ${app}::run_app()\\\"]"

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

  hf_configure_space "$repo" "$image" "$app" || return 1
  echo "[hf] configured ${repo} (FROM ${image})"
}

# Deploy: commit a Dockerfile pinned to the just-pushed image digest (which makes
# HF rebuild and re-pull exactly what was pushed), then nudge a restart. Runs for
# every Space on every deploy, so each cron.sh run rebuilds the Space rather than
# silently serving the previous build.
adapter_deploy() {
  local slug="$1"
  local image="$2"
  local app="${3:-league}"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] rebuild + restart HF space $(hf_space_id "$slug") (image ${image:-<none>}, app ${app}) -> $(adapter_url "$slug")"
    return 0
  fi

  : "${HUGGINGFACE_TOKEN:?HUGGINGFACE_TOKEN is required for HF deploys}"

  # The commit is what guarantees a fresh image; it must succeed.
  hf_configure_space "$(hf_space_id "$slug")" "$image" "$app" || return 1

  # The factory restart is a best-effort nudge on top of the rebuild the commit
  # already queued, and can race that build, so a failure here is not fatal.
  if ! curl -sf -X POST \
    "https://huggingface.co/api/spaces/$(hf_space_id "$slug")/restart?factory=true" \
    -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" >/dev/null; then
    echo "[hf] WARN: restart for $(hf_space_id "$slug") errored; the committed Dockerfile still triggers a rebuild" >&2
  fi
}

adapter_teardown() {
  local slug="$1"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] teardown HF space $(hf_space_id "$slug")"
    return 0
  fi
  echo "hf adapter: teardown for $(hf_space_id "$slug") is not automated (pause it in the Hub UI)" >&2
}
