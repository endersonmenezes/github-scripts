#!/bin/bash

###############################################################################
# Holopin Badge Generator
#
# Author: Enderson Menezes
# Created: 2025-09-18
# Updated: 2025-09-18
#
# Description:
#   This script generates and issues Holopin badges to recipients based on
#   email addresses and sticker IDs provided in a CSV file. Uses the Holopin
#   API to issue badges with optional email notifications.
#
# Usage: bash 31-holopin-badge-generator.sh [--no-email] [--metadata="custom metadata"]
#
# Parameters:
#   --no-email:    Issue badges without sending email notifications
#   --metadata:    Optional metadata to include with the badge (string)
#
# Environment Variables:
#   HOLOPIN_KEY:   API key for Holopin (required)
#
# Input File: 31-holopin-badge-generator.csv
# Format: email,sticker_id[,metadata]
# Example:
#   email,sticker_id,metadata
#   user@example.com,abc123,First badge
#   admin@company.com,def456,Welcome badge
#
# Output File: 31-holopin-badge-generator-results.csv
# Format: timestamp,email,sticker_id,status,response_message,metadata
#
# Features:
# - Bulk badge issuing with CSV input
# - Optional email notifications (configurable)
# - Custom metadata support (per badge or global)
# - Comprehensive error handling and logging
# - Rate limiting to respect API limits
# - Detailed results tracking
###############################################################################

set -euo pipefail

# Import shared functions
source ./functions.sh

# Global variables
SCRIPT_NAME=$(basename "$0" | cut -d'.' -f1)
INPUT_FILE="${SCRIPT_NAME}.csv"
OUTPUT_FILE="${SCRIPT_NAME}-results.csv"
SEND_EMAIL=true
GLOBAL_METADATA=""
declare -i TOTAL_PROCESSED=0
declare -i TOTAL_SUCCESS=0
declare -i TOTAL_FAILED=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print status messages to stderr to separate from data output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}" >&2
}

# Check prerequisites
check_prerequisites() {
    print_status "${BLUE}" "🔍 Checking prerequisites..."
    
    # Check if GitHub CLI is installed (from functions.sh)
    is_gh_installed
    
    # Check if required tools are available
    if ! command -v curl &> /dev/null; then
        print_status "${RED}" "❌ ERROR: curl is not installed."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_status "${RED}" "❌ ERROR: jq is not installed."
        exit 1
    fi
    
    # Check if HOLOPIN_KEY environment variable is set
    if [[ -z "${HOLOPIN_KEY:-}" ]]; then
        print_status "${RED}" "❌ ERROR: HOLOPIN_KEY environment variable is not set."
        print_status "${YELLOW}" "   Please set your Holopin API key:"
        print_status "${YELLOW}" "   export HOLOPIN_KEY='your-api-key-here'"
        exit 1
    fi
    
    # Check if input file exists
    if [[ ! -f "$INPUT_FILE" ]]; then
        print_status "${RED}" "❌ ERROR: Input file '$INPUT_FILE' does not exist."
        print_status "${YELLOW}" "   Create it based on the example file: ${SCRIPT_NAME}.example.csv"
        exit 1
    fi
    
    print_status "${GREEN}" "✅ All prerequisites met."
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-email)
                SEND_EMAIL=false
                print_status "${YELLOW}" "📧 Email notifications disabled"
                shift
                ;;
            --metadata=*)
                GLOBAL_METADATA="${1#*=}"
                print_status "${CYAN}" "📝 Global metadata set: '$GLOBAL_METADATA'"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_status "${RED}" "❌ ERROR: Unknown parameter '$1'"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Holopin Badge Generator

Usage: bash $0 [OPTIONS]

Options:
    --no-email              Issue badges without sending email notifications
    --metadata="text"       Set global metadata for all badges
    --help, -h             Show this help message

Environment Variables:
    HOLOPIN_KEY            Your Holopin API key (required)

Input File Format:
    email,sticker_id[,metadata]

Example:
    user@example.com,abc123,First achievement
    admin@company.com,def456,Welcome badge

EOF
}

# Initialize output file
initialize_output() {
    print_status "${BLUE}" "📁 Initializing output file: $OUTPUT_FILE"
    echo "timestamp,email,sticker_id,status,response_message,metadata" > "$OUTPUT_FILE"
}

# Issue a single badge via Holopin API
issue_badge() {
    local email="$1"
    local sticker_id="$2"
    local metadata="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    print_status "${CYAN}" "🎯 Issuing badge '$sticker_id' to '$email'..."
    
    # Prepare API request body
    local request_body="{}"
    
    # Add email if notifications are enabled
    if [[ "$SEND_EMAIL" == true ]]; then
        request_body=$(echo "$request_body" | jq --arg email "$email" '. + {email: $email}')
    fi
    
    # Add metadata if provided
    if [[ -n "$metadata" ]]; then
        request_body=$(echo "$request_body" | jq --arg metadata "$metadata" '. + {metadata: $metadata}')
    fi
    
    # Make API request
    local api_url="https://www.holopin.io/api/sticker/share?id=${sticker_id}&apiKey=${HOLOPIN_KEY}"
    local response_file=$(mktemp)
    local http_code
    
    # Execute curl request and capture HTTP status code
    http_code=$(curl -s -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$request_body" \
        "$api_url" \
        -o "$response_file")
    
    # Process response
    local status
    local response_message
    
    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
        status="SUCCESS"
        response_message="Badge issued successfully"
        TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
        print_status "${GREEN}" "   ✅ Success!"
    else
        status="FAILED"
        if [[ -s "$response_file" ]]; then
            # Try to extract error message from response
            response_message=$(jq -r '.message // .error // "API request failed"' "$response_file" 2>/dev/null || echo "HTTP $http_code - $(cat "$response_file")")
        else
            response_message="HTTP $http_code - No response body"
        fi
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        print_status "${RED}" "   ❌ Failed: $response_message"
    fi
    
    # Log result to output file
    echo "\"$timestamp\",\"$email\",\"$sticker_id\",\"$status\",\"$response_message\",\"$metadata\"" >> "$OUTPUT_FILE"
    
    # Clean up temporary file
    rm -f "$response_file"
    
    TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))
}

# Process CSV file and issue badges
process_badges() {
    print_status "${GREEN}" "🚀 Starting badge generation process..."
    print_status "${BLUE}" "📊 Processing file: $INPUT_FILE"
    
    local line_number=0
    local header_processed=false
    
    while IFS=',' read -r email sticker_id file_metadata || [[ -n "$email" ]]; do
        line_number=$((line_number + 1))
        
        # Skip header line
        if [[ "$header_processed" == false ]]; then
            header_processed=true
            print_status "${YELLOW}" "📋 Skipping header line"
            continue
        fi
        
        # Skip empty lines
        if [[ -z "$email" && -z "$sticker_id" ]]; then
            print_status "${YELLOW}" "⏭️  Skipping empty line $line_number"
            continue
        fi
        
        # Skip comment lines (starting with #)
        if [[ "$email" =~ ^[[:space:]]*# ]]; then
            print_status "${YELLOW}" "💬 Skipping comment line $line_number"
            continue
        fi
        
        # Trim whitespace
        email=$(echo "$email" | tr -d '"' | xargs)
        sticker_id=$(echo "$sticker_id" | tr -d '"' | xargs)
        file_metadata=$(echo "$file_metadata" | tr -d '"' | xargs)
        
        # Validate required fields
        if [[ -z "$email" || -z "$sticker_id" ]]; then
            print_status "${YELLOW}" "⚠️  Line $line_number: Missing required fields (email or sticker_id), skipping..."
            continue
        fi
        
        # Validate email format (basic validation)
        if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            print_status "${RED}" "⚠️  Line $line_number: Invalid email format '$email', skipping..."
            continue
        fi
        
        # Determine metadata to use (priority: global > file > empty)
        local metadata_to_use="$GLOBAL_METADATA"
        if [[ -z "$metadata_to_use" && -n "$file_metadata" ]]; then
            metadata_to_use="$file_metadata"
        fi
        
        print_status "${CYAN}" "📤 Processing line $line_number: $email -> $sticker_id"
        
        # Issue the badge
        issue_badge "$email" "$sticker_id" "$metadata_to_use"
        
        # Rate limiting - sleep between requests to avoid hitting API limits
        sleep 1
        
    done < "$INPUT_FILE"
}

# Generate summary report
generate_summary() {
    print_status "${NC}" ""
    print_status "${BLUE}" "📈 SUMMARY REPORT"
    print_status "${BLUE}" "=================="
    print_status "${CYAN}" "📊 Total processed: $TOTAL_PROCESSED"
    print_status "${GREEN}" "✅ Successful: $TOTAL_SUCCESS"
    print_status "${RED}" "❌ Failed: $TOTAL_FAILED"
    print_status "${BLUE}" "📁 Results saved to: $OUTPUT_FILE"
    print_status "${NC}" ""
    
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        print_status "${YELLOW}" "⚠️  Some badges failed to issue. Check the results file for details."
        return 1
    else
        print_status "${GREEN}" "🎉 All badges issued successfully!"
        return 0
    fi
}

# Main function
main() {
    print_status "${GREEN}" "🎯 Holopin Badge Generator"
    print_status "${GREEN}" "=========================="
    
    # Audit file execution
    audit_file
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Initialize output file
    initialize_output
    
    # Process badges
    process_badges
    
    # Generate summary
    generate_summary
}

# Execute main function only if script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi