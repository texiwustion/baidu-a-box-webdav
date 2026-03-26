#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CONFIG_FILE="${WEBDAV_CONFIG_FILE:-$ROOT_DIR/.local/baidu-a-box-webdav.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${WEBDAV_BASE_URL:?WEBDAV_BASE_URL is required}"
: "${WEBDAV_USERNAME:?WEBDAV_USERNAME is required}"
: "${WEBDAV_PASSWORD:?WEBDAV_PASSWORD is required}"
WEBDAV_RETRY_ATTEMPTS="${WEBDAV_RETRY_ATTEMPTS:-5}"
WEBDAV_RETRY_DELAY_SECONDS="${WEBDAV_RETRY_DELAY_SECONDS:-2}"

AUTH_ARGS=(-u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}")
BASE_URL="${WEBDAV_BASE_URL%/}"

usage() {
  cat <<'EOF'
Usage:
  a-box-webdav.sh check
  a-box-webdav.sh list
  a-box-webdav.sh upload <local_path> [remote_name]
  a-box-webdav.sh upload-versioned <local_path> [--git-sha]
  a-box-webdav.sh download <remote_name> [local_path]
  a-box-webdav.sh delete <remote_name>
EOF
}

urlencode_path() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote

path = sys.argv[1]
parts = [quote(part, safe="") for part in path.split("/") if part]
print("/".join(parts))
PY
}

join_remote_url() {
  local relative_path="$1"
  local encoded
  encoded="$(urlencode_path "$relative_path")"
  if [[ -n "$encoded" ]]; then
    printf '%s/%s' "$BASE_URL" "$encoded"
  else
    printf '%s/' "$BASE_URL"
  fi
}

build_versioned_name() {
  local local_path="$1"
  local git_sha="$2"
  local filename stem ext timestamp remote_name

  filename="$(basename "$local_path")"
  stem="$filename"
  ext=""
  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    stem="${filename%.*}"
    ext=".${filename##*.}"
  fi

  timestamp="$(TZ="${A_BOX_UPLOAD_TZ:-Asia/Shanghai}" date +%Y%m%d-%H%M%S)"

  remote_name="${stem}-${timestamp}"
  if [[ -n "$git_sha" ]]; then
    remote_name="${remote_name}-${git_sha}"
  fi
  printf '%s%s' "$remote_name" "$ext"
}

retry_with_backoff() {
  local mode="$1"
  shift
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if (( attempt >= WEBDAV_RETRY_ATTEMPTS )); then
      return 1
    fi
    if [[ "$mode" == "download" ]]; then
      echo "Download not ready yet, retrying in ${WEBDAV_RETRY_DELAY_SECONDS}s..." >&2
    elif [[ "$mode" == "delete" ]]; then
      echo "Remote file still locked, retrying in ${WEBDAV_RETRY_DELAY_SECONDS}s..." >&2
    fi
    sleep "$WEBDAV_RETRY_DELAY_SECONDS"
    attempt=$((attempt + 1))
  done
}

cmd="${1:-}"
case "$cmd" in
  check)
    curl -fsS "${AUTH_ARGS[@]}" -X PROPFIND -H 'Depth: 0' "$BASE_URL/" >/dev/null
    echo "WebDAV OK: $BASE_URL"
    ;;
  list)
    curl -fsS "${AUTH_ARGS[@]}" -X PROPFIND -H 'Depth: 1' "$BASE_URL/"
    ;;
  upload)
    local_path="${2:-}"
    remote_name="${3:-}"
    if [[ -z "$local_path" ]]; then
      usage >&2
      exit 1
    fi
    if [[ ! -f "$local_path" ]]; then
      echo "Local file not found: $local_path" >&2
      exit 1
    fi
    if [[ -z "$remote_name" ]]; then
      remote_name="$(basename "$local_path")"
    fi
    curl -fsS -o /dev/null "${AUTH_ARGS[@]}" -T "$local_path" "$(join_remote_url "$remote_name")"
    echo "Uploaded: $local_path -> $remote_name"
    ;;
  upload-versioned)
    local_path="${2:-}"
    sha_flag="${3:-}"
    git_sha=""
    if [[ -z "$local_path" ]]; then
      usage >&2
      exit 1
    fi
    if [[ ! -f "$local_path" ]]; then
      echo "Local file not found: $local_path" >&2
      exit 1
    fi
    if [[ -n "$sha_flag" && "$sha_flag" != "--git-sha" ]]; then
      echo "Unknown flag: $sha_flag" >&2
      usage >&2
      exit 1
    fi
    if [[ "$sha_flag" == "--git-sha" ]]; then
      if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_sha="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
      fi
      if [[ -z "$git_sha" ]]; then
        echo "Warning: --git-sha requested but git short SHA is unavailable; proceeding without SHA suffix." >&2
      fi
    fi
    remote_name="$(build_versioned_name "$local_path" "$git_sha")"
    curl -fsS -o /dev/null "${AUTH_ARGS[@]}" -T "$local_path" "$(join_remote_url "$remote_name")"
    echo "Uploaded versioned: $local_path -> $remote_name"
    ;;
  download)
    remote_name="${2:-}"
    local_path="${3:-}"
    if [[ -z "$remote_name" ]]; then
      usage >&2
      exit 1
    fi
    if [[ -z "$local_path" ]]; then
      local_path="$ROOT_DIR/$(basename "$remote_name")"
    fi
    mkdir -p "$(dirname "$local_path")"
    retry_with_backoff download curl -fsS "${AUTH_ARGS[@]}" "$(join_remote_url "$remote_name")" -o "$local_path"
    echo "Downloaded: $remote_name -> $local_path"
    ;;
  delete)
    remote_name="${2:-}"
    if [[ -z "$remote_name" ]]; then
      usage >&2
      exit 1
    fi
    retry_with_backoff delete curl -fsS -o /dev/null "${AUTH_ARGS[@]}" -X DELETE "$(join_remote_url "$remote_name")"
    echo "Deleted: $remote_name"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
