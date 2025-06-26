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
#   5. Closes all Secret scanning alerts
#   6. Re-archives the repository
#
# Input File Format (25-close-security-alerts-archived-repos.csv):
#   organization,repository
#
# Usage: bash 25-close-security-alerts-archived-repos.sh
# Debug mode: DEBUG=true bash 25-close-security-alerts-archived-repos.sh
###############################################################################

# Read Common Functions
source functions.sh

# Debug mode (set to true to enable verbose API responses)
DEBUG=${DEBUG:-false}

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
            if [[ "$DEBUG" == "true" ]]; then
                echo "    [DEBUG] API call: PATCH /repos/$org/$repo/dependabot/alerts/$alert_number"
                response=$(gh api \
                    --method PATCH \
                    -H "Accept: application/vnd.github+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    "/repos/$org/$repo/dependabot/alerts/$alert_number" \
                    -f state=dismissed \
                    -f dismissed_reason=no_bandwidth \
                    -f dismissed_comment="Automatically dismissed during repository archival process" 2>&1)
                echo "    [DEBUG] Response: $response"
            else
                gh api \
                    --method PATCH \
                    -H "Accept: application/vnd.github+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    "/repos/$org/$repo/dependabot/alerts/$alert_number" \
                    -f state=dismissed \
                    -f dismissed_reason=no_bandwidth \
                    -f dismissed_comment="Automatically dismissed during repository archival process" > /dev/null 2>&1
            fi
        fi
    done <<< "$alerts"
}

# Function to close Code scanning alerts
close_code_scanning_alerts() {
    local org=$1
    local repo=$2
    
    echo "  Checking for Code scanning alerts..."
    
    # Get all open Code scanning alerts
    if [[ "$DEBUG" == "true" ]]; then
        echo "    [DEBUG] API call: GET /repos/$org/$repo/code-scanning/alerts?state=open"
    fi
    
    local alerts=$(gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$org/$repo/code-scanning/alerts?state=open" \
        --jq '.[].number' 2>/dev/null)
    
    if [[ "$DEBUG" == "true" ]]; then
        echo "    [DEBUG] Found alerts: $alerts"
    fi
    
    if [[ -z "$alerts" ]]; then
        echo "    No open Code scanning alerts found."
        return
    fi
    
    # Close each alert
    while IFS= read -r alert_number; do
        if [[ -n "$alert_number" ]]; then
            echo "    Closing Code scanning alert #$alert_number..."
            if [[ "$DEBUG" == "true" ]]; then
                echo "    [DEBUG] API call: PATCH /repos/$org/$repo/code-scanning/alerts/$alert_number"
                response=$(gh api \
                    --method PATCH \
                    -H "Accept: application/vnd.github+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    "/repos/$org/$repo/code-scanning/alerts/$alert_number" \
                    -f state=dismissed \
                    -f dismissed_reason="won't fix" \
                    -f dismissed_comment="Automatically dismissed during repository archival process" 2>&1)
                echo "    [DEBUG] Response: $response"
                echo "    [DEBUG] Exit code: $?"
            else
                gh api \
                    --method PATCH \
                    -H "Accept: application/vnd.github+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    "/repos/$org/$repo/code-scanning/alerts/$alert_number" \
                    -f state=dismissed \
                    -f dismissed_reason="won't fix" \
                    -f dismissed_comment="Automatically dismissed during repository archival process" > /dev/null 2>&1
            fi
        fi
    done <<< "$alerts"
}

# Function to close Secret scanning alerts
close_secret_scanning_alerts() {
    local org=$1
    local repo=$2
    
    echo "  Checking for Secret scanning alerts..."
    
    # Get all open Secret scanning alerts (is:open)
    if [[ "$DEBUG" == "true" ]]; then
        echo "    [DEBUG] Query 1: is:open - API call: GET /repos/$org/$repo/secret-scanning/alerts?state=open"
    fi
    
    local alerts_open=$(gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$org/$repo/secret-scanning/alerts?state=open" \
        --jq '.[].number' 2>/dev/null)
    
    if [[ "$DEBUG" == "true" ]]; then
        echo "    [DEBUG] Raw response from query 1:"
        gh api \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "/repos/$org/$repo/secret-scanning/alerts?state=open" 2>/dev/null | head -20
    fi
    
    # Get secret scanning alerts with generic results (is:open results:generic)
    if [[ "$DEBUG" == "true" ]]; then
        echo "    [DEBUG] Query 2: is:open results:generic - API calls for specific generic secret types"
    fi
    
    # List of generic secret types
    local generic_types=(
        "http_basic_authentication_header"
        "http_bearer_authentication_header" 
        "mongodb_connection_string"
        "mysql_connection_string"
        "openssh_private_key"
        "pgp_private_key"
        "postgres_connection_string"
        "rsa_private_key"
    )
    
    local all_generic_alerts=""
    for secret_type in "${generic_types[@]}"; do
        if [[ "$DEBUG" == "true" ]]; then
            echo "    [DEBUG] Checking secret_type: $secret_type"
        fi
        
        local type_alerts=$(gh api \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "/repos/$org/$repo/secret-scanning/alerts?state=open&secret_type=$secret_type" \
            --jq '.[].number' 2>/dev/null)
        
        if [[ -n "$type_alerts" ]]; then
            all_generic_alerts="$all_generic_alerts$type_alerts"$'\n'
            if [[ "$DEBUG" == "true" ]]; then
                echo "    [DEBUG] Found alerts for $secret_type: $type_alerts"
            fi
        fi
    done
    
    # Clean up the generic alerts list
    local alerts_generic=$(echo "$all_generic_alerts" | grep -v '^$' | sort -u)
    
    # Combine and deduplicate alerts
    local all_alerts=$(echo -e "$alerts_open\n$alerts_generic" | sort -u | grep -v '^$')
    
    if [[ "$DEBUG" == "true" ]]; then
        echo "    [DEBUG] Found secret scanning alerts (is:open): $alerts_open"
        echo "    [DEBUG] Found secret scanning alerts (is:open results:generic): $alerts_generic"
        echo "    [DEBUG] Combined unique alerts: $all_alerts"
    fi
    
    if [[ -z "$all_alerts" ]]; then
        echo "    No open Secret scanning alerts found."
        return
    fi
    
    # Close each alert
    while IFS= read -r alert_number; do
        if [[ -n "$alert_number" ]]; then
            echo "    Closing Secret scanning alert #$alert_number..."
            if [[ "$DEBUG" == "true" ]]; then
                echo "    [DEBUG] API call: PATCH /repos/$org/$repo/secret-scanning/alerts/$alert_number"
                response=$(gh api \
                    --method PATCH \
                    -H "Accept: application/vnd.github+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    "/repos/$org/$repo/secret-scanning/alerts/$alert_number" \
                    -f state=resolved \
                    -f resolution=wont_fix \
                    -f resolution_comment="Automatically resolved during repository archival process" 2>&1)
                echo "    [DEBUG] Response: $response"
                echo "    [DEBUG] Exit code: $?"
            else
                gh api \
                    --method PATCH \
                    -H "Accept: application/vnd.github+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    "/repos/$org/$repo/secret-scanning/alerts/$alert_number" \
                    -f state=resolved \
                    -f resolution=wont_fix \
                    -f resolution_comment="Automatically resolved during repository archival process" > /dev/null 2>&1
            fi
        fi
    done <<< "$all_alerts"
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
    if [[ "$DEBUG" == "true" ]]; then
        echo "    [DEBUG] API call: PATCH /repos/$ORG/$REPO (unarchive)"
        response=$(gh api \
            --method PATCH \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "/repos/$ORG/$REPO" \
            -f archived=false 2>&1)
        echo "    [DEBUG] Unarchive response: $response"
    else
        gh api \
            --method PATCH \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "/repos/$ORG/$REPO" \
            -f archived=false > /dev/null 2>&1
    fi

    if [[ $? -ne 0 ]]; then
        echo "  Failed to unarchive repository. Skipping..."
        continue
    fi

    # Close Dependabot alerts
    close_dependabot_alerts "$ORG" "$REPO"
    
    # Close Code scanning alerts
    close_code_scanning_alerts "$ORG" "$REPO"
    
    # Close Secret scanning alerts
    close_secret_scanning_alerts "$ORG" "$REPO"
    
    # Re-archive the repository
    echo "  Re-archiving repository..."
    if [[ "$DEBUG" == "true" ]]; then
        echo "    [DEBUG] API call: PATCH /repos/$ORG/$REPO (re-archive)"
        response=$(gh api \
            --method PATCH \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "/repos/$ORG/$REPO" \
            -f archived=true 2>&1)
        echo "    [DEBUG] Re-archive response: $response"
    else
        gh api \
            --method PATCH \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "/repos/$ORG/$REPO" \
            -f archived=true > /dev/null 2>&1
    fi

    if [[ $? -eq 0 ]]; then
        echo "  ✓ Repository successfully processed and re-archived."
    else
        echo "  ⚠ Warning: Failed to re-archive repository."
    fi
    
    echo ""
done < $FILE

echo "Script execution completed."
