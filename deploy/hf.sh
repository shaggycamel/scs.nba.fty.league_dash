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

# Commit the Space's Dockerfile with a fresh cache-busting build arg. HF only
# rebuilds a Docker Space when its repository changes, and a bare restart keeps
# serving the previously built image -- so a freshly pushed :latest is otherwise
# never picked up. The changing ARG/RUN makes every deploy a real repo change,
# forcing the rebuild that re-pulls the image. library() is required so LazyData
# objects (e.g. ls_nba_teams) are attached.
hf_configure_space() {
  local repo="$1"
  local image="$2"
  local app="$3"

  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}${RANDOM}"

  local df_json="FROM ${image}\\nARG SPACE_REBUILD=${stamp}\\nRUN echo \\\"space rebuild ${stamp}\\\"\\nEXPOSE 7860\\nUSER rstudio\\nCMD [\\\"R\\\", \\\"-e\\\", \\\"options('shiny.port'=7860, 'shiny.host'='0.0.0.0'); library(${app}); ${app}::run_app()\\\"]"

  printf '%s\n' \
    '{"key":"header","value":{"summary":"provision space"}}' \
    "{\"key\":\"file\",\"value\":{\"path\":\"Dockerfile\",\"content\":\"${df_json}\",\"encoding\":\"utf-8\"}}" |
    curl -sf -X POST "https://huggingface.co/api/spaces/${repo}/commit/main" \
      -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
      -H "Content-Type: application/x-ndjson" \
      --data-binary @- >/dev/null || return 1
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

# Deploy: commit a cache-busted Dockerfile (so HF rebuilds and re-pulls the image
# just pushed) and restart. This runs for every Space on every deploy, so each
# cron.sh run rebuilds the Space rather than silently serving the previous build.
adapter_deploy() {
  local slug="$1"
  local image="$2"
  local app="${3:-league}"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] rebuild + restart HF space $(hf_space_id "$slug") (image ${image:-<none>}, app ${app}) -> $(adapter_url "$slug")"
    return 0
  fi

  : "${HUGGINGFACE_TOKEN:?HUGGINGFACE_TOKEN is required for HF deploys}"
  hf_configure_space "$(hf_space_id "$slug")" "$image" "$app" || return 1
  curl -sf -X POST \
    "https://huggingface.co/api/spaces/$(hf_space_id "$slug")/restart?factory=true" \
    -H "Authorization: Bearer ${HUGGINGFACE_TOKEN}"
}

adapter_teardown() {
  local slug="$1"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] teardown HF space $(hf_space_id "$slug")"
    return 0
  fi
  echo "hf adapter: teardown for $(hf_space_id "$slug") is not automated (pause it in the Hub UI)" >&2
}
