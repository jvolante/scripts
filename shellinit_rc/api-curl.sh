# shellinit:contexts=any
# shellinit:tools=curl
# ---------------------------------------------------------------------------
# api-curl-helpers — shared curl/auth utilities for API wrapper scripts.
#
# Provides:
#   api_curl  — prepends a base URL to the first non-flag argument and fires
#               curl with auth + JSON content-type headers injected.
#   keepalive — runs a command while printing dots every 30 s so CI log
#               streaming / terminal connections don't time out.
#
# Sourced automatically via shellinit when the api-curl-helpers package is
# installed.  Downstream modules declare requires=api-curl so it is always
# sourced first.
#
# Usage: api_curl <base_url> <auth_header> [curl flags...] <endpoint> [curl flags...]
#   base_url    — e.g. "https://jira.example.com/rest/api/2"
#   auth_header — full value for the Authorization header,
#                 e.g. "Bearer $TOKEN" or "Basic $ENCODED".
#                 Pass an empty string to omit the Authorization header entirely.
#   endpoint    — first non-flag argument; base_url + "/" + endpoint is used as
#                 the final URL.
#
# Two-part flags (-X, -d, --data, --data-urlencode, -H) have their value
# argument preserved correctly.
# ---------------------------------------------------------------------------

declare -f api_curl > /dev/null 2>&1 && return

api_curl() {
  local base_url="$1"
  local auth_header="$2"
  shift 2

  local args=()
  local endpoint_set=0
  local skip_next=0
  for arg in "$@"; do
    if [[ $skip_next -eq 1 ]]; then
      args+=("$arg")
      skip_next=0
    elif [[ "$arg" == -X || "$arg" == -d || "$arg" == --data || "$arg" == --data-urlencode || "$arg" == -H ]]; then
      args+=("$arg")
      skip_next=1
    elif [[ "$arg" == -* ]]; then
      args+=("$arg")
    elif [[ $endpoint_set -eq 0 ]]; then
      args+=("${base_url}/${arg}")
      endpoint_set=1
    else
      args+=("$arg")
    fi
  done
  if [[ $endpoint_set -eq 0 ]]; then
    printf 'api_curl: no endpoint provided\n' >&2
    return 1
  fi
  local auth_args=()
  [[ -n "$auth_header" ]] && auth_args=(-H "Authorization: ${auth_header}")
  curl -s \
    "${auth_args[@]}" \
    -H "Content-Type: application/json" \
    "${args[@]}"
}

# Wrapper that prints dots to keep a process' log alive during long-running
# commands (e.g. slow CI downloads, remote builds).
# Usage: keepalive <command> [args...]
keepalive() {
  while sleep 30; do printf '.'; done &
  local _kl_pid=$!
  "$@"
  local _kl_ret=$?
  kill "$_kl_pid" 2>/dev/null
  return "$_kl_ret"
}
