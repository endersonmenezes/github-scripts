#!/usr/bin/env bash

###############################################################################
# GitHub Repository Archive Status Check Tool
#
# Author: Enderson Menezes
# Created: 2025-05-06
#
# Description:
#   This script reads a list of repositories from a CSV file and checks if each
#   repository is archived using the GitHub API. The results are saved to a CSV
#   file with the format: owner,repo,is_archived (where is_archived is true/false).
#
# Input File: 23-is-archived.csv
#   Format: owner/repo (one repository per line)
#
# Output File: result.csv
#   Format: owner,repo,is_archived
#
# Usage: bash 23-is-archived.sh
###############################################################################

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit
audit_file

# Read CSV config file
read_config_file

# Configurations
API_VERSION="2022-11-28"
ACCEPT_HEADER="application/vnd.github+json"
OUTPUT_FILE="result.csv"

# Create output file and add header
echo "owner,repo,is_archived" > $OUTPUT_FILE

# Process each repository
LINE_NUMBER=0
while IFS= read -r repo_path || [ -n "$repo_path" ]; do
  # Increment line counter
  ((LINE_NUMBER++))
  
  # Skip comment lines (starts with //) and empty lines
  [[ "$repo_path" =~ ^//.*$ || -z "$repo_path" ]] && continue
  
  # Extract owner and repository name
  OWNER=$(echo $repo_path | awk -F/ '{print $1}')
  REPO=$(echo $repo_path | awk -F/ '{print $2}')
  
  # Skip if owner or repo is empty
  if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
    echo "❌ Error: Invalid repository path format at line $LINE_NUMBER: '$repo_path'"
    continue
  fi
  
  echo "Checking repository: $OWNER/$REPO"
  
  # Use GitHub API to get repository info
  REPO_INFO=$(gh api \
    -H "Accept: $ACCEPT_HEADER" \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "/repos/$OWNER/$REPO" 2>/dev/null)
  
  # Check if the API call was successful
  if [ $? -ne 0 ]; then
    echo "❌ Error: Repository $OWNER/$REPO not found or API error"
    echo "$OWNER,$REPO,false" >> $OUTPUT_FILE
    continue
  fi
  
  # Extract the archived status
  IS_ARCHIVED=$(echo $REPO_INFO | jq -r '.archived')
  
  # Add to output CSV
  echo "$OWNER,$REPO,$IS_ARCHIVED" >> $OUTPUT_FILE
  
  echo "✅ Repository $OWNER/$REPO is archived: $IS_ARCHIVED"
done < $FILE

echo "Process completed! Results are available in $OUTPUT_FILE"
