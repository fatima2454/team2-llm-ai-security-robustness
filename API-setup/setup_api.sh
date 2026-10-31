#!/usr/bin/env bash
# Team 2 — load and verify the Perplexity Agent API key.
# Does not print the key, write it to disk, or install host packages.
# Do not run this file with bash -x or set -x; that can print the key.
#
# Keep the key in this SSM shell:
#   source API-setup/setup_api.sh
#
# Verify the key. The value does not remain in the parent shell:
#   bash API-setup/setup_api.sh --check
#
# Docs:
#   https://docs.perplexity.ai/docs/getting-started/quickstart
#   https://docs.perplexity.ai/docs/agent-api/quickstart
#   https://docs.perplexity.ai/api-reference/agent-post

API_URL="https://api.perplexity.ai/v1/agent"
SSM_NAME="${PPLX_SSM_PARAMETER:-/team2/perplexity/api-key}"
SMOKE_MODEL="${PPLX_SMOKE_MODEL:-openai/gpt-5.6-sol}"

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  _SOURCED=1
else
  _SOURCED=0
fi

_fail() {
  printf 'ERROR: %s\n' "$1" >&2
  if [[ $_SOURCED -eq 1 ]]; then
    return 1
  fi
  exit 1
}

_load_from_ssm() {
  local value err_file
  if ! command -v aws >/dev/null 2>&1; then
    _fail "aws CLI not found. Export PERPLEXITY_API_KEY in this shell, or run this on the EC2 instance." || return 1
  fi
  err_file="$(mktemp)"
  if ! value="$(aws ssm get-parameter \
      --name "$SSM_NAME" \
      --with-decryption \
      --query Parameter.Value \
      --output text 2>"$err_file")"; then
    cat "$err_file" >&2
    rm -f "$err_file"
    _fail "Could not read SSM parameter ${SSM_NAME}. Check the name, AWS_REGION, and ssm:GetParameter permission." || return 1
  fi
  rm -f "$err_file"
  if [[ -z "$value" || "$value" == "None" ]]; then
    _fail "SSM parameter ${SSM_NAME} was empty." || return 1
  fi
  PERPLEXITY_API_KEY="$value"
  export PERPLEXITY_API_KEY
  unset value
}

_smoke() {
  local payload http_code header_file
  if ! command -v curl >/dev/null 2>&1; then
    _fail "curl is required for --check." || return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    _fail "python3 is required to build the request body." || return 1
  fi
  if [[ ! "$SMOKE_MODEL" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    _fail "PPLX_SMOKE_MODEL contains unsupported characters." || return 1
  fi
  payload="$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1], "input": "Reply with the single word ok."}))' "$SMOKE_MODEL")"
  header_file="$(mktemp)"
  http_code="$(curl -sS -D "$header_file" -o /dev/null -w '%{http_code}' \
    --max-time 180 \
    -X POST "$API_URL" \
    -H "Authorization: Bearer ${PERPLEXITY_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "$payload" || true)"
  printf 'HTTP %s\n' "${http_code:-000}"
  if [[ "$http_code" == "429" ]]; then
    awk 'BEGIN{IGNORECASE=1} $1=="retry-after:" {print "Wait for Retry-After:", $2}' "$header_file"
  fi
  rm -f "$header_file"
  unset payload
  case "$http_code" in
    200) return 0 ;;
    400) _fail "Request rejected. Set PPLX_SMOKE_MODEL to a current id from the Agent API models page." || return 1 ;;
    401) _fail "Authentication failed. Create or rotate the key in the API Console. Do not paste it into chat." || return 1 ;;
    402) _fail "Payment required. Add API credits in the API Console billing page." || return 1 ;;
    429) _fail "Rate limited. Wait for Retry-After, then run --check again." || return 1 ;;
    *) _fail "Unexpected HTTP status ${http_code:-000}." || return 1 ;;
  esac
}

DO_CHECK=0
for arg in "$@"; do
  case "$arg" in
    --check) DO_CHECK=1 ;;
    -h|--help)
      cat <<'EOF'
Usage:
  source API-setup/setup_api.sh          Load the key into this shell.
  bash API-setup/setup_api.sh --check    Load if needed, then print only the HTTP status.

Environment:
  PERPLEXITY_API_KEY   Used as-is when already set. Never printed.
  PPLX_SSM_PARAMETER   SSM name. Default: /team2/perplexity/api-key
  PPLX_SMOKE_MODEL     Smoke-test model. Default: openai/gpt-5.6-sol
  AWS_REGION           Must match the region of the SSM parameter.
EOF
      if [[ $_SOURCED -eq 1 ]]; then
        return 0
      fi
      exit 0
      ;;
    *)
      _fail "Unknown argument: $arg" || return 1
      ;;
  esac
done

if [[ -z "${PERPLEXITY_API_KEY:-}" ]]; then
  _load_from_ssm || return 1
fi

if [[ -z "${PERPLEXITY_API_KEY:-}" ]]; then
  _fail "PERPLEXITY_API_KEY is not set." || return 1
fi

printf 'key present\n'

if [[ $DO_CHECK -eq 1 ]]; then
  _smoke || return 1
elif [[ $_SOURCED -eq 0 ]]; then
  printf 'The key existed only in this process. To keep it, run:\n  source API-setup/setup_api.sh\n'
fi
