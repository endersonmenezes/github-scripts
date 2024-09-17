#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-09-17
# Description: This script will transform a public to private repository and archive the repository.
# Usage: bash 15-public-to-private-and-archive.sh
##

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 varible)
audit_file

## Read a CSV file (Define FILE variable)
read_config_file

# Specific Config File
if [[ $(head -n 1 $FILE) != "organization,repository" ]]; then
    echo "The file $FILE does not have the correct format."
    exit 1
fi

# Verify last line
if [[ $(tail -n 1 $FILE) != "" ]]; then
    echo "The file $FILE does not have the correct format."
    echo "Adding a blank line at the end of the file..."
    echo "" >> $FILE
fi

## Team
while IFS=, read -r ORG REPO; do
    # Continue on first line
    [ "$ORG" == "organization" ] && continue

    # Ignore blank line
    [ -z "$ORG" ] && continue

    echo "Transforming the repository $REPO from the organization $ORG to private and archiving..."

    # Try unarchive the repository
    gh api \
        --method PATCH \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /repos/$ORG/$REPO \
            -f archived=false > /dev/null 2>&1
    
    # Archive and Private
    gh api \
        --method PATCH \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /repos/$ORG/$REPO \
            -f archived=true \
            -f private=true > /dev/null 2>&1
done < $FILE

