#!/usr/bin/env bash

###############################################################################
# GitHub Repository Information Collector
#
# Author: Enderson Menezes
# Created: 2025-03-15
#
# Description:
#   This script collects comprehensive information about GitHub repositories,
#   including team access, branch protection rules, webhooks, and deployment
#   environments. The collected data is stored in JSON format for analysis
#   and documentation purposes.
#
# Usage: bash 19-collect-repo-info.sh <organization> <repository>
#
# Parameters:
#   - organization: GitHub organization name
#   - repository: Repository name (without organization prefix)
#
# Outputs:
#   - Multiple JSON files with different aspects of repository configuration
###############################################################################

# Args
ORGANIZATION=$1
REPOSITORY=$2

# Validate parameters
if [ -z "$ORGANIZATION" ] || [ -z "$REPOSITORY" ]; then
  echo "Usage: $0 <organization> <repository>"
  exit 1
fi

# Prepare output directory
DATE=$(date '+%Y%m%d')
OUTPUT_DIR="${DATE}_${ORGANIZATION}_${REPOSITORY}"
mkdir -p "$OUTPUT_DIR"

# Get repository information
echo "Collecting repository information for $ORGANIZATION/$REPOSITORY"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$ORGANIZATION/$REPOSITORY" > "$OUTPUT_DIR/repo_info.json"

# Get repository teams
echo "Collecting team information"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$ORGANIZATION/$REPOSITORY/teams" > "$OUTPUT_DIR/teams.json"

# Get branch protection
echo "Collecting branch protection rules"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$ORGANIZATION/$REPOSITORY/branches" > "$OUTPUT_DIR/branches.json"

# Get default branch from repo_info.json
DEFAULT_BRANCH=$(jq -r .default_branch "$OUTPUT_DIR/repo_info.json")

echo "Default branch: $DEFAULT_BRANCH"

# Get branch protection for default branch
echo "Collecting branch protection for $DEFAULT_BRANCH"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$ORGANIZATION/$REPOSITORY/branches/$DEFAULT_BRANCH/protection" > "$OUTPUT_DIR/branch_protection_${DEFAULT_BRANCH}.json" || echo "No branch protection for $DEFAULT_BRANCH"

# Get webhooks
echo "Collecting webhook configurations"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$ORGANIZATION/$REPOSITORY/hooks" > "$OUTPUT_DIR/webhooks.json"

# Get environments
echo "Collecting deployment environments"
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$ORGANIZATION/$REPOSITORY/environments" > "$OUTPUT_DIR/environments.json" || echo "No environments found"

echo "Collection complete. Data saved in directory: $OUTPUT_DIR"
echo "Available files:"
ls -la "$OUTPUT_DIR"