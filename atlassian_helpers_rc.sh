# ---------------------------------------------------------------------------
# Jira helpers
# All functions read $JIRA_URL, $JIRA_PERSONAL_TOKEN, $JIRA_AUTH_TYPE
#
# Chaining examples:
#   jira-query 'assignee = currentUser() AND status != Done' | jq -r '.key' | xargs -I{} jira-comments {}
#   jira-query 'assignee = currentUser()' | jq -r '.key' | xargs -I{} jira-transitions {}
#   jira-issue ASDF-469 | jq '{key, summary, status}'
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
#   jira-curl issue/ASDF-469
#   jira-curl -X POST -d '{"body":"hi"}' issue/ASDF-469/comment
#   jira-curl -G --data-urlencode 'jql=assignee=currentUser()' search
jira-curl() {
  api_curl "${JIRA_URL}/rest/api/2" "$(_jira_auth_header)" "$@"
}

jira-query() {
  local usage="Usage: jira-query <jql> [max_results]
Examples:
  jira-query 'assignee = currentUser()'
  jira-query 'assignee = currentUser() AND status != Done'
  jira-query 'project = ASDF AND status = \"In Progress\"'
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
# Chains: jira-issue ASDF-469 | jq '{key, summary, status}'
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
# Example: jira-transition ASDF-469 "done"
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
# Example: jira-create ASDF Task "Fix the thing" "More detail here"
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

# ---------------------------------------------------------------------------
# Confluence helpers
# All functions read $CONFLUENCE_URL, $CONFLUENCE_PERSONAL_TOKEN
#
# Chaining examples:
#   confluence-search 'type=page AND contributor=currentUser()' | jq -r '.id' | xargs -I{} confluence-page {}
#   confluence-search 'type=page AND space=MRDE AND text~"wire"' | jq '{title, url}'
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
#   confluence-search 'type=page AND space=MRDE AND text~"wire detection"'
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
    endpoint="v1.1/project/${slug}/tree/${branch}"
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
# Chains: cci-builds github/imaging/repo | jq -r '.workflow_id' | sort -u | xargs -I{} cci-workflow {}
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
# Usage: cci-log <project-slug> <build-num>
# Example: cci-log github/my-org/my-repo 3001
cci-log() {
  if [[ $# -lt 2 ]]; then
    printf 'Usage: cci-log <project-slug> <build-num>\n' >&2
    return 1
  fi
  cci-curl "v1.1/project/$1/$2/output" \
  | jq -r '.[] | .output[] | .message' 2>/dev/null
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
