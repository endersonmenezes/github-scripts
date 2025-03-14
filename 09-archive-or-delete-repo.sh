#!/usr/bin/env bash

###############################################################################
# GitHub Repository Archive or Delete Tool
#
# Author: Enderson Menezes
# Created: 2024-07-18
# Updated: 2025-03-14
#
# Description:
#   This script examines GitHub repositories and takes one of two actions:
#   1. Archives repositories that contain content
#   2. Deletes repositories that are empty
#   
#   The script also removes all team access from the repositories before
#   archiving or deleting them.
#
# Input File Format (09-archive-or-delete-repo.csv):
#   repository
#
# Usage: bash 09-archive-or-delete-repo.sh
###############################################################################

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 varible)
audit_file

## Read a CSV file (owner-repo,team,permission) (Define FILE variable)
read_config_file

# Specific Config File
if [[ $(head -n 1 $FILE) != "repository" ]]; then
    echo "The file $FILE does not have the correct format."
    exit 1
fi

# Verify last line
if [[ $(tail -n 1 $FILE) != "" ]]; then
    echo "The file $FILE does not have the correct format."
    echo "Adding a blank line at the end of the file..."
    echo "" >> $FILE
fi

# Read line by line
while IFS=, read -r REPOSITORY; do
    # Continue on first line
    [ "$REPOSITORY" == "repository" ] && continue

    # Ignore blank line
    [ -z "$REPOSITORY" ] && continue

    ORGANIZATION=$(echo $REPOSITORY | cut -d'/' -f1)
    REPOSITORY_ONLY=$(echo $REPOSITORY | cut -d'/' -f2)

    echo "Processing repository: $REPOSITORY"

    # Verify if repository have content
    REPOSITORY_CONTENT=$(gh api /repos/$REPOSITORY/contents)

    # Remove all teams with access
    gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /repos/$REPOSITORY/teams > teams.json

    jq -r '.[].slug' teams.json | while read team; do
        echo "Removing team $team from repository $REPOSITORY"
        gh api -X DELETE /orgs/$ORGANIZATION/teams/$team/repos/$REPOSITORY > /dev/null
    done

    # If "This repository is empty." then delete
    if [[ "$REPOSITORY_CONTENT" == *"This repository is empty."* ]]; then
        echo "-> Repository is empty. Deleting..."
        gh repo delete $REPOSITORY --yes > /dev/null
    else
        echo "-> Repository has content. Archiving..."
        gh api -X PATCH /repos/$REPOSITORY -F archived=true > /dev/null
    fi
done < $FILE