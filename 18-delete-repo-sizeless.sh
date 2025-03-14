#!/usr/bin/env bash

###############################################################################
# GitHub Small Repository Deletion Tool
#
# Author: Enderson Menezes
# Created: 2024-03-08
# Updated: 2025-03-14
#
# Description:
#   This script identifies and deletes small GitHub repositories that are less
#   than 1MB in size. It first verifies repository size via the GitHub API and
#   only proceeds with deletion if the size is below the threshold. This helps
#   clean up empty or nearly empty repositories.
#
# Input File Format (18-delete-repo-sizeless.csv):
#   owner/repo
#
# Usage: bash 18-delete-repo-sizeless.sh
###############################################################################

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 varible)
audit_file

# Read CSV config file (Define FILE variable)
read_config_file

# Configurations
API_VERSION="2022-11-28"
ACCEPT_HEADER="application/vnd.github+json"

# Function to delete the repository
function delete_repo() {
  local owner=$1
  local repo=$2
  
  echo "Deleting repository $owner/$repo..."
  gh repo delete $owner/$repo --yes
  echo "Repository $owner/$repo has been deleted"
}

function show_separator() {
  echo "----------------------------------------"
}

###############################################################################
# MAIN PROGRAM
###############################################################################

# Process each repository
for repo_path in $(cat $FILE | grep -v '^#' | grep -v '^$' | awk -F, '{print $1}'); do
  # Extract owner and repository name
  OWNER=$(echo $repo_path | awk -F/ '{print $1}')
  REPO=$(echo $repo_path | awk -F/ '{print $2}')
  echo "Processing repository: $OWNER/$REPO"

  # Check if repository size is less than 1MB
  SIZE=$(gh api \
      -H "Accept: $ACCEPT_HEADER" \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "/repos/$OWNER/$REPO" | jq -r '.size')
  
  if [ $SIZE -gt 1 ]; then
    echo "Repository $OWNER/$REPO is larger than 1MB (size: $SIZE KB)"
    continue
  fi

  # Delete the repository if smaller than 1MB
  delete_repo $OWNER $REPO
  
  # Show separator
  show_separator
done

echo "Process completed!"