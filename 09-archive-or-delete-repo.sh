#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-07-18
# Description: This script archive a repository if have content and delete if not.
# Usage: bash add-team-as-admin.sh
##

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

    echo "Processing repository: $REPOSITORY"

    # Verify if repository have content
    REPOSITORY_CONTENT=$(gh api /repos/$REPOSITORY/contents)

    # if "This repository is empty." then delete
    if [[ "$REPOSITORY_CONTENT" == *"This repository is empty."* ]]; then
        echo "-> Repository is empty. Deleting..."
        gh repo delete $REPOSITORY --yes
    else
        echo "-> Repository have content. Archiving..."
        gh api -X PATCH /repos/$REPOSITORY -F archived=true
    fi
done < $FILE