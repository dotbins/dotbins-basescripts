#!/usr/bin/env bash
# Download the latest release binaries of every public repo in a GitHub org.
# Usage: fetch_dotbins.sh [org] [dest_dir]
# Requires: curl, jq. No token needed (public org); set GITHUB_TOKEN only if you hit the
# 60 requests/hour unauthenticated API limit.
set -euo pipefail

org="${1:-dotbins-term}"
dest="${2:-$HOME/.local/bin}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/dotbins/$org"   # remembers installed tag per repo
api="https://api.github.com"

mkdir -p "$dest" "$state"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gh() {
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "$@"
}

# list all repo names (paginated, 100 per page)
list_repos() {
    local page=1 names
    while :; do
        names=$(gh "$api/orgs/$org/repos?type=public&per_page=100&page=$page" | jq -r '.[].name')
        [[ -n "$names" ]] || break
        echo "$names"
        ((page++))
    done
}

while read -r repo; do
    rel=$(gh "$api/repos/$org/$repo/releases/latest" 2>/dev/null) || {
        echo "skip  $repo (no release)" >&2
        continue
    }
    tag=$(jq -r .tag_name <<< "$rel")

    if [[ -f "$state/$repo" && "$(<"$state/$repo")" == "$tag" ]]; then
        echo "ok    $repo ($tag)"
        continue
    fi

    n=0
    while IFS=$'\t' read -r name url; do
        gh -o "$tmp/$name" "$url"
        install -m 755 "$tmp/$name" "$dest/$name"   # install replaces the file atomically enough, even if it's running
        echo "new   $repo $tag -> $dest/$name"
        ((n++)) || true
    done < <(jq -r '.assets[] | [.name, .browser_download_url] | @tsv' <<< "$rel")

    if ((n > 0)); then
        echo "$tag" > "$state/$repo"
    else
        echo "skip  $repo ($tag has no assets)" >&2
    fi
done < <(list_repos)
