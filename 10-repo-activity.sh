#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-07-23
# Description: This script will return a csv for activity in repositories
# Usage: bash 10-repo-activity.sh <organization>
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


# Verify if the repository has activity
echo "owner,repository,days_since_last_pr,days_since_last_issue,days_since_last_commit" > activity_$organization.csv

for repository in $(jq -r '.[] | select(.archived == false) | .name' repos_$organization.json); do
  echo "Checking $organization/$repository"
  # Get the last activity
  last_pr=$(gh pr list --state all --repo $organization/$repository --json createdAt --limit 1 | jq -r '.[0].createdAt' | xargs -I {} date -d {} +%s)
  last_issue=$(gh issue --state all list --repo $organization/$repository --json createdAt --limit 1 | jq -r '.[0].createdAt' | xargs -I {} date -d {} +%s)
  last_commit=$(gh api /repos/$organization/$repository/commits | jq -r '.[0].commit.author.date' | xargs -I {} date -d {} +%s)
  now=$(date +%s)

  echo "Last PR: $(date -d @$last_pr)"
  echo "Last Issue: $(date -d @$last_issue)"
  echo "Last Commit: $(date -d @$last_commit)"
  echo "Now: $(date -d @$now)"


  # Calculate the days since the last activity
  days_since_last_pr=$(( (now - last_pr) / 86400 ))
  days_since_last_issue=$(( (now - last_issue) / 86400 ))
  days_since_last_commit=$(( (now - last_commit) / 86400 ))

  # Save the activity in a CSV file
  echo "$organization,$repository,$days_since_last_pr,$days_since_last_issue,$days_since_last_commit" >> activity_$organization.csv
done
