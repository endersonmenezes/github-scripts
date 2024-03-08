#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-03-08
# Description: This script reads a repositores.csv file, and grant permissions on repo.
# Usage: bash add-team-as-admin.sh
##

# Create a SHA256 of the file for audit
SHA256=$(sha256sum $0 | cut -d' ' -f1)
echo "Executing a file: $0, with SHA256: $SHA256"

## Read a CSV file (owner-repo,team)
FILE="repositories.csv"

# Verify if the file exists
if [ ! -f $FILE ]; then
    echo "The file $FILE does not exist."
    exit 1
fi

# Verify a file format
if [[ $(head -n 1 $FILE) != "owner-repo,team" ]]; then
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
while IFS=, read -r OWNER_REPO TEAM; do

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
    echo "Adding the team ${TEAM} as admin on the repository ${OWNER_REPO}..."
    gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /orgs/"${OWNER}"/teams/"${TEAM}"/repos/"${OWNER}"/"${REPOSITORY}" \
        -f permission='admin' > /dev/null || {
        echo "An error occurred while adding the team ${TEAM} as admin on the repository ${OWNER_REPO}."
    }
    echo "The team ${TEAM} was added as admin on the repository ${OWNER_REPO}."
done < $FILE
