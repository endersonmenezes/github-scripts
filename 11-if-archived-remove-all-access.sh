#!/usr/bin/env bash

###############################################################################
# GitHub Archived Repository Access Cleanup
#
# Author: Enderson Menezes
# Created: 2024-07-23
# Updated: 2025-03-14
#
# Description:
#   This script removes all team and direct collaborator access from archived
#   repositories within a given organization. This helps maintain security
#   and access control by ensuring that archived repositories don't have
#   unnecessary access permissions.
#
# Usage: bash 11-if-archived-remove-all-access.sh <organization>
#
# Parameters:
#   - organization: GitHub organization name
###############################################################################

organization=$1
if [ -z $organization ]; then
  echo "Please provide the organization name"
  exit 1
fi

# List all repositories in an organization
echo "Listing all repositories in organization: $organization"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/orgs/${organization}/repos" \
  --paginate > "repos_${organization}.json"

# Filter only the archived repositories
echo "Filtering archived repositories"
jq -r '.[] | select(.archived == true) | .name' "repos_${organization}.json" > "archived_repos_${organization}.txt"

for repository in $(cat "archived_repos_${organization}.txt"); do
  echo "Removing access from ${organization}/${repository}"
  
  # Get all teams collaborators
  echo "  Getting team collaborators"
  gh api "/repos/${organization}/${repository}/teams" > "teams_${organization}_${repository}.json"
  for team in $(jq -r '.[].slug' "teams_${organization}_${repository}.json"); do
    echo "- Removing access from team: ${team}"
    gh api \
      --method DELETE \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "/orgs/${organization}/teams/${team}/repos/${organization}/${repository}" > /dev/null
  done

  # Get all direct collaborators
  echo "  Getting direct collaborators"
  gh api "/repos/${organization}/${repository}/collaborators?affiliation=direct" --paginate > collaborators_${organization}_${repository}.json
  for collaborator in $(jq -r '.[].login' collaborators_${organization}_${repository}.json); do
    echo "- Removing access from collaborator: ${collaborator}"
    gh api \
      --method DELETE \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "/repos/${organization}/${repository}/collaborators/${collaborator}" > /dev/null
  done

done