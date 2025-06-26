#!/usr/bin/env bash

###############################################################################
# GitHub Archived Repository Security Alerts Cleaner
#
# Author: Enderson Menezes
# Created: 2025-06-25
#
# Description:
#   This script processes archived repositories to clean up security alerts.
#   It supports interactive menu selection or environment variable configuration.
#
# Usage:
#   Interactive mode:
#     ./25-close-security-alerts-archived-repos.sh
#
#   Non-interactive mode (environment variables):
#     CLOSE_DEPENDABOT=true CLOSE_CODE_SCANNING=true ./script.sh
#     NON_INTERACTIVE=true CLOSE_SECRET_SCANNING=true ./script.sh
#
# Environment Variables:
#   GITHUB_TOKEN        - Required: GitHub personal access token
#   DEBUG               - Optional: Set to 'true' for verbose output
#   NON_INTERACTIVE     - Optional: Set to 'true' to skip interactive menu
#   CLOSE_DEPENDABOT    - Optional: Set to 'true' to close Dependabot alerts
#   CLOSE_CODE_SCANNING - Optional: Set to 'true' to close Code scanning alerts
#   CLOSE_SECRET_SCANNING - Optional: Set to 'true' to close Secret scanning alerts
#
###############################################################################

# Check for environment variable overrides (for non-interactive mode)
if [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
    CLOSE_DEPENDABOT=${CLOSE_DEPENDABOT:-false}
    CLOSE_CODE_SCANNING=${CLOSE_CODE_SCANNING:-false}
    CLOSE_SECRET_SCANNING=${CLOSE_SECRET_SCANNING:-false}
    
    # Validate that at least one alert type is selected
    if [[ "$CLOSE_DEPENDABOT" == "false" && "$CLOSE_CODE_SCANNING" == "false" && "$CLOSE_SECRET_SCANNING" == "false" ]]; then
        echo "Error: In non-interactive mode, you must specify at least one alert type to close."
        echo "Set one or more of: CLOSE_DEPENDABOT, CLOSE_CODE_SCANNING, CLOSE_SECRET_SCANNING to 'true'"
        exit 1
    fi
fi
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

# Global variables for what to close
CLOSE_DEPENDABOT=false
CLOSE_CODE_SCANNING=false
CLOSE_SECRET_SCANNING=false

# Function to show selection menu
show_selection_menu() {
    echo ""
    echo "=========================================="
    echo "  Security Alerts Cleanup Options"
    echo "=========================================="
    echo ""
    echo "Select which types of alerts to close:"
    echo ""
    echo "1) Dependabot alerts"
    echo "2) Code scanning alerts" 
    echo "3) Secret scanning alerts"
    echo "4) All alert types"
    echo "5) Custom selection"
    echo "6) Exit"
    echo ""
    
    while true; do
        read -p "Choose an option (1-6): " choice
        case $choice in
            1)
                CLOSE_DEPENDABOT=true
                echo "✓ Selected: Dependabot alerts only"
                break
                ;;
            2)
                CLOSE_CODE_SCANNING=true
                echo "✓ Selected: Code scanning alerts only"
                break
                ;;
            3)
                CLOSE_SECRET_SCANNING=true
                echo "✓ Selected: Secret scanning alerts only"
                break
                ;;
            4)
                CLOSE_DEPENDABOT=true
                CLOSE_CODE_SCANNING=true
                CLOSE_SECRET_SCANNING=true
                echo "✓ Selected: All alert types"
                break
                ;;
            5)
                custom_selection_menu
                break
                ;;
            6)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid option. Please choose 1-6."
                ;;
        esac
    done
    echo ""
}

# Function for custom selection
custom_selection_menu() {
    echo ""
    echo "Custom Selection - Choose multiple types:"
    echo ""
    
    while true; do
        read -p "Close Dependabot alerts? (y/n): " dep_choice
        case $dep_choice in
            [Yy]* ) CLOSE_DEPENDABOT=true; break;;
            [Nn]* ) CLOSE_DEPENDABOT=false; break;;
            * ) echo "Please answer y or n.";;
        esac
    done
    
    while true; do
        read -p "Close Code scanning alerts? (y/n): " code_choice
        case $code_choice in
            [Yy]* ) CLOSE_CODE_SCANNING=true; break;;
            [Nn]* ) CLOSE_CODE_SCANNING=false; break;;
            * ) echo "Please answer y or n.";;
        esac
    done
    
    while true; do
        read -p "Close Secret scanning alerts? (y/n): " secret_choice
        case $secret_choice in
            [Yy]* ) CLOSE_SECRET_SCANNING=true; break;;
            [Nn]* ) CLOSE_SECRET_SCANNING=false; break;;
            * ) echo "Please answer y or n.";;
        esac
    done
    
    echo ""
    echo "✓ Custom selection complete:"
    echo "  - Dependabot: $([[ $CLOSE_DEPENDABOT == true ]] && echo "Yes" || echo "No")"
    echo "  - Code scanning: $([[ $CLOSE_CODE_SCANNING == true ]] && echo "Yes" || echo "No")"
    echo "  - Secret scanning: $([[ $CLOSE_SECRET_SCANNING == true ]] && echo "Yes" || echo "No")"
}

# Show selection menu (unless running in non-interactive mode)
if [[ "${NON_INTERACTIVE:-false}" != "true" ]]; then
    show_selection_menu
else
    echo ""
    echo "=========================================="
    echo "  Non-Interactive Mode"
    echo "=========================================="
    echo ""
    echo "Configuration from environment variables:"
    echo "  - Dependabot: $([[ $CLOSE_DEPENDABOT == true ]] && echo "Yes" || echo "No")"
    echo "  - Code scanning: $([[ $CLOSE_CODE_SCANNING == true ]] && echo "Yes" || echo "No")"
    echo "  - Secret scanning: $([[ $CLOSE_SECRET_SCANNING == true ]] && echo "Yes" || echo "No")"
    echo ""
fi

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

    # Close security alerts based on user selection
    if [[ "$CLOSE_DEPENDABOT" == "true" ]]; then
        close_dependabot_alerts "$ORG" "$REPO"
    else
        echo "  Skipping Dependabot alerts (not selected)"
    fi
    
    if [[ "$CLOSE_CODE_SCANNING" == "true" ]]; then
        close_code_scanning_alerts "$ORG" "$REPO"
    else
        echo "  Skipping Code scanning alerts (not selected)"
    fi
    
    if [[ "$CLOSE_SECRET_SCANNING" == "true" ]]; then
        close_secret_scanning_alerts "$ORG" "$REPO"
    else
        echo "  Skipping Secret scanning alerts (not selected)"
    fi
    
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
