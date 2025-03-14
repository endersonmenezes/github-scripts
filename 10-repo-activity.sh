#!/usr/bin/env bash

###############################################################################
# GitHub Repository Activity Analyzer
#
# Author: Enderson Menezes
# Created: 2024-07-23
# Updated: 2025-03-14
#
# Description:
#   This script analyzes activity in GitHub repositories and generates a CSV
#   report with metrics such as days since last PR, issue, commit, and action run.
#   It focuses on repositories that have not been pushed to in over 360 days.
#
# Usage: bash 10-repo-activity.sh <organization> [debug] [random_page]
#
# Parameters:
#   - organization: GitHub organization name
#   - debug (optional): Set to "true" to enable debug mode
#   - random_page (optional): Page number to fetch when in debug mode (default: 2)
###############################################################################

organization=$1
if [ -z $organization ]; then
  echo "Please provide the organization name"
  exit 1
fi
echo "🏢 Organization: ${organization}"

debug=$2
if [ -z $debug ]; then
  debug="false"
fi
echo "🐞 Debug: ${debug}"

# List all repositories in an organization if not debug
if [ $debug == "true" ]; then
  echo "Debug mode enabled"
  RANDOM_PAGE=$3
  if [ -z $RANDOM_PAGE ]; then
    RANDOM_PAGE=2
  fi
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/orgs/$organization/repos?sort=pushed&page=$RANDOM_PAGE&direction=asc" > repos_$organization.json
else
  echo "📜 Listing all repositories in $organization"
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/orgs/$organization/repos?sort=pushed&direction=asc" \
    --paginate > repos_$organization.json
fi

# Create CSV file: repo_name, repo_url, repo_maintainer ignore archived = true
echo "Creating CSV file"
jq -r '.[] | select(.archived == false) | [.name, .html_url, .owner.login] | @csv' repos_$organization.json > repos_$organization.csv


# Verify if the repository has activity
echo "Checking activity in repositories"
echo "owner,repository,days_since_last_pr,days_since_last_issue,days_since_last_commit,days_since_last_action_run,owner_teams" > activity_$organization.csv

for repository in $(jq -r '.[] | select(.archived == false) | .name' repos_$organization.json); do
  echo "Checking $organization/$repository"
  # Date
  now=$(date +%s)

  # Open repos_$organization.json and get the pushed_at for the repository
  pushed_at=$(jq -r --arg repository "$repository" '.[] | select(.name == $repository) | .pushed_at' repos_$organization.json | xargs -I {} date -d {} +%s)
  if [ $pushed_at == "null" ]; then
    echo "No activity found for $organization/$repository"
    continue
  fi
  echo "Last Pushed: $(date -d @$pushed_at)"
  days_since_last_pushed=$(( (now - pushed_at) / 86400 ))
  if [ $days_since_last_pushed -lt 360 ]; then
    echo "Less than 360 days since last pushed. Since $days_since_last_pushed days"
    continue
  fi

  # Get the last activity
  last_pr=$(gh pr list --state all --repo $organization/$repository --json createdAt --limit 1 | jq -r '.[0].createdAt' | xargs -I {} date -d {} +%s)
  last_issue=$(gh issue --state all list --repo $organization/$repository --json createdAt --limit 1 | jq -r '.[0].createdAt' | xargs -I {} date -d {} +%s)
  last_commit=$(gh api /repos/$organization/$repository/commits | jq -r '.[0].commit.author.date' | xargs -I {} date -d {} +%s)
  last_action_run=$(gh api /repos/$organization/$repository/actions/runs | jq -r '.workflow_runs[0].created_at' | xargs -I {} date -d {} +%s)
  # Exists Team Owner?
  owner_teams=$(gh api /repos/$organization/$repository/teams --paginate | jq -r '.[].slug' | grep -E 'owner' | wc -l)


  echo "Last PR: $(date -d @$last_pr)"
  echo "Last Issue: $(date -d @$last_issue)"
  echo "Last Commit: $(date -d @$last_commit)"
  echo "Last Action Run: $(date -d @$last_action_run)"
  echo "Now: $(date -d @$now)"
  echo "Owner Teams: $owner_teams"


  # Calculate the days since the last activity
  days_since_last_pr=$(( (now - last_pr) / 86400 ))
  days_since_last_issue=$(( (now - last_issue) / 86400 ))
  days_since_last_commit=$(( (now - last_commit) / 86400 ))
  days_since_last_action_run=$(( (now - last_action_run) / 86400 ))

  # Save the activity in a CSV file
  echo "$organization,$repository,$days_since_last_pr,$days_since_last_issue,$days_since_last_commit,$days_since_last_action_run,$owner_teams" >> activity_$organization.csv
done
