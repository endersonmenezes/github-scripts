#!/usr/bin/env bash

###############################################################################
# GitHub Archived Repository Security Alerts Cleaner
#
# Author: Enderson Menezes
# Created: 2025-06-25
#
# Description:
#   This script processes archived repositories to clean up security alerts.
#   For each repository in the CSV file, it:
#   1. Checks if the repository is archived
#   2. If archived, temporarily unarchives it
#   3. Closes all Dependabot security alerts
#   4. Closes all CodeQL/Code scanning alerts
#   5. Re-archives the repository
#
# Input File Format (25-close-security-alerts-archived-repos.csv):
#   organization,repository
#
# Usage: bash 25-close-security-alerts-archived-repos.sh
###############################################################################

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 variable)
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

# Function to close Dependabot alerts
close_dependabot_alerts() {
    local org=$1
    local repo=$2
    
    echo "  Checking for Dependabot alerts..."
    
    # Get all open Dependabot alerts
    local alerts=$(gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$org/$repo/dependabot/alerts?state=open" \
        --jq '.[].number' 2>/dev/null)
    
    if [[ -z "$alerts" ]]; then
        echo "    No open Dependabot alerts found."
        return
    fi
    
    # Close each alert
    while IFS= read -r alert_number; do
        if [[ -n "$alert_number" ]]; then
            echo "    Closing Dependabot alert #$alert_number..."
            gh api \
                --method PATCH \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "/repos/$org/$repo/dependabot/alerts/$alert_number" \
                -f state=dismissed \
                -f dismissed_reason=no_bandwidth \
                -f dismissed_comment="Automatically dismissed during repository archival process" > /dev/null 2>&1
        fi
    done <<< "$alerts"
}

# Function to close Code scanning alerts
close_code_scanning_alerts() {
    local org=$1
    local repo=$2
    
    echo "  Checking for Code scanning alerts..."
    
    # Get all open Code scanning alerts
    local alerts=$(gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$org/$repo/code-scanning/alerts?state=open" \
        --jq '.[].number' 2>/dev/null)
    
    if [[ -z "$alerts" ]]; then
        echo "    No open Code scanning alerts found."
        return
    fi
    
    # Close each alert
    while IFS= read -r alert_number; do
        if [[ -n "$alert_number" ]]; then
            echo "    Closing Code scanning alert #$alert_number..."
            gh api \
                --method PATCH \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "/repos/$org/$repo/code-scanning/alerts/$alert_number" \
                -f state=dismissed \
                -f dismissed_reason=wont_fix \
                -f dismissed_comment="Automatically dismissed during repository archival process" > /dev/null 2>&1
        fi
    done <<< "$alerts"
}

## Process repositories
while IFS=, read -r ORG REPO; do
    # Continue on first line
    [ "$ORG" == "organization" ] && continue

    # Ignore blank line
    [ -z "$ORG" ] && continue

    echo "Processing repository $REPO from organization $ORG..."

    # Check if repository is archived
    echo "  Checking if repository is archived..."
    archived_status=$(gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$ORG/$REPO" \
        --jq '.archived' 2>/dev/null)

    if [[ "$archived_status" != "true" ]]; then
        echo "  Repository is not archived. Skipping..."
        continue
    fi

    echo "  Repository is archived. Temporarily unarchiving..."
    
    # Unarchive the repository temporarily
    gh api \
        --method PATCH \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$ORG/$REPO" \
        -f archived=false > /dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        echo "  Failed to unarchive repository. Skipping..."
        continue
    fi

    # Close Dependabot alerts
    close_dependabot_alerts "$ORG" "$REPO"
    
    # Close Code scanning alerts
    close_code_scanning_alerts "$ORG" "$REPO"
    
    # Re-archive the repository
    echo "  Re-archiving repository..."
    gh api \
        --method PATCH \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$ORG/$REPO" \
        -f archived=true > /dev/null 2>&1

    if [[ $? -eq 0 ]]; then
        echo "  ✓ Repository successfully processed and re-archived."
    else
        echo "  ⚠ Warning: Failed to re-archive repository."
    fi
    
    echo ""
done < $FILE

echo "Script execution completed."
