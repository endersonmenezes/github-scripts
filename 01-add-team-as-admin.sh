#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-03-08
# Description: This script reads a repositores.csv file, and grant permissions on repo.
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
if [[ $(head -n 1 $FILE) != "owner-repo,team,permission" ]]; then
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
while IFS=, read -r OWNER_REPO TEAM PERMISSION; do

    # Continue on first line
    [ "$OWNER_REPO" == "owner-repo" ] && continue

    # Ignore blank line
    [ -z "$OWNER_REPO" ] && continue

    # Split the owner and repository
    OWNER=$(echo $OWNER_REPO | cut -d'/' -f1)
    REPOSITORY=$(echo $OWNER_REPO | cut -d'/' -f2)

    # Verify if the owner and repository exists and the user has permission to access
    gh api repos/"${OWNER_REPO}" &>/dev/null || {
        echo "The owner ${OWNER_REPO} and the repository ${REPOSITORY} does not exist or you do not have permission to access."
        exit 1
    }
    echo "The owner ${OWNER_REPO} and the repository ${REPOSITORY} exists and you have permission to access."

    # Verify if the team exists
    gh api orgs/"${OWNER}"/teams/"${TEAM}" &>/dev/null || {
        echo "The team ${TEAM} does not exist or you do not have permission to access."
        exit 1
    }
    echo "The team ${TEAM} exists and you have permission to access."

    # Add the team as admin
    echo "Adding the team ${TEAM} as ${PERMISSION} on the repository ${OWNER_REPO}..."
    
    # Add or update the team as permissions
    gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /orgs/"${OWNER}"/teams/"${TEAM}"/repos/"${OWNER}"/"${REPOSITORY}" \
        -f permission="${PERMISSION}" &>/dev/null || {
        echo "The team ${TEAM} was not added as ${PERMISSION} on the repository ${OWNER_REPO}."
        exit 1
    }
    echo "The team ${TEAM} was added as ${PERMISSION} on the repository ${OWNER_REPO}."
done < $FILE
