#!/usr/bin/env bash

###############################################################################
# GitHub Repository Search Tool
#
# Author: Enderson Menezes
# Created: 2025-02-07
# Updated: 2025-03-14
#
# Description:
#   This script searches GitHub repositories using the GitHub API search functionality.
#   It also enhances the search results by retrieving additional information about
#   team ownership for each repository found. The results are saved as both JSON
#   and CSV formats for further analysis.
#
# Usage: bash 16-query-github-repos.sh "QUERY"
#
# Parameters:
#   - QUERY: Search query for finding repositories (required)
#
# Outputs:
#   - 16-query-github-repos.json: Raw search results with added repository_owner field
#   - 16-query-github-repos.csv: CSV formatted results for easy analysis
###############################################################################

QUERY="$1"
# Validate parameters
if [[ -z "$QUERY" ]]; then
  echo "Query is required"
  exit 1
fi

PARSED_QUERY=$(echo $QUERY | sed 's/ /+/g')

# https://docs.github.com/en/rest/search/search?apiVersion=2022-11-28#search-repositories
URL="/search/repositories?q=$PARSED_QUERY"
echo "Consulting GitHub API: $URL"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$URL" --paginate > 16-query-github-repos.json

# Check if have team with "Repository owner" permission and updated that JSON with key "repository_owner" with value of all teams comma separated
# API to Check Owner: https://docs.github.com/en/rest/repos/repos?apiVersion=2022-11-28#list-repository-teams
# gh api \
#   -H "Accept: application/vnd.github+json" \
#   -H "X-GitHub-Api-Version: 2022-11-28" \
#   /repos/OWNER/REPO/teams
REPOS_TO_CHECK=$(jq -r '.items[] | .full_name' 16-query-github-repos.json)
for REPO in $REPOS_TO_CHECK; do
  OWNER=$(echo $REPO | cut -d'/' -f1)
  REPO_NAME=$(echo $REPO | cut -d'/' -f2)
  echo "Consulting GitHub API: /repos/$OWNER/$REPO_NAME/teams"
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/$OWNER/$REPO_NAME/teams > 16-query-github-repos-teams.json
  TEAM_PERMISSION=$(jq -r '.[] | select(.permission == "Repository owner")' 16-query-github-repos-teams.json)
  if [ -n "$TEAM_PERMISSION" ]; then
    echo "Repository $REPO_NAME has teams with 'Repository owner' permission"
    TEAMS=$(echo $TEAM_PERMISSION | jq -r '.name' | tr '\n' ',' | sed 's/,$//')
    echo "Teams: $TEAMS"
    jq --arg TEAMS "$TEAMS" --arg REPO "$REPO" '.items = (.items | map(if .full_name == $REPO then . + {"repository_owner": $TEAMS} else . end))' 16-query-github-repos.json > 16-query-github-repos.tmp.json
    mv 16-query-github-repos.tmp.json 16-query-github-repos.json
  else
    echo "Repository $REPO_NAME doesn't have teams with 'Repository owner' permission"
    jq --arg REPO "$REPO" '.items = (.items | map(if .full_name == $REPO then . + {"repository_owner": "Não encontrado"} else . end))' 16-query-github-repos.json > 16-query-github-repos.tmp.json
    mv 16-query-github-repos.tmp.json 16-query-github-repos.json
  fi
done

# Create CSV from .[]items
jq -r '.items[] | [.full_name, .html_url, .created_at, .updated_at, .pushed_at, .size, .archived, .repository_owner] | @csv' 16-query-github-repos.json > 16-query-github-repos.csv

# Insert header
sed -i '1s/^/full_name,html_url,created_at,updated_at,pushed_at,size,archived,repository_owner\n/' 16-query-github-repos.csv

echo "Search completed. Results available in:"
echo "- 16-query-github-repos.json (raw data with repository owner details)"
echo "- 16-query-github-repos.csv (formatted data for analysis)"