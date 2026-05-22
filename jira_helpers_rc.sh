# shellinit:contexts=any
# shellinit:requires=api-curl
# shellinit:tools=curl,jq,python3
# ---------------------------------------------------------------------------
# Jira helpers
# All functions read $JIRA_URL, $JIRA_PERSONAL_TOKEN, $JIRA_AUTH_TYPE
#
# Chaining examples:
#   jira-query 'assignee = currentUser() AND status != Done' | jq -r '.key' | xargs -I{} jira-comments {}
#   jira-query 'assignee = currentUser()' | jq -r '.key' | xargs -I{} jira-transitions {}
#   jira-issue PROJ-469 | jq '{key, summary, status}'
#   jira-epics PROJ | jq -r '.key' | xargs -I{} jira-epic-issues {}
#   jira-boards PROJ | jq -r '.id' | head -1 | xargs jira-sprints
#   jira-sprints 42 --state active | jq -r '.id' | xargs jira-sprint-issues
#   jira-attachments PROJ-42 | jq -r '.[] | .content' | xargs -I{} jira-attachment-get {}
# ---------------------------------------------------------------------------

declare -f jira-curl > /dev/null 2>&1 && return

_jira_auth_header() {
  case "${JIRA_AUTH_TYPE:-bearer}" in
    bearer) printf 'Bearer %s' "${JIRA_PERSONAL_TOKEN}" ;;
    basic)  printf 'Basic %s'  "${JIRA_PERSONAL_TOKEN}" ;;
    *)      printf 'Bearer %s' "${JIRA_PERSONAL_TOKEN}" ;;
  esac
}

# Public curl wrapper — prepends $JIRA_URL/rest/api/2/ to the first non-flag argument.
# Usage: jira-curl [curl flags...] <endpoint> [curl flags...]
# Examples:
#   jira-curl issue/PROJ-469
#   jira-curl -X POST -d '{"body":"hi"}' issue/PROJ-469/comment
#   jira-curl -G --data-urlencode 'jql=assignee=currentUser()' search
jira-curl() {
  api_curl "${JIRA_URL}/rest/api/2" "$(_jira_auth_header)" "$@"
}

jira-query() {
  local usage="Usage: jira-query <jql> [max_results]
Examples:
  jira-query 'assignee = currentUser()'
  jira-query 'assignee = currentUser() AND status != Done'
  jira-query 'project = PROJ AND status = \"In Progress\"'
  jira-query 'assignee = currentUser()' 200"

  if [[ $# -lt 1 ]]; then
    printf '%s\n' "$usage" >&2
    return 1
  fi

  local jql="$1"
  local max_results="${2:-1000}"

  if [[ -n "${JIRA_PROJECTS:-}" ]]; then
    jql="(${jql}) AND project in (${JIRA_PROJECTS})"
  fi

  jira-curl \
    search \
    -G \
    --data-urlencode "jql=${jql}" \
    --data-urlencode "maxResults=${max_results}" \
    --data-urlencode "fields=summary,status,assignee,priority,issuetype" \
  | jq '.issues[] | {
      key:      .key,
      type:     .fields.issuetype.name,
      summary:  .fields.summary,
      status:   .fields.status.name,
      priority: .fields.priority.name,
      assignee: .fields.assignee.displayName
    }'
}

# Print full detail for a single issue
# Usage: jira-issue <KEY>
# Chains: jira-issue PROJ-469 | jq '{key, summary, status}'
jira-issue() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-issue <KEY>\n' >&2
    return 1
  fi
  jira-curl "issue/$1" \
  | jq '{
      key:         .key,
      type:        .fields.issuetype.name,
      summary:     .fields.summary,
      description: .fields.description,
      status:      .fields.status.name,
      priority:    .fields.priority.name,
      assignee:    .fields.assignee.displayName,
      reporter:    .fields.reporter.displayName,
      created:     .fields.created,
      updated:     .fields.updated,
      labels:      .fields.labels,
      subtasks:    [.fields.subtasks[]? | {key: .key, summary: .fields.summary}],
      parent:      .fields.parent?.key
    }'
}

# List comments on an issue
# Usage: jira-comments <KEY>
# Chains: jira-query '...' | jq -r '.key' | xargs -I{} jira-comments {}
jira-comments() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-comments <KEY>\n' >&2
    return 1
  fi
  jira-curl "issue/$1/comment" \
  | jq '{
      key: "'"$1"'",
      comments: [.comments[] | {
        author:  .author.displayName,
        created: .created,
        body:    .body
      }]
    }'
}

# List valid transitions for an issue
# Usage: jira-transitions <KEY>
# Chains: jira-query '...' | jq -r '.key' | xargs -I{} jira-transitions {}
jira-transitions() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-transitions <KEY>\n' >&2
    return 1
  fi
  jira-curl "issue/$1/transitions" \
  | jq '{
      key: "'"$1"'",
      transitions: [.transitions[] | {id: .id, name: .name}]
    }'
}

# Transition an issue to a new status by transition name (case-insensitive substring match)
# Usage: jira-transition <KEY> <transition name>
# Example: jira-transition PROJ-469 "done"
jira-transition() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: jira-transition <KEY> <transition name>\n' >&2
    return 1
  fi
  local key="$1"
  local name="$2"
  local transition_id
  transition_id=$(
    jira-curl "issue/${key}/transitions" \
    | jq -r --arg name "$name" \
        '.transitions[] | select(.name | ascii_downcase | contains($name | ascii_downcase)) | .id' \
    | head -1
  )
  if [[ -z "$transition_id" ]]; then
    printf 'No matching transition "%s" for %s\n' "$name" "$key" >&2
    jira-transitions "$key"
    return 1
  fi
  jira-curl -X POST \
    -d "{\"transition\": {\"id\": \"${transition_id}\"}}" \
    "issue/${key}/transitions" \
  && printf '%s transitioned to "%s"\n' "$key" "$name"
}

# Add a comment to an issue
# Usage: jira-comment <KEY> <"comment text">
jira-comment() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: jira-comment <KEY> <"comment text">\n' >&2
    return 1
  fi
  local key="$1"
  local body="$2"
  jira-curl -X POST \
    -d "{\"body\": $(jq -n --arg b "$body" '$b')}" \
    "issue/${key}/comment" \
  | jq '{key: "'"$key"'", comment_id: .id, author: .author.displayName, created: .created}'
}

# Create a new issue
# Usage: jira-create <PROJECT> <TYPE> <"summary"> ["description"]
# Example: jira-create PROJ Task "Fix the thing" "More detail here"
jira-create() {
  if [[ $# -lt 3 ]]; then
    printf 'Usage: jira-create <PROJECT> <TYPE> <"summary"> ["description"]\n' >&2
    return 1
  fi
  local project="$1"
  local issuetype="$2"
  local summary="$3"
  local description="${4:-}"
  jira-curl -X POST \
    -d "$(jq -n \
      --arg proj    "$project" \
      --arg type    "$issuetype" \
      --arg summary "$summary" \
      --arg desc    "$description" \
      '{fields: {project: {key: $proj}, issuetype: {name: $type}, summary: $summary, description: $desc}}')" \
    "issue" \
  | jq '{key: .key, url: ("'"${JIRA_URL}"'/browse/" + .key)}'
}

# Public curl wrapper for the Jira Agile (Software) REST API.
# Prepends $JIRA_URL/rest/agile/1.0/ to the first non-flag argument.
# Usage: jira-agile-curl [curl flags...] <endpoint> [curl flags...]
# Examples:
#   jira-agile-curl board?projectKeyOrId=PROJ
#   jira-agile-curl board/42/sprint -G --data-urlencode 'state=active'
jira-agile-curl() {
  api_curl "${JIRA_URL}/rest/agile/1.0" "$(_jira_auth_header)" "$@"
}

# ---------------------------------------------------------------------------
# Jira — issue assignment
# ---------------------------------------------------------------------------

# Assign a user to an issue.  Pass "x" or "-" as the name to unassign.
# Username is matched via a fuzzy search; the call fails if the query is
# ambiguous (> 1 result) so that the wrong person is never silently assigned.
#
# Usage: jira-assign <KEY> <username-query | x | ->
# Examples:
#   jira-assign PROJ-42 jdoe
#   jira-assign PROJ-42 x
jira-assign() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: jira-assign <KEY> <username-query | x | ->\n' >&2
    return 1
  fi
  local key="$1"
  local query="$2"

  local name_field
  if [[ "$query" == "x" || "$query" == "-" ]]; then
    name_field='null'
  else
    local matches
    matches=$(jira-curl "user/search" -G \
      --data-urlencode "username=${query}" \
      --data-urlencode "maxResults=10" 2>/dev/null \
      | jq '[.[] | select(.active == true) | {name, displayName}]')

    local count
    count=$(printf '%s' "$matches" | jq 'length')
    if [[ "$count" -eq 0 ]]; then
      printf 'jira-assign: no active users found matching "%s"\n' "$query" >&2
      return 1
    elif [[ "$count" -gt 1 ]]; then
      printf 'jira-assign: ambiguous query "%s" — %d matches:\n' "$query" "$count" >&2
      printf '%s' "$matches" | jq -r '.[] | "  \(.name)  \(.displayName)"' >&2
      return 1
    fi
    local username
    username=$(printf '%s' "$matches" | jq -r '.[0].name')
    name_field="\"${username}\""
  fi

  jira-curl -X PUT \
    -d "{\"name\": ${name_field}}" \
    "issue/${key}/assignee" \
  && printf '%s assigned to %s\n' "$key" "$query"
}

# ---------------------------------------------------------------------------
# Jira — issue links
# ---------------------------------------------------------------------------

# List all available issue link types.
# Usage: jira-link-types
# Chains: jira-link-types | jq -r '.[] | .name'
jira-link-types() {
  jira-curl "issueLinkType" \
  | jq '[.issueLinkTypes[] | {id, name, inward, outward}]'
}

# Link two issues by link-type name (case-insensitive substring match).
# Usage: jira-link <KEY1> <KEY2> <link-type>
# Examples:
#   jira-link PROJ-1 PROJ-2 blocks
#   jira-link PROJ-1 PROJ-2 relates
jira-link() {
  if [[ $# -lt 3 ]]; then
    printf 'Usage: jira-link <KEY1> <KEY2> <link-type>\n' >&2
    return 1
  fi
  local key1="$1"
  local key2="$2"
  local type_query="$3"

  local link_name
  link_name=$(jira-curl "issueLinkType" 2>/dev/null \
    | jq -r --arg q "$type_query" \
        '.issueLinkTypes[]
         | select(.name | ascii_downcase | contains($q | ascii_downcase))
         | .name' \
    | head -1)

  if [[ -z "$link_name" ]]; then
    printf 'jira-link: no link type matching "%s"\n' "$type_query" >&2
    jira-link-types >&2
    return 1
  fi

  jira-curl -X POST \
    -d "$(jq -n \
      --arg type "$link_name" \
      --arg out  "$key1" \
      --arg in   "$key2" \
      '{type: {name: $type}, outwardIssue: {key: $out}, inwardIssue: {key: $in}}')" \
    "issueLink" \
  && printf '%s -[%s]-> %s\n' "$key1" "$link_name" "$key2"
}

# Remove the link between two issues.
# Usage: jira-unlink <KEY1> <KEY2>
jira-unlink() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: jira-unlink <KEY1> <KEY2>\n' >&2
    return 1
  fi
  local key1="$1"
  local key2="$2"

  local link_id
  link_id=$(jira-curl "issue/${key1}?fields=issuelinks" 2>/dev/null \
    | jq -r --arg k "$key2" \
        '.fields.issuelinks[]
         | select(
             (.inwardIssue?.key  == $k) or
             (.outwardIssue?.key == $k)
           )
         | .id' \
    | head -1)

  if [[ -z "$link_id" ]]; then
    printf 'jira-unlink: no link found between %s and %s\n' "$key1" "$key2" >&2
    return 1
  fi

  jira-curl -X DELETE "issueLink/${link_id}" \
  && printf 'Unlinked %s <-> %s (link id %s)\n' "$key1" "$key2" "$link_id"
}

# ---------------------------------------------------------------------------
# Jira — epics  (classic projects: Epic Link = customfield_10100)
# ---------------------------------------------------------------------------

# List epics in a project (or $JIRA_PROJECTS if no project given).
# Usage: jira-epics [project-key]
# Chains: jira-epics PROJ | jq -r '.key'
jira-epics() {
  local project="${1:-}"
  local jql='issuetype = Epic'

  if [[ -n "$project" ]]; then
    jql="${jql} AND project = ${project}"
  elif [[ -n "${JIRA_PROJECTS:-}" ]]; then
    jql="${jql} AND project in (${JIRA_PROJECTS})"
  fi

  jira-curl \
    search \
    -G \
    --data-urlencode "jql=${jql}" \
    --data-urlencode "maxResults=1000" \
    --data-urlencode "fields=summary,status,assignee,customfield_10102" \
  | jq '.issues[] | {
      key:        .key,
      epic_name:  .fields.customfield_10102,
      summary:    .fields.summary,
      status:     .fields.status.name,
      assignee:   .fields.assignee?.displayName
    }'
}

# List issues belonging to an epic (classic Epic Link field).
# Usage: jira-epic-issues <EPIC-KEY>
# Chains: jira-epic-issues PROJ-100 | jq -r '.key'
jira-epic-issues() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-epic-issues <EPIC-KEY>\n' >&2
    return 1
  fi
  jira-curl \
    search \
    -G \
    --data-urlencode "jql=\"Epic Link\" = $1" \
    --data-urlencode "maxResults=1000" \
    --data-urlencode "fields=summary,status,assignee,priority,issuetype" \
  | jq '.issues[] | {
      key:      .key,
      type:     .fields.issuetype.name,
      summary:  .fields.summary,
      status:   .fields.status.name,
      priority: .fields.priority.name,
      assignee: .fields.assignee?.displayName
    }'
}

# Set the epic for one or more issues (classic customfield_10100).
# Usage: jira-epic-set <EPIC-KEY> <ISSUE-KEY> [<ISSUE-KEY>...]
# Example: jira-epic-set PROJ-100 PROJ-200 PROJ-201
jira-epic-set() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: jira-epic-set <EPIC-KEY> <ISSUE-KEY> [<ISSUE-KEY>...]\n' >&2
    return 1
  fi
  local epic_key="$1"
  shift
  local issues=("$@")

  # Fire all PUT requests in parallel using background jobs, then wait.
  local pids=()
  local keys=()
  local tmpdir
  tmpdir=$(mktemp -d)

  local issue_key
  for issue_key in "${issues[@]}"; do
    (
      jira-curl -X PUT \
        -d "$(jq -n --arg e "$epic_key" '{fields: {customfield_10100: $e}}')" \
        "issue/${issue_key}" > /dev/null 2>&1
      printf '%s\n' "$issue_key" > "${tmpdir}/${issue_key}.ok"
    ) &
    pids+=($!)
    keys+=("$issue_key")
  done

  local i
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
      printf '%s -> epic %s\n' "${keys[$i]}" "$epic_key"
    else
      printf 'jira-epic-set: failed to update %s\n' "${keys[$i]}" >&2
    fi
  done
  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Jira — projects listing
# ---------------------------------------------------------------------------

# List all accessible projects.
# Usage: jira-projects
# Chains: jira-projects | jq -r 'select(.type=="software") | .key'
jira-projects() {
  jira-curl "project" \
  | jq '.[] | {
      key:  .key,
      name: .name,
      type: .projectTypeKey,
      lead: .lead?.displayName
    }'
}

# ---------------------------------------------------------------------------
# Jira — boards, sprints
# ---------------------------------------------------------------------------

# List boards, optionally filtered by project key.
# Respects $JIRA_PROJECTS (comma-separated) when no argument is given —
# each project is queried in parallel and results are merged.
# Usage: jira-boards [project-key]
# Chains: jira-boards PROJ | jq -r '.id'
jira-boards() {
  local project="${1:-}"

  # Collect the list of project keys to query.
  local -a projects=()
  if [[ -n "$project" ]]; then
    projects=("$project")
  elif [[ -n "${JIRA_PROJECTS:-}" ]]; then
    IFS=',' read -ra projects <<< "${JIRA_PROJECTS}"
  fi

  if [[ "${#projects[@]}" -eq 0 ]]; then
    # No filter — return everything (may be large).
    jira-agile-curl "board" -G --data-urlencode "maxResults=1000" 2>/dev/null \
    | jq '.values[] | {id, name, type}'
    return
  fi

  # Parallel fetch — one background job per project.
  local tmpdir
  tmpdir=$(mktemp -d)
  local pids=()
  local proj
  for proj in "${projects[@]}"; do
    proj="${proj// /}"   # strip any spaces from CSV
    (
      jira-agile-curl "board" \
        -G \
        --data-urlencode "projectKeyOrId=${proj}" \
        --data-urlencode "maxResults=1000" 2>/dev/null \
      | jq '.values // []' > "${tmpdir}/${proj}.json"
    ) &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid"; done

  # Merge, deduplicate by id, emit one object per line.
  jq -s '[.[][] ] | unique_by(.id) | .[] | {id, name, type}' "${tmpdir}"/*.json
  rm -rf "$tmpdir"
}

# List sprints for a board.
# Usage: jira-sprints <board-id> [--state active|future|closed|all]
# Default state: active,future
# Chains: jira-sprints 42 --state active | jq -r '.id'
jira-sprints() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-sprints <board-id> [--state active|future|closed|all]\n' >&2
    return 1
  fi
  local board_id="$1"
  local state="active,future"

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state) state="$2"; shift 2 ;;
      *) printf 'jira-sprints: unknown option "%s"\n' "$1" >&2; return 1 ;;
    esac
  done

  # "all" means don't filter by state — omit the param entirely.
  local state_args=()
  if [[ "$state" != "all" ]]; then
    state_args=(--data-urlencode "state=${state}")
  fi

  jira-agile-curl "board/${board_id}/sprint" \
    -G \
    --data-urlencode "maxResults=1000" \
    "${state_args[@]}" 2>/dev/null \
  | jq '.values[] | {id, name, state, startDate, endDate}'
}

# List issues in a sprint.
# Usage: jira-sprint-issues <sprint-id>
# Chains: jira-sprint-issues 24836 | jq -r '.key'
jira-sprint-issues() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-sprint-issues <sprint-id>\n' >&2
    return 1
  fi
  jira-agile-curl "sprint/$1/issue" \
    -G \
    --data-urlencode "maxResults=1000" \
    --data-urlencode "fields=summary,status,assignee,priority,issuetype" \
    2>/dev/null \
  | jq '.issues[] | {
      key:      .key,
      type:     .fields.issuetype.name,
      summary:  .fields.summary,
      status:   .fields.status.name,
      priority: .fields.priority?.name,
      assignee: .fields.assignee?.displayName
    }'
}

# Add one or more issues to a sprint.
# Usage: jira-sprint-add <sprint-id> <ISSUE-KEY> [<ISSUE-KEY>...]
# Example: jira-sprint-add 42 PROJ-200 PROJ-201
jira-sprint-add() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: jira-sprint-add <sprint-id> <ISSUE-KEY> [<ISSUE-KEY>...]\n' >&2
    return 1
  fi
  local sprint_id="$1"
  shift
  local issues_json
  issues_json=$(jq -n --args '{"issues": $ARGS.positional}' -- "$@")

  jira-agile-curl -X POST \
    -d "$issues_json" \
    "sprint/${sprint_id}/issue" 2>/dev/null \
  && printf 'Added %d issue(s) to sprint %s\n' "$#" "$sprint_id"
}

# ---------------------------------------------------------------------------
# Jira — versions (releases)
# ---------------------------------------------------------------------------

# List versions for a project.
# Usage: jira-versions <project-key>
# Chains: jira-versions PROJ | jq -r 'select(.released==false) | .name'
jira-versions() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-versions <project-key>\n' >&2
    return 1
  fi
  jira-curl "project/$1/versions" \
  | jq '.[] | {id, name, released, releaseDate, archived}'
}

# Create a new version (release) in a project.
# Usage: jira-version-create <project-key> <name> [release-date YYYY-MM-DD]
# Example: jira-version-create PROJ "2026 Q3" 2026-09-30
jira-version-create() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: jira-version-create <project-key> <name> [release-date YYYY-MM-DD]\n' >&2
    return 1
  fi
  local project="$1"
  local name="$2"
  local release_date="${3:-}"

  local payload
  payload=$(jq -n \
    --arg proj "$project" \
    --arg name "$name" \
    --arg date "$release_date" \
    '{
      project:     $proj,
      name:        $name,
      releaseDate: (if $date != "" then $date else null end)
    }')

  jira-curl -X POST -d "$payload" "version" \
  | jq '{id, name, releaseDate, url: ("'"${JIRA_URL}"'/projects/'"'"' + .projectId + '"'"'/versions/" + .id)}'
}

# Mark a version as released (sets released=true and releaseDate to today if unset).
# Usage: jira-version-release <version-id>
jira-version-release() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-version-release <version-id>\n' >&2
    return 1
  fi
  local today
  today=$(date -u +%Y-%m-%d)
  jira-curl -X PUT \
    -d "$(jq -n --arg d "$today" '{released: true, releaseDate: $d}')" \
    "version/$1" \
  | jq '{id, name, released, releaseDate}'
}

# ---------------------------------------------------------------------------
# Jira — attachments
# ---------------------------------------------------------------------------

# List attachments on an issue.
# Usage: jira-attachments <KEY>
# Chains: jira-attachments PROJ-42 | jq -r '.[] | .content'
jira-attachments() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-attachments <KEY>\n' >&2
    return 1
  fi
  jira-curl "issue/$1?fields=attachment" \
  | jq '[.fields.attachment[] | {
      id,
      filename,
      size,
      mimeType,
      author:  .author.displayName,
      created,
      content
    }]'
}

# Upload a local file as an attachment to an issue.
# Usage: jira-attach <KEY> <file-path>
# Example: jira-attach PROJ-42 /tmp/report.pdf
jira-attach() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: jira-attach <KEY> <file-path>\n' >&2
    return 1
  fi
  local key="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    printf 'jira-attach: file not found: %s\n' "$file" >&2
    return 1
  fi
  curl -s \
    -H "Authorization: $(_jira_auth_header)" \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@${file}" \
    "${JIRA_URL}/rest/api/2/issue/${key}/attachments" \
  | jq '[.[] | {id, filename, size, content}]'
}

# Download an attachment by its content URL (from jira-attachments) to a file.
# If no output path is given, writes to the current directory using the filename
# from the URL.
# Usage: jira-attachment-get <content-url> [output-path]
# Example: jira-attachment-get "https://jira.example.com/secure/attachment/123/report.pdf"
jira-attachment-get() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: jira-attachment-get <content-url> [output-path]\n' >&2
    return 1
  fi
  local url="$1"
  local output="${2:-${url##*/}}"
  curl -sL \
    -H "Authorization: $(_jira_auth_header)" \
    -o "$output" \
    "$url" \
  && printf 'Saved to %s\n' "$output"
}

# ---------------------------------------------------------------------------
