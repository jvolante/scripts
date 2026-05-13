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
# Confluence helpers
# All functions read $CONFLUENCE_URL, $CONFLUENCE_PERSONAL_TOKEN
#
# Chaining examples:
#   confluence-search 'type=page AND contributor=currentUser()' | jq -r '.id' | xargs -I{} confluence-page {}
#   confluence-search 'type=page AND space=SPACE AND text~"wire"' | jq '{title, url}'
# ---------------------------------------------------------------------------

# Public curl wrapper — prepends $CONFLUENCE_URL/rest/api/ to the first non-flag argument.
# Usage: confluence-curl [curl flags...] <endpoint> [curl flags...]
# Examples:
#   confluence-curl "content/12345?expand=body.storage"
#   confluence-curl -X POST -d '<json>' content
#   confluence-curl content/search -G --data-urlencode 'cql=type=page'
confluence-curl() {
  api_curl "${CONFLUENCE_URL}/rest/api" "Bearer ${CONFLUENCE_PERSONAL_TOKEN}" "$@"
}

# Search pages/content using CQL
# Usage: confluence-search '<cql>' [max_results]
# Examples:
#   confluence-search 'type=page AND contributor=currentUser()'
#   confluence-search 'type=page AND space=SPACE AND text~"wire detection"'
confluence-search() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: confluence-search <cql> [max_results]\n' >&2
    return 1
  fi
  local cql="$1"
  local limit="${2:-1000}"

  if [[ -n "${CONFLUENCE_SPACES:-}" ]]; then
    cql="(${cql}) AND space in (${CONFLUENCE_SPACES})"
  fi

  confluence-curl "content/search" \
    -G \
    --data-urlencode "cql=${cql}" \
    --data-urlencode "limit=${limit}" \
    --data-urlencode "expand=space,version,ancestors" \
  | jq '.results[] | {
      id:        .id,
      title:     .title,
      type:      .type,
      space:     .space.key,
      version:   .version.number,
      ancestors: [.ancestors[]?.title],
      url:       ._links.webui
    }'
}

# Get full content of a page including body
# Usage: confluence-page <page-id>
# Chains: confluence-search '...' | jq -r '.id' | xargs -I{} confluence-page {}
confluence-page() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: confluence-page <page-id>\n' >&2
    return 1
  fi
  confluence-curl "content/$1?expand=body.storage,space,version,ancestors" \
  | jq '{
      id:        .id,
      title:     .title,
      space:     .space.key,
      version:   .version.number,
      ancestors: [.ancestors[]?.title],
      url:       ._links.webui,
      body:      .body.storage.value
    }'
}

# Get comments on a page
# Usage: confluence-comments <page-id>
confluence-comments() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: confluence-comments <page-id>\n' >&2
    return 1
  fi
  confluence-curl "content/$1/child/comment?expand=body.storage,version" \
  | jq '{
      page_id: "'"$1"'",
      comments: [.results[] | {
        id:      .id,
        author:  .version.by.displayName,
        created: .version.when,
        body:    .body.storage.value
      }]
    }'
}

# Add a comment to a page
# Usage: confluence-comment <page-id> "<text>"
confluence-comment() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: confluence-comment <page-id> "<text>"\n' >&2
    return 1
  fi
  local page_id="$1"
  local body="$2"
  confluence-curl "content" \
    -X POST \
    -d "$(jq -n \
      --arg page_id "$page_id" \
      --arg body    "$body" \
      '{type: "comment", container: {id: $page_id, type: "page"}, body: {storage: {value: $body, representation: "wiki"}}}')" \
  | jq '{id: .id, url: ._links.webui}'
}

# Create a new page
# Usage: confluence-create <SPACE> "<title>" "<body>" [parent-page-id]
confluence-create() {
  if [[ $# -lt 3 ]]; then
    printf 'Usage: confluence-create <SPACE> "<title>" "<body>" [parent-page-id]\n' >&2
    return 1
  fi
  local space="$1"
  local title="$2"
  local body="$3"
  local parent_id="${4:-}"

  local payload
  if [[ -n "$parent_id" ]]; then
    payload=$(jq -n \
      --arg space  "$space" \
      --arg title  "$title" \
      --arg body   "$body" \
      --arg parent "$parent_id" \
      '{type: "page", title: $title, space: {key: $space}, ancestors: [{id: $parent}], body: {storage: {value: $body, representation: "storage"}}}')
  else
    payload=$(jq -n \
      --arg space "$space" \
      --arg title "$title" \
      --arg body  "$body" \
      '{type: "page", title: $title, space: {key: $space}, body: {storage: {value: $body, representation: "storage"}}}')
  fi

  confluence-curl "content" -X POST -d "$payload" \
  | jq '{id: .id, title: .title, url: ._links.webui}'
}

# Update an existing page — fetches current version automatically
# Usage: confluence-update <page-id> "<title>" "<body>"
# Body should be Confluence storage format (HTML subset)
# Example: confluence-update 12345 "My Page" "<h1>New content</h1><p>Updated.</p>"
confluence-update() {
  if [[ $# -lt 3 ]]; then
    printf 'Usage: confluence-update <page-id> "<title>" "<body>"\n' >&2
    return 1
  fi
  local page_id="$1"
  local title="$2"
  local body="$3"

  local current_version
  current_version=$(confluence-curl "content/${page_id}?expand=version" | jq -r '.version.number')
  if [[ -z "$current_version" || "$current_version" == "null" ]]; then
    printf 'confluence-update: could not fetch version for page %s\n' "$page_id" >&2
    return 1
  fi

  local next_version=$(( current_version + 1 ))

  confluence-curl -X PUT \
    -d "$(jq -n \
      --arg title "$title" \
      --arg body  "$body" \
      --argjson v "$next_version" \
      '{version: {number: $v}, title: $title, type: "page", body: {storage: {value: $body, representation: "storage"}}}')" \
    "content/${page_id}" \
  | jq '{id: .id, title: .title, version: .version.number, url: ._links.webui}'
}

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
    encoded_branch="$(printf '%s' "$branch" | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))')"
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

# Get build log output for a single job
# Get build log output for a single job.
# Falls back to fetching presigned output URLs from the v1.1 job detail when
# the direct /output endpoint returns a non-JSON 404 (common on self-hosted CCI).
# Usage: cci-log <project-slug> <build-num>
# Example: cci-log github/my-org/my-repo 3001
cci-log() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: cci-log <project-slug> <build-num>\n' >&2
    return 1
  fi
  local slug="$1"
  local build_num="$2"

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

# Fetch logs for the most recently failed job on the current branch (or a given slug+branch).
# Infers the project slug and branch from git when not provided.
# Usage: cci-failed-logs [project-slug [branch]]
# Examples:
#   cci-failed-logs
#   cci-failed-logs github/my-org/my-repo
#   cci-failed-logs github/my-org/my-repo feature/my-branch
cci-failed-logs() {
  local slug branch org repo remote_url

  if [[ $# -ge 1 ]]; then
    slug="$1"
    branch="${2:-}"
  else
    remote_url=$(git remote get-url origin 2>/dev/null)
    if [[ -z "$remote_url" ]]; then
      printf 'cci-failed-logs: not inside a git repo with an origin remote\n' >&2
      return 1
    fi
    if [[ "$remote_url" =~ ^git@[^:]+:([^/]+)/(.+)\.git$ ]]; then
      org="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]}"
    elif [[ "$remote_url" =~ ^https?://[^/]+/([^/]+)/(.+?)(.git)?$ ]]; then
      org="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]}"
    else
      printf 'cci-failed-logs: could not parse org/repo from remote URL: %s\n' "$remote_url" >&2
      return 1
    fi
    slug="github/${org}/${repo}"
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

  cci-log "$slug" "$build_num"
}

# Wait for all CI jobs on the current branch's remote HEAD to finish, then print a summary.
# If any jobs failed, prints their logs automatically. Exits non-zero if any job failed.
#
# Only watches pipelines whose revision matches the current remote tracking SHA, so a
# stale in-progress pipeline from a previous push is ignored.
#
# Usage: cci-wait-on-jobs [project-slug [branch]] [--interval <seconds>] [--timeout <seconds>] [--progress] [--no-logs]
# Options:
#   --interval <seconds>  Poll interval (default: 30)
#   --timeout  <seconds>  Give up after this many seconds (default: 36000)
#   --progress            Print a live job-status table on each poll cycle
#   --no-logs             On failure, print only pass/fail/cancel status; skip build log output
# Examples:
#   cci-wait-on-jobs
#   cci-wait-on-jobs --progress
#   cci-wait-on-jobs --no-logs
#   cci-wait-on-jobs github/my-org/my-repo feature/my-branch --interval 15 --progress
cci-wait-on-jobs() {
  local slug branch org repo remote_url
  local interval=30 timeout=36000 progress=0 no_logs=0

  # --- parse args (positional slug/branch first, then flags) ------------------
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="$2"; shift 2 ;;
      --timeout)  timeout="$2";  shift 2 ;;
      --progress) progress=1;    shift   ;;
      --no-logs)  no_logs=1;     shift   ;;
      *)          positional+=("$1"); shift ;;
    esac
  done

  if [[ ${#positional[@]} -ge 1 ]]; then
    slug="${positional[0]}"
    branch="${positional[1]:-}"
  else
    remote_url=$(git remote get-url origin 2>/dev/null)
    if [[ -z "$remote_url" ]]; then
      printf 'cci-wait-on-jobs: not inside a git repo with an origin remote\n' >&2
      return 1
    fi
    if [[ "$remote_url" =~ ^git@[^:]+:([^/]+)/(.+)\.git$ ]]; then
      org="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
    elif [[ "$remote_url" =~ ^https?://[^/]+/([^/]+)/(.+?)(.git)?$ ]]; then
      org="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
    else
      printf 'cci-wait-on-jobs: could not parse org/repo from remote URL: %s\n' "$remote_url" >&2
      return 1
    fi
    slug="github/${org}/${repo}"
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
  encoded_branch="$(printf '%s' "$branch" | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))')"

  # --- find the pipeline for the current remote SHA ---------------------------
  local pipeline_id pipeline_num
  printf 'Waiting for CI on %s @ %s...\n' "$branch" "${remote_sha:0:8}"

  # CCI returns pipelines newest-first; scan up to 10 to find one matching our SHA.
  local pipeline_json
  pipeline_json=$(cci-curl "v2/project/${slug}/pipeline?branch=${encoded_branch}" 2>/dev/null \
    | jq --arg sha "$remote_sha" '
        .items | map(select(.vcs.revision == $sha)) | first
        | {id, number}')
  pipeline_id=$(printf '%s' "$pipeline_json" | jq -r '.id // empty')
  pipeline_num=$(printf '%s' "$pipeline_json" | jq -r '.number // empty')

  if [[ -z "$pipeline_id" ]]; then
    printf 'cci-wait-on-jobs: no pipeline found for SHA %s on %s\n' "${remote_sha:0:8}" "$branch" >&2
    printf 'Is the push complete and has CCI picked it up yet?\n' >&2
    return 1
  fi

  printf 'Pipeline #%s (%s)\n\n' "$pipeline_num" "${pipeline_id:0:8}"

  # --- poll until all workflows are in a terminal state -----------------------
  # Workflow terminal states: success, failed, error, canceled, unauthorised
  # Note: "failing" means jobs have failed but others are still running — not terminal.
  local terminal_states='["success","failed","error","canceled","unauthorised"]'
  local elapsed=0
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
      # Header line: "[<elapsed>s]  workflow: <sym>"
      # Job lines  : "  <job>: <sym>"
      local lines_printed=0
      local wf_id wf_name wf_status
      while IFS=$'\t' read -r wf_id wf_name wf_status; do
        local wf_sym
        case "$wf_status" in
          success)                      wf_sym="✓" ;;
          failed|error|unauthorised)    wf_sym="✗" ;;
          canceled)                     wf_sym="⊘" ;;
          *)                            wf_sym="…" ;;
        esac

        printf '\r\033[K[%ds]  %s: %s\n' "$elapsed" "$wf_name" "$wf_sym"
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
            printf '\r\033[K    %-40s %s\n' "$job_name" "$job_sym"
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
        cci-log "$slug" "$job_number"
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
  encoded_branch="$(printf '%s' "$branch" | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))')"

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
