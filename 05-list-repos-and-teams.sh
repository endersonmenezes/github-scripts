#!/usr/bin/env bash

###############################################################################
# GitHub Repository and Teams Listing
#
# Author: Enderson Menezes
# Created: 2024-06-15
# Updated: 2025-03-14
#
# Description:
#   This script lists all repositories and teams from a GitHub organization
#   and saves them to CSV files for further analysis. It also identifies
#   teams with access to each repository.
#
# Usage: bash 05-list-repos-and-teams.sh <organization>
###############################################################################

organization=$1
if [ -z $organization ]; then
  echo "Please provide the organization name"
  exit 1
fi

# List all repositories in an organization
echo "Fetching all repositories for organization: $organization"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /orgs/$organization/repos \
  --paginate > repos_$organization.json

# Create CSV file: repo_name, repo_url, repo_maintainer ignore archived = true
echo "Creating CSV file with non-archived repositories"
jq -r '.[] | select(.archived == false) | [.name, .html_url, .owner.login] | @csv' repos_$organization.json > repos_$organization.csv

# List all teams
echo "Fetching all teams for organization: $organization"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /orgs/$organization/teams \
  --paginate > teams_$organization.json

# Create CSV file: team_name, team_id
echo "Creating CSV file with team information"
jq -r '.[] | [.name, .id] | @csv' teams_$organization.json > teams_$organization.csv

# Remove " from CSV files
sed -i 's/"//g' repos_$organization.csv
sed -i 's/"//g' teams_$organization.csv

# Catch all teams with access to repositories
echo "Analyzing teams with repository access"
echo "organization,repository,have_repository_owner,team_name,team_id" > teams_repos_$organization.csv

echo "Fetching teams with access to each repository"
for repository in $(jq -r '.[] | select(.archived == false) | .name' repos_$organization.json); do
  echo "Processing repository: $repository"
  # Teams with Access
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/$organization/$repository/teams > teams_access_$organization_$repository.json
done

echo "Process completed. Output files:"
echo "- repos_$organization.csv"
echo "- teams_$organization.csv"
echo "- teams_repos_$organization.csv"
