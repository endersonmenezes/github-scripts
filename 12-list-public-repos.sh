#!/usr/bin/env bash

###############################################################################
# GitHub Public Repository Lister
#
# Author: Enderson Menezes
# Created: 2024-08-06
# Updated: 2025-03-14
#
# Description:
#   This script lists all public repositories for a set of organizations and
#   generates a consolidated CSV report containing repository information
#   including organization name, repository name, and archived status.
#
# Usage: bash 12-list-public-repos.sh <organizations by comma>
#
# Parameters:
#   - organizations: Comma-separated list of GitHub organization names
###############################################################################

organizations=$1
if [ -z $organizations ]; then
  echo "Please provide the organization name"
  exit 1
fi

# Split by comma
organizations=$(echo $organizations | tr "," "\n")

# List all repositories in an organization
for organization in $organizations; do
  echo "Fetching public repositories for organization: $organization"
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /orgs/$organization/repos?type=public \
    --paginate > repos_public_$organization.json
done

# Create one CSV with all repositories
echo "Creating consolidated CSV report"
echo "organization,repository,status" > public_repos.csv
for organization in $organizations; do
  jq -r --arg org $organization '.[] | [.owner.login, .name, .archived] | @csv' repos_public_$organization.json >> public_repos.csv
done

# Remove " from CSV files
sed -i 's/"//g' repos_$organization.csv

echo "Process completed. Output saved to public_repos.csv"