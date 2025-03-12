#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-07-23
# Description: Remove all access from archived repositories and disable security checks.
# Usage: bash 11-if-archived-remove-all-access <organization>
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
  "/orgs/${organization}/repos" \
  --paginate > "repos_${organization}.json"

# Filter only the archived repositories
jq -r '.[] | select(.archived == true) | .name' "repos_${organization}.json" > "archived_repos_${organization}.txt"

for repository in $(cat "archived_repos_${organization}.txt"); do
  echo "Removing access from ${organization}/${repository}"
  
  # Get all teams collaborators
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