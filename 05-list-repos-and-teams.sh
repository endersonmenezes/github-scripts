#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-06-15
# Description: This script 
# Usage: bash 05-list-repos-and-teams.sh <organization>
##

organization=$1
if [ -z $organization ]; then
  echo "Please provide the organization name"
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

# Remove " from CSV files
sed -i 's/"//g' repos_$organization.csv
sed -i 's/"//g' teams_$organization.csv

# Catch all teams with access to repositories
echo "organization,repository,have_repository_owner,team_name,team_id" > teams_repos_$organization.csv

for repository in $(jq -r '.[] | select(.archived == false) | .name' repos_$organization.json); do
  # Teams with Access
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/$organization/$repository/teams > teams_access_$organization_$repository.json
done
