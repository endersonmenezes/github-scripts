#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-03-08
# Description: This script delete all teams.
# Usage: bash 07-delete-teams.sh
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
if [[ $(head -n 1 $FILE) != "team,org" ]]; then
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
while IFS=, read -r TEAM ORG; do
    # Continue on first line
    [ "$TEAM" == "team" ] && continue

    # Ignore blank line
    [ -z "$TEAM" ] && continue

    echo "Deleting team: $TEAM on $ORG"

    # Delete team
    gh api \
        --method DELETE \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /orgs/$ORG/teams/$TEAM > /dev/null
    
done < $FILE