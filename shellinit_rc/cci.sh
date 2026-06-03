# shellinit:contexts=any
# shellinit:requires=api-curl
# shellinit:tools=curl,jq
# ---------------------------------------------------------------------------
# CircleCI helpers
# All functions read $CCI_URL, $CCI_PERSONAL_TOKEN
#
# Project slugs use the format: github/<org>/<repo>  e.g. github/my-org/my-repo
#
# Chaining examples:
#   cci-builds github/my-org/my-repo | jq -r '.workflow_id' | sort -u | xargs -I{} cci-workflow {}
#   cci-builds github/my-org/my-repo | jq 'select(.status=="failed")' | jq -r '.workflow_id' | sort -u | xargs -I{} cci-rerun {}
# ---------------------------------------------------------------------------

declare -f cci-curl > /dev/null 2>&1 && return

# Public curl wrapper — CircleCI uses Circle-Token header, not Bearer.
# Prepends $CCI_URL/api/ to the first non-flag argument.
# Usage: cci-curl [curl flags...] <v1.1/... or v2/...> [curl flags...]
# Examples:
#   cci-curl v2/me
#   cci-curl v1.1/recent-builds -G --data-urlencode 'limit=5'
#   cci-curl -X POST v2/workflow/<id>/rerun -d '{}'
cci-curl() {
  api_curl "${CCI_URL}/api" "" -H "Circle-Token: ${CCI_PERSONAL_TOKEN}" "$@"
}

# Get info about the authenticated user
# Usage: cci-me
cci-me() {
  cci-curl v2/me | jq '{id, login: .login, name}'
}

# List recent builds across all projects
# Usage: cci-recent [limit]
cci-recent() {
  local limit="${1:-25}"
  cci-curl v1.1/recent-builds -G --data-urlencode "limit=${limit}" \
  | jq '.[] | {
      build_num,
      status,
      subject,
      branch,
      repo:     .reponame,
      workflow: .workflows.workflow_name,
      job:      .workflows.job_name,
      started:  .start_time,
      stopped:  .stop_time,
      url:      .build_url
    }'
}

# List recent builds for a specific project
# Usage: cci-builds <project-slug> [branch] [limit]
# Example: cci-builds github/my-org/my-repo
#          cci-builds github/my-org/my-repo main 10
cci-builds() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: cci-builds <project-slug> [branch] [limit]\n' >&2
    return 1
  fi
  local slug="$1"
  local branch="${2:-}"
  local limit="${3:-25}"
  local endpoint="v1.1/project/${slug}"
  if [[ -n "$branch" ]]; then
    # URL-encode slashes in branch names (e.g. user/feature-branch)
    local encoded_branch
    encoded_branch="$(jq -rn --arg v "$branch" '$v | @uri')"
    endpoint="v1.1/project/${slug}/tree/${encoded_branch}"
  fi
  cci-curl "${endpoint}" -G --data-urlencode "limit=${limit}" \
  | jq '.[] | {
      build_num,
      status,
      subject,
      branch,
      workflow: .workflows.workflow_name,
      job:      .workflows.job_name,
      workflow_id: .workflows.workflow_id,
      started:  .start_time,
      stopped:  .stop_time,
      url:      .build_url
    }'
}

# Get jobs in a workflow
# Usage: cci-workflow <workflow-id>
# Chains: cci-builds github/my-org/my-repo | jq -r '.workflow_id' | sort -u | xargs -I{} cci-workflow {}
cci-workflow() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: cci-workflow <workflow-id>\n' >&2
    return 1
  fi
  local wf_id="$1"
  local meta
  meta=$(cci-curl "v2/workflow/${wf_id}" | jq '{id, name, status, pipeline_id, created_at, stopped_at}')
  local jobs
  jobs=$(cci-curl "v2/workflow/${wf_id}/job" | jq '[.items[] | {id, name, status, job_number, started_at, stopped_at}]')
  jq -n --argjson meta "$meta" --argjson jobs "$jobs" '$meta + {jobs: $jobs}'
}

# Sanitize secrets from log output on stdin.
# Redacts SSH/TLS private keys, API tokens, and other credentials.
# Each unique secret value is assigned a stable sequential ID so reuse is visible.
# PEM private-key blocks are collapsed to a single marker line.
# Usage: cci-log-sanitize
# Example: cci-log github/my-org/my-repo 3001 | cci-log-sanitize
cci-log-sanitize() {
  awk '
  # Return the stable ID for a given secret value, assigning one if new.
  function secret_id(val,    id) {
    if (val in _ids) return _ids[val]
    id = ++_counter
    _ids[val] = id
    return id
  }

  # ---------------------------------------------------------------------------
  BEGIN { _counter = 0; _in_pem = 0 }

  # --- PEM block handling (stateful, collapse entire block) -------------------
  /-----BEGIN [A-Z ]*KEY-----/ || /-----BEGIN CERTIFICATE-----/ || /-----BEGIN ENCRYPTED PRIVATE KEY-----/ {
    _pem_marker = $0
    # Use the BEGIN line itself as the key for stable ID assignment.
    _pem_id = secret_id("pem:" _pem_marker)
    print "[SECRET:pem-key:" _pem_id "]"
    _in_pem = 1
    next
  }
  _in_pem && /-----END / {
    _in_pem = 0
    next
  }
  _in_pem { next }

  # --- inline secret patterns -------------------------------------------------
  {
    line = $0

    # Circle-Token header value
    while (match(line, /Circle-Token:[[:space:]]*([^[:space:]"'"'"'\\]+)/, m)) {
      id = secret_id(m[1])
      sub(m[1], "[SECRET:circle-token:" id "]", line)
      break
    }

    # Authorization: Bearer <token>
    while (match(line, /Authorization:[[:space:]]*Bearer[[:space:]]+([^[:space:]"'"'"'\\]+)/, m)) {
      id = secret_id(m[1])
      sub(m[1], "[SECRET:bearer-token:" id "]", line)
      break
    }

    # Authorization: Basic <value>
    while (match(line, /Authorization:[[:space:]]*Basic[[:space:]]+([^[:space:]"'"'"'\\]+)/, m)) {
      id = secret_id(m[1])
      sub(m[1], "[SECRET:basic-auth:" id "]", line)
      break
    }

    # AWS access key IDs: AKIA followed by 16 uppercase alphanumerics
    while (match(line, /(AKIA[A-Z0-9]{16})/, m)) {
      id = secret_id(m[1])
      gsub(m[1], "[SECRET:aws-key:" id "]", line)
      break
    }

    # GitHub tokens: ghp_ / ghs_ followed by 36 or more alphanumerics
    while (match(line, /(gh[ps]_[A-Za-z0-9]{36,})/, m)) {
      id = secret_id(m[1])
      gsub(m[1], "[SECRET:github-token:" id "]", line)
      break
    }

    # GitLab personal access tokens: glpat- followed by 20 alphanumerics/hyphens
    while (match(line, /(glpat-[A-Za-z0-9-]{20})/, m)) {
      id = secret_id(m[1])
      gsub(m[1], "[SECRET:gitlab-token:" id "]", line)
      break
    }

    # JWT: three base64url segments each at least 20 chars, separated by dots
    while (match(line, /([A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,})/, m)) {
      id = secret_id(m[1])
      gsub(m[1], "[SECRET:jwt:" id "]", line)
      break
    }

    # SSH public keys in known_hosts format: <host> <key-type> <base64blob>
    # Keeps the host and key-type (useful context) but replaces the blob.
    # Key types: ssh-rsa, ssh-ed25519, ecdsa-sha2-nistp{256,384,521}
    while (match(line, /^([^[:space:]]+[[:space:]]+(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)[[:space:]]+)(AAAA[A-Za-z0-9+\/]+=*)/, m)) {
      id = secret_id(m[3])
      # m[1] is "<host> <key-type> ", m[3] is the blob — replace blob with marker.
      # Use substr arithmetic to avoid regex-metachar issues with sub().
      blob_start = index(line, m[3])
      line = substr(line, 1, blob_start - 1) "[PUBLIC-KEY:" m[2] ":" id "]" substr(line, blob_start + length(m[3]))
      break
    }

    # Environment variable assignments where the var name suggests a secret.
    # Matches: export FOO_TOKEN="value", FOO_SECRET=value, etc.
    # Captures only the value portion so the var name stays visible.
    while (match(line, /[Ee][Xx][Pp][Oo][Rr][Tt][[:space:]]+[A-Z_a-z][A-Z_a-z0-9]*(_[Kk][Ee][Yy]|_[Tt][Oo][Kk][Ee][Nn]|_[Ss][Ee][Cc][Rr][Ee][Tt]|_[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|_[Pp][Aa][Ss][Ss][Ww][Dd]|_[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll])[[:space:]]*=[[:space:]]*([^[:space:]"'"'"';\\]+)/, m) || \
          match(line, /[A-Z_][A-Z_0-9]*(_KEY|_TOKEN|_SECRET|_PASSWORD|_PASSWD|_CREDENTIAL)[[:space:]]*=[[:space:]]*([^[:space:]"'"'"';\\]+)/, m)) {
      # Capture group index differs: use whichever is non-empty.
      val = (m[2] != "") ? m[2] : m[3]
      if (val != "" && val !~ /^\[SECRET:/) {
        id = secret_id(val)
        gsub(val, "[SECRET:env-secret:" id "]", line)
      }
      break
    }

    print line
  }
  '
}

# Strip progress-indicator noise from CCI log output.
# Simulates terminal CR-overwrite behaviour: for each line, keeps only the
# final segment after the last bare \r (the state a terminal would display).
# Works on any tool that uses \r to redraw progress (git, pip, npm, etc.).
# By default also sanitizes secrets (SSH/API keys etc.) — use --no-sanitize to skip.
# Usage: cci-log-clean [--no-sanitize]
# Example: cci-log github/my-org/my-repo 3001 | cci-log-clean
cci-log-clean() {
  local sanitize=1
  if [[ "${1:-}" == "--no-sanitize" ]]; then
    sanitize=0
    shift
  fi
  # Pass 1 (--across): normalise CRLF → LF so \r\n line endings are not
  #         mistaken for progress overwrites in pass 2.
  # Pass 2 (line-by-line): strip everything up to and including the last
  #         bare \r on each line, leaving only the final overwrite state.
  # Pass 3 (optional): redact secrets.
  if [[ "$sanitize" -eq 1 ]]; then
    sd --across '\x0d\x0a' '\x0a' | sd '.*\x0d' '' | cci-log-sanitize
  else
    sd --across '\x0d\x0a' '\x0a' | sd '.*\x0d' ''
  fi
}

# Get build log output for a single job
# Falls back to fetching presigned output URLs from the v1.1 job detail when
# the direct /output endpoint returns a non-JSON 404 (common on self-hosted CCI).
# Progress-indicator noise and secrets are sanitized by default (see cci-log-clean).
# Usage: cci-log [--no-clean] [--no-sanitize] <project-slug> <build-num>
# Example: cci-log github/my-org/my-repo 3001
#          cci-log --no-clean github/my-org/my-repo 3001
#          cci-log --no-sanitize github/my-org/my-repo 3001
cci-log() {
  local clean=1 sanitize=1
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --no-clean)    clean=0;    shift ;;
      --no-sanitize) sanitize=0; shift ;;
      *) break ;;
    esac
  done

  if [[ $# -lt 2 ]]; then
    printf 'Usage: cci-log [--no-clean] [--no-sanitize] <project-slug> <build-num>\n' >&2
    return 1
  fi
  local slug="$1"
  local build_num="$2"

  _cci-log-raw() {
    # Try the direct output endpoint first
    local direct
    direct=$(cci-curl "v1.1/project/${slug}/${build_num}/output" 2>/dev/null)
    if echo "$direct" | jq -e '.[0].output' >/dev/null 2>&1; then
      echo "$direct" | jq -r '.[] | .output[] | .message' 2>/dev/null
      return
    fi

    # Fall back: extract presigned output_url values from the job detail and fetch each
    local urls
    urls=$(cci-curl "v1.1/project/${slug}/${build_num}" 2>/dev/null \
      | jq -r '[.steps[]? | .actions[]? | select(.output_url != null) | .output_url] | .[]' 2>/dev/null)
    if [[ -z "$urls" ]]; then
      printf 'cci-log: no output available for build %s\n' "$build_num" >&2
      return 1
    fi
    while IFS= read -r url; do
      curl -s "$url" | jq -r '.[].message' 2>/dev/null
    done <<< "$urls"
  }

  if [[ "$clean" -eq 1 ]]; then
    if [[ "$sanitize" -eq 1 ]]; then
      _cci-log-raw | cci-log-clean
    else
      _cci-log-raw | cci-log-clean --no-sanitize
    fi
  else
    _cci-log-raw
  fi
  unset -f _cci-log-raw
}

# Rerun a failed workflow from failed jobs
# Usage: cci-rerun <workflow-id>
cci-rerun() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: cci-rerun <workflow-id>\n' >&2
    return 1
  fi
  cci-curl -X POST "v2/workflow/$1/rerun" \
    -d '{"from_failed": true}' \
  | jq '{workflow_id}'
}

# Trigger a new pipeline for a project
# Usage: cci-trigger <project-slug> [branch]
# Example: cci-trigger github/my-org/my-repo main
cci-trigger() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: cci-trigger <project-slug> [branch]\n' >&2
    return 1
  fi
  local slug="$1"
  local branch="${2:-main}"
  cci-curl -X POST "v2/project/${slug}/pipeline" \
    -d "$(jq -n --arg branch "$branch" '{branch: $branch}')" \
  | jq '{id, number, state, created_at}'
}

# List all followed projects
# Usage: cci-projects
cci-projects() {
  cci-curl v1.1/projects \
  | jq '.[] | {
      slug:     ("github/" + .username + "/" + .reponame),
      repo:     .reponame,
      org:      .username,
      url:      .vcs_url,
      branches: (.branches | keys | length)
    }'
}

# Resolve the canonical CircleCI project slug from the current git repo's origin remote.
# Parses org/repo from the remote URL, then calls GET v2/project/github/<org>/<repo> to get
# the canonical slug (which may differ, e.g. gh/ vs github/).
# Prints the slug to stdout. Returns 1 if org/repo cannot be parsed or the project is not found in CCI.
# Usage: cci-slug
cci-slug() {
  local remote_url org repo slug
  remote_url=$(git remote get-url origin 2>/dev/null)
  if [[ -z "$remote_url" ]]; then
    printf 'cci-slug: not inside a git repo with an origin remote\n' >&2
    return 1
  fi
  if [[ "$remote_url" =~ ^git@[^:]+:([^/]+)/(.+)\.git$ ]]; then
    org="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ ^git@[^:]+:([^/]+)/(.+)$ ]]; then
    org="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ ^https?://[^/]+/([^/]+)/(.+)\.git$ ]]; then
    org="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ ^https?://[^/]+/([^/]+)/(.+)$ ]]; then
    org="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
  else
    printf 'cci-slug: could not parse org/repo from remote URL: %s\n' "$remote_url" >&2
    return 1
  fi
  slug=$(cci-curl "v2/project/github/${org}/${repo}" 2>/dev/null | jq -r '.slug // empty')
  if [[ -z "$slug" ]]; then
    printf 'cci-slug: project not found in CircleCI: github/%s/%s\n' "$org" "$repo" >&2
    return 1
  fi
  printf '%s' "$slug"
}

# Fetch logs for the most recently failed job on the current branch (or a given slug+branch).
# Infers the project slug and branch from git when not provided.
# Progress-indicator noise and secrets are sanitized by default (see cci-log-clean).
# Usage: cci-failed-logs [--no-clean] [--no-sanitize] [project-slug [branch]]
# Options:
#   --no-clean     Disable stripping of progress-indicator noise from log output
#   --no-sanitize  Disable secret sanitization from log output
# Examples:
#   cci-failed-logs
#   cci-failed-logs --no-clean
#   cci-failed-logs --no-sanitize
#   cci-failed-logs github/my-org/my-repo
#   cci-failed-logs github/my-org/my-repo feature/my-branch
cci-failed-logs() {
  local slug branch clean=1 sanitize=1

  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --no-clean)    clean=0;    shift ;;
      --no-sanitize) sanitize=0; shift ;;
      *) break ;;
    esac
  done

  if [[ $# -ge 1 ]]; then
    slug="$1"
    branch="${2:-}"
  else
    slug=$(cci-slug) || return 1
    branch=$(git branch --show-current 2>/dev/null)
    if [[ -z "$branch" ]]; then
      printf 'cci-failed-logs: could not determine current branch\n' >&2
      return 1
    fi
  fi

  printf 'Project : %s\n' "$slug"
  printf 'Branch  : %s\n\n' "$branch"

  # Find the most recently failed build on this branch
  local failed_build
  failed_build=$(cci-builds "$slug" "$branch" 25 \
    | jq -s 'map(select(.status == "failed")) | first | {build_num, job, workflow}')

  if [[ -z "$failed_build" || "$failed_build" == "null" ]]; then
    printf 'No failed builds found for %s on %s\n' "$slug" "$branch" >&2
    return 1
  fi

  local build_num job_name workflow_name
  build_num=$(printf '%s' "$failed_build" | jq -r '.build_num')
  job_name=$(printf '%s' "$failed_build" | jq -r '.job')
  workflow_name=$(printf '%s' "$failed_build" | jq -r '.workflow')

  printf 'Failed job : %s / %s  (build #%s)\n\n' "$workflow_name" "$job_name" "$build_num"

  local log_flags=()
  [[ "$clean" -eq 0 ]]    && log_flags+=(--no-clean)
  [[ "$sanitize" -eq 0 ]] && log_flags+=(--no-sanitize)
  cci-log "${log_flags[@]}" "$slug" "$build_num"
}

# Wait for all CI jobs on the current branch's remote HEAD to finish, then print a summary.
# If any jobs failed, prints their logs automatically. Exits non-zero if any job failed.
#
# Only watches pipelines whose revision matches the current remote tracking SHA, so a
# stale in-progress pipeline from a previous push is ignored.
#
# Usage: cci-wait-on-jobs [project-slug [branch]] [--interval <seconds>] [--timeout <seconds>] [--progress] [--no-logs] [--no-clean] [--no-sanitize]
# Options:
#   --interval <seconds>  Poll interval (default: 30)
#   --timeout  <seconds>  Give up after this many seconds (default: 36000)
#   --progress            Print a live job-status table on each poll cycle
#   --no-logs             On failure, print only pass/fail/cancel status; skip build log output
#   --no-clean            Disable stripping of progress-indicator noise from log output
#   --no-sanitize         Disable secret sanitization from log output
# Examples:
#   cci-wait-on-jobs
#   cci-wait-on-jobs --progress
#   cci-wait-on-jobs --no-logs
#   cci-wait-on-jobs --no-sanitize
#   cci-wait-on-jobs github/my-org/my-repo feature/my-branch --interval 15 --progress
cci-wait-on-jobs() {
  local slug branch
  local interval=30 timeout=36000 progress=0 no_logs=0 clean=1 sanitize=1

  # --- parse args (positional slug/branch first, then flags) ------------------
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval)    interval="$2";  shift 2 ;;
      --timeout)     timeout="$2";   shift 2 ;;
      --progress)    progress=1;     shift   ;;
      --no-logs)     no_logs=1;      shift   ;;
      --no-clean)    clean=0;        shift   ;;
      --no-sanitize) sanitize=0;     shift   ;;
      *)             positional+=("$1"); shift ;;
    esac
  done

  if [[ ${#positional[@]} -ge 1 ]]; then
    slug="${positional[0]}"
    branch="${positional[1]:-}"
  else
    slug=$(cci-slug) || return 1
    branch=$(git branch --show-current 2>/dev/null)
    if [[ -z "$branch" ]]; then
      printf 'cci-wait-on-jobs: could not determine current branch\n' >&2
      return 1
    fi
  fi

  # --- resolve the remote HEAD SHA for this branch ----------------------------
  # Use the tracking ref if branch was inferred from git; otherwise ask the remote.
  local remote_sha
  if [[ -n "$(git rev-parse --git-dir 2>/dev/null)" ]]; then
    remote_sha=$(git rev-parse "origin/${branch}" 2>/dev/null)
  fi
  if [[ -z "$remote_sha" ]]; then
    printf 'cci-wait-on-jobs: could not resolve remote SHA for origin/%s\n' "$branch" >&2
    return 1
  fi

  local encoded_branch
  encoded_branch="$(jq -rn --arg v "$branch" '$v | @uri')"

  # --- find the pipeline for the current remote SHA ---------------------------
  local pipeline_id pipeline_num
  local elapsed=0
  printf 'Waiting for CI on %s @ %s...\n' "$branch" "${remote_sha:0:8}"

  # CCI returns pipelines newest-first; scan up to 10 to find one matching our SHA.
  local pipeline_json
  pipeline_json=$(cci-curl "v2/project/${slug}/pipeline?branch=${encoded_branch}" 2>/dev/null \
    | jq --arg sha "$remote_sha" '
        .items | map(select(.vcs.revision == $sha)) | first
        | {id, number}')
  pipeline_id=$(printf '%s' "$pipeline_json" | jq -r '.id // empty')
  pipeline_num=$(printf '%s' "$pipeline_json" | jq -r '.number // empty')

  local pipeline_retries=0
  local max_pipeline_retries=3
  while [[ -z "$pipeline_id" ]]; do
    if [[ "$pipeline_retries" -ge "$max_pipeline_retries" ]]; then
      printf 'cci-wait-on-jobs: no pipeline found for SHA %s on %s after %d attempts\n' "${remote_sha:0:8}" "$branch" "$max_pipeline_retries" >&2
      return 1
    fi
    printf 'cci-wait-on-jobs: no pipeline found for SHA %s on %s — retrying in 60s... (%d/%d)\n' "${remote_sha:0:8}" "$branch" "$(( pipeline_retries + 1 ))" "$max_pipeline_retries" >&2
    sleep 60
    elapsed=$(( elapsed + 60 ))
    pipeline_retries=$(( pipeline_retries + 1 ))
    pipeline_json=$(cci-curl "v2/project/${slug}/pipeline?branch=${encoded_branch}" 2>/dev/null \
      | jq --arg sha "$remote_sha" '
          .items | map(select(.vcs.revision == $sha)) | first
          | {id, number}')
    pipeline_id=$(printf '%s' "$pipeline_json" | jq -r '.id // empty')
    pipeline_num=$(printf '%s' "$pipeline_json" | jq -r '.number // empty')
  done

  printf 'Pipeline #%s (%s)\n\n' "$pipeline_num" "${pipeline_id:0:8}"

  # --- poll until all workflows are in a terminal state -----------------------
  # Workflow terminal states: success, failed, error, canceled, unauthorised
  # Note: "failing" means jobs have failed but others are still running — not terminal.
  local terminal_states='["success","failed","error","canceled","unauthorised"]'
  # Number of lines printed by the previous progress render (used to move cursor back up).
  local _progress_lines=0

  while true; do
    local workflows_json
    workflows_json=$(cci-curl "v2/pipeline/${pipeline_id}/workflow" 2>/dev/null \
      | jq '[.items[] | {id, name, status}]')

    local all_done
    all_done=$(printf '%s' "$workflows_json" \
      | jq --argjson t "$terminal_states" 'all(.status as $s | $t | contains([$s]))')

    if [[ "$progress" -eq 1 ]]; then
      # Move cursor back up to overwrite the previous render.
      if [[ "$_progress_lines" -gt 0 ]]; then
        printf '\033[%dA' "$_progress_lines"
      fi

      # Print one line per job, grouped under their workflow.
      local lines_printed=0

      printf "[%ds]\n" "$elapsed"
      (( lines_printed++ ))

      local wf_id wf_name wf_status
      while IFS=$'\t' read -r wf_id wf_name wf_status; do
        local wf_sym
        case "$wf_status" in
          success)                      wf_sym="✓" ;;
          failed|error|unauthorised)    wf_sym="✗" ;;
          canceled)                     wf_sym="⊘" ;;
          *)                            wf_sym="…" ;;
        esac

        printf '\r\033[K%s %s\n' "$wf_sym" "$wf_name"
        (( lines_printed++ ))

        # For in-progress workflows, list every job on its own indented line.
        if [[ "$wf_status" != "success" && "$wf_status" != "failed" \
           && "$wf_status" != "error"   && "$wf_status" != "canceled" \
           && "$wf_status" != "unauthorised" ]]; then
          local job_name job_status job_sym
          while IFS=$'\t' read -r job_name job_status; do
            case "$job_status" in
              success)    job_sym="✓" ;;
              failed)     job_sym="✗" ;;
              running)    job_sym="…" ;;
              canceled)   job_sym="⊘" ;;
              blocked)    job_sym="⏸" ;;
              *)          job_sym="?" ;;
            esac
            printf '\r\033[K    %s %-40s\n' "$job_sym" "$job_name"
            (( lines_printed++ ))
          done < <(cci-curl "v2/workflow/${wf_id}/job" 2>/dev/null \
            | jq -r '.items[] | "\(.name)\t\(.status)"' 2>/dev/null)
        fi
      done < <(printf '%s' "$workflows_json" | jq -r '.[] | "\(.id)\t\(.name)\t\(.status)"')

      _progress_lines="$lines_printed"
    fi

    if [[ "$all_done" == "true" ]]; then
      break
    fi

    if [[ "$elapsed" -ge "$timeout" ]]; then
      printf 'cci-wait-on-jobs: timed out after %ds\n' "$timeout" >&2
      return 1
    fi

    sleep "$interval"
    elapsed=$(( elapsed + interval ))
  done

  # --- final summary ----------------------------------------------------------
  local workflows_final
  workflows_final=$(cci-curl "v2/pipeline/${pipeline_id}/workflow" 2>/dev/null \
    | jq '[.items[] | {id, name, status}]')

  printf 'Pipeline #%s complete:\n' "$pipeline_num"
  local wf_name wf_status
  while IFS=$'\t' read -r wf_name wf_status; do
    printf '  %-12s %s\n' "$wf_status" "$wf_name"
  done < <(printf '%s' "$workflows_final" | jq -r '.[] | "\(.name)\t\(.status)"')
  printf '\n'

  # --- print logs for each failed job (skip cancelled) ------------------------
  # Enumerate failed jobs directly from the pipeline's workflows via v2 API so
  # we are scoped to exactly this pipeline, not just recent branch builds.
  local any_failed=0
  local wf_id wf_name wf_status
  while IFS=$'\t' read -r wf_id wf_name wf_status; do
    [[ "$wf_status" != "failed" && "$wf_status" != "error" ]] && continue
    local job_name job_status job_number
    while IFS=$'\t' read -r job_name job_status job_number; do
      [[ "$job_status" != "failed" ]] && continue
      any_failed=1
      if [[ "$no_logs" -eq 0 ]]; then
        printf '=== %s / %s (build #%s) ===\n\n' "$wf_name" "$job_name" "$job_number"
        local log_flags=()
        [[ "$clean" -eq 0 ]]    && log_flags+=(--no-clean)
        [[ "$sanitize" -eq 0 ]] && log_flags+=(--no-sanitize)
        cci-log "${log_flags[@]}" "$slug" "$job_number"
        printf '\n'
      else
        printf '  failed  %s / %s (build #%s)\n' "$wf_name" "$job_name" "$job_number"
      fi
    done < <(cci-curl "v2/workflow/${wf_id}/job" 2>/dev/null \
      | jq -r '.items[] | "\(.name)\t\(.status)\t\(.job_number)"')
  done < <(printf '%s' "$workflows_final" | jq -r '.[] | "\(.id)\t\(.name)\t\(.status)"')

  return "$any_failed"
}

# Show the latest pipeline and workflow statuses for the current git branch.
# Infers the project slug from the git remote URL and the branch from git.
# Usage: cci-current
cci-current() {
  local remote_url branch slug org repo pipeline_id
  remote_url=$(git remote get-url origin 2>/dev/null)
  if [[ -z "$remote_url" ]]; then
    printf 'cci-current: not inside a git repo with an origin remote\n' >&2
    return 1
  fi
  branch=$(git branch --show-current 2>/dev/null)
  if [[ -z "$branch" ]]; then
    printf 'cci-current: could not determine current branch\n' >&2
    return 1
  fi

  # Parse org/repo from SSH (git@host:org/repo.git) or HTTPS (https://host/org/repo.git)
  if [[ "$remote_url" =~ ^git@[^:]+:([^/]+)/(.+)\.git$ ]]; then
    org="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ ^https?://[^/]+/([^/]+)/(.+?)(.git)?$ ]]; then
    org="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  else
    printf 'cci-current: could not parse org/repo from remote URL: %s\n' "$remote_url" >&2
    return 1
  fi
  slug="github/${org}/${repo}"

  local encoded_branch
  encoded_branch="$(jq -rn --arg v "$branch" '$v | @uri')"

  printf 'Project : %s\n' "$slug"
  printf 'Branch  : %s\n' "$branch"

  pipeline_id=$(cci-curl "v2/project/${slug}/pipeline?branch=${encoded_branch}" 2>/dev/null \
    | jq -r '.items[0].id // empty')
  if [[ -z "$pipeline_id" ]]; then
    printf 'No pipelines found for this branch.\n' >&2
    return 1
  fi

  local pipeline_meta
  pipeline_meta=$(cci-curl "v2/pipeline/${pipeline_id}" 2>/dev/null \
    | jq '{number, state, created_at}')
  printf 'Pipeline: %s\n\n' "$(echo "$pipeline_meta" | jq -r '"#\(.number)  state=\(.state)  created=\(.created_at)"')"

  cci-curl "v2/pipeline/${pipeline_id}/workflow" 2>/dev/null \
  | jq -r '.items[] | "\(.status)\t\(.name)\t\(.id)"' \
  | while IFS=$'\t' read -r status name wf_id; do
      printf '  %-10s  %s\n' "$status" "$name"
    done
}
