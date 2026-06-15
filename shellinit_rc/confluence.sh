# shellinit:contexts=any
# shellinit:requires=api-curl
# shellinit:tools=curl,jq
# ---------------------------------------------------------------------------
# Confluence helpers
# All functions read $CONFLUENCE_URL, $CONFLUENCE_PERSONAL_TOKEN
#
# Chaining examples:
#   confluence-search 'type=page AND contributor=currentUser()' | jq -r '.id' | xargs -I{} confluence-page {}
#   confluence-search 'type=page AND space=SPACE AND text~"wire"' | jq '{title, url}'
# ---------------------------------------------------------------------------

declare -f confluence-curl > /dev/null 2>&1 && return

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
  | jq '[.results[] | {
      id:        .id,
      title:     .title,
      type:      .type,
      space:     .space.key,
      version:   .version.number,
      ancestors: [.ancestors[]?.title],
      url:       ._links.webui
    }]'
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

# Get plain-text body of a page (HTML tags stripped)
# Usage: confluence-page-text <page-id>
# Chains: confluence-search '...' | jq -r '.[].id' | xargs -I{} confluence-page-text {}
confluence-page-text() {
  if [[ $# -lt 1 ]]; then
    printf 'Usage: confluence-page-text <page-id>\n' >&2
    return 1
  fi
  confluence-page "$1" | jq -r '.body | gsub("<[^>]+>"; " ") | gsub("\\s+"; " ") | ltrimstr(" ")'
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
