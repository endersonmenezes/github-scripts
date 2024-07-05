#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-06-15
# Description: This script extracts data from a specified repository and returns a CSV with all teams.
# Usage: bash 05-list-repos-and-teams.sh <organization> <repository>
##

organization=$1
repository=$2
if [ -z $organization ] || [ -z $repository ]; then
  echo "Please provide the organization name and repository name"
  exit 1
fi

# List all repositories in an organization
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /orgs/$organization/repos \
  --paginate > repos_$organization.json

# Create CSV file: repo_name, repo_url, repo_maintainer ignore archived = true
jq -r '.[] | select(.archived == false) | [.name, .html_url, .owner.login] | @csv' repos_$organization.json > repos_$organization.csv

# List all teams
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /orgs/$organization/teams \
  --paginate > teams_$organization.json

# Create CSV file: team_name, team_id
jq -r '.[] | [.name, .id] | @csv' teams_$organization.json > teams_$organization.csv

# List teams for the specified repository
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/$organization/$repository/teams \
  --paginate > repo_teams_$repository.json

# Create combined CSV file: repo_name, repo_url, repo_maintainer, team_name, team_id
jq -r --arg repo_name "$repository" --arg repo_url "$(jq -r --arg repo_name "$repository" '.[] | select(.name == $repo_name) | .html_url' repos_$organization.json)" --arg repo_maintainer "$(jq -r --arg repo_name "$repository" '.[] | select(.name == $repo_name) | .owner.login' repos_$organization.json)" '.[] | [$repo_name, $repo_url, $repo_maintainer, .name, .id] | @csv' repo_teams_$repository.json > combined_$repository.csv
