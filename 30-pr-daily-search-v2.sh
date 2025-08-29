#!/bin/bash

###############################################################################
# Daily Pull Request Search Tool
#
# Author: Enderson Menezes
# Created: 2025-08-29
# Updated: 2025-08-29
#
# Description:
#   This script searches for merged Pull Requests day by day across multiple
#   GitHub organizations. For each day, it searches for PRs targeting both
#   'main' and 'master' branches to ensure comprehensive coverage.
#
# Usage: bash 30-pr-daily-search.sh [START_DATE] [END_DATE] [--test]
#
# Parameters:
#   START_DATE: Start date in YYYY-MM-DD format (default: 2025-01-01)
#   END_DATE:   End date in YYYY-MM-DD format (default: today)
#   --test:     Test mode - process only first 3 days
#
# Input File: 30-pr-daily-search.csv
# Format: organization
# Example:
#   organization
#   stone-payments
#   pagarme
#   stone-ton
#   mundipagg
#   dlpco
#
# Output File: 30-pr-daily-search-results.csv
# Format: date,branch,organization,pr_number,pr_title,pr_url,author,merged_at,created_at
#
# Features:
# - Day-by-day PR search with date range support
# - Searches both 'main' and 'master' branches per organization per day
# - Merged PRs only (is:merged filter)
# - Rate limiting to respect GitHub API limits
# - Test mode for validation
# - Comprehensive error handling and progress tracking
###############################################################################

set -euo pipefail

# Import shared functions
source ./functions.sh

# Global variables
TEST_MODE=false
START_DATE="2025-01-01"
END_DATE=""
PROCESSED_DAYS=0
TOTAL_DAYS=0
TEMP_DIR=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to setup temporary directory
setup_temp_dir() {
    TEMP_DIR=$(mktemp -d)
    print_status "${GREEN}" "Created temporary directory: ${TEMP_DIR}"
}

# Function to cleanup temporary directory
cleanup() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        print_status "${YELLOW}" "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi
}

# Function to get end date (today if not specified)
get_end_date() {
    if [[ -z "${END_DATE}" ]]; then
        END_DATE=$(date +%Y-%m-%d)
        print_status "${BLUE}" "End date not specified, using today: ${END_DATE}"
    fi
}

# Function to validate date format
validate_date() {
    local date_str=$1
    local date_name=$2
    
    if ! date -d "${date_str}" >/dev/null 2>&1; then
        print_status "${RED}" "Invalid ${date_name}: ${date_str} (expected format: YYYY-MM-DD)"
        exit 1
    fi
}

# Function to calculate days between dates
calculate_days() {
    local start_timestamp=$(date -d "${START_DATE}" +%s)
    local end_timestamp=$(date -d "${END_DATE}" +%s)
    
    if [[ ${start_timestamp} -gt ${end_timestamp} ]]; then
        print_status "${RED}" "Start date ${START_DATE} is after end date ${END_DATE}"
        exit 1
    fi
    
    TOTAL_DAYS=$(( (end_timestamp - start_timestamp) / 86400 + 1 ))
    print_status "${BLUE}" "Processing ${TOTAL_DAYS} days from ${START_DATE} to ${END_DATE}"
    
    if [[ "${TEST_MODE}" == true ]]; then
        TOTAL_DAYS=$(( TOTAL_DAYS > 3 ? 3 : TOTAL_DAYS ))
        print_status "${YELLOW}" "Test mode enabled - processing first ${TOTAL_DAYS} days only"
    fi
}

# Function to read organizations from CSV
read_organizations() {
    local organizations=()
    
    # Skip header and read organizations
    while IFS= read -r org; do
        # Skip header line
        [[ "${org}" == "organization" ]] && continue
        # Skip empty lines
        [[ -z "${org}" ]] && continue
        # Clean organization name
        org=$(echo "${org}" | sed 's/^"//;s/"$//;s/^'\''//;s/'\''$//')
        organizations+=("${org}")
    done < "30-pr-daily-search-v2.csv"
    
    if [[ ${#organizations[@]} -eq 0 ]]; then
        print_status "${RED}" "No organizations found in 30-pr-daily-search-v2.csv"
        exit 1
    fi
    
    print_status "${GREEN}" "Found ${#organizations[@]} organizations: ${organizations[*]}"
    # Return organizations as space-separated string
    echo "${organizations[*]}"
}

# Function to search PRs for a specific date and organization
search_prs_for_date() {
    local search_date=$1
    local organization=$2
    local branch=$3
    local temp_file="${TEMP_DIR}/prs_${search_date}_${organization}_${branch}.json"
    
    # Build the search query - GitHub search API format
    local query="org:${organization} is:merged created:${search_date} head:${branch}"
    
    print_status "${BLUE}" "  Searching ${organization} (${branch}): ${search_date}"
    
    # Search for PRs
    if gh api \
        --paginate \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/search/issues" \
        -f q="${query}" \
        -f type="pr" \
        -f state="closed" \
        -f sort="created" \
        -f order="desc" > "${temp_file}" 2>/dev/null; then
        
        # Check if we have results
        local total_count=$(jq -r '.items | length' "${temp_file}" 2>/dev/null || echo "0")
        
        if [[ "${total_count}" -gt 0 ]]; then
            print_status "${GREEN}" "    ✓ Found ${total_count} PRs"
            
            # Process each PR and add to CSV
            jq -r --arg DATE "${search_date}" --arg BRANCH "${branch}" --arg ORG "${organization}" '
                .items[] | 
                [
                    $DATE,
                    $BRANCH,
                    $ORG,
                    .number,
                    .title,
                    .html_url,
                    .user.login,
                    .closed_at,
                    .created_at
                ] | @csv
            ' "${temp_file}" >> "30-pr-daily-search-results.csv"
        else
            print_status "${YELLOW}" "    ⚠ No PRs found"
        fi
        
        # Clean up temp file
        rm -f "${temp_file}"
        
        # Rate limiting - small delay between requests
        sleep 0.5
        
        return 0
    else
        print_status "${RED}" "    ✗ API error for ${organization} (${branch})"
        rm -f "${temp_file}"
        return 1
    fi
}

# Function to process a single date
process_date() {
    local current_date=$1
    local organizations=$2
    
    print_status "${GREEN}" "[${PROCESSED_DAYS}/${TOTAL_DAYS}] Processing date: ${current_date}"
    
    # Convert organizations string to array
    local org_array=($organizations)
    
    # For each organization, search both main and master branches
    for org in "${org_array[@]}"; do
        search_prs_for_date "${current_date}" "${org}" "main"
        search_prs_for_date "${current_date}" "${org}" "master"
    done
    
    echo
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: bash 30-pr-daily-search.sh [START_DATE] [END_DATE] [--test]

This script searches for merged Pull Requests day by day across multiple
GitHub organizations, checking both 'main' and 'master' branches.

Parameters:
  START_DATE   Start date in YYYY-MM-DD format (default: 2025-01-01)
  END_DATE     End date in YYYY-MM-DD format (default: today)
  --test       Test mode - process only the first 3 days

Input File: 30-pr-daily-search.csv
Format:
  organization
  stone-payments
  pagarme
  stone-ton
  mundipagg
  dlpco

Output File: 30-pr-daily-search-results.csv
Format:
  date,branch,organization,pr_number,pr_title,pr_url,author,merged_at,created_at

Example Output:
  2025-01-15,main,stone-payments,1234,"Fix user authentication","https://github.com/stone-payments/repo/pull/1234","developer1","2025-01-15T10:30:00Z","2025-01-15T09:15:00Z"
  2025-01-15,master,pagarme,5678,"Update payment flow","https://github.com/pagarme/repo/pull/5678","developer2","2025-01-15T14:22:00Z","2025-01-15T13:45:00Z"

Features:
- Day-by-day search to ensure complete coverage
- Searches both 'main' and 'master' branches per organization
- Only merged PRs (is:merged filter)
- Rate limiting to respect GitHub API limits
- Test mode for validation with small datasets
- Progress tracking with colored output

Examples:
  bash 30-pr-daily-search.sh                           # From 2025-01-01 to today
  bash 30-pr-daily-search.sh 2025-01-01 2025-01-31     # January 2025
  bash 30-pr-daily-search.sh 2025-01-01 2025-01-03 --test  # First 3 days, test mode

EOF
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --test)
                TEST_MODE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                print_status "${RED}" "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ "${START_DATE}" == "2025-01-01" ]]; then
                    START_DATE="$1"
                elif [[ -z "${END_DATE}" ]]; then
                    END_DATE="$1"
                else
                    print_status "${RED}" "Too many arguments"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Show execution info
    audit_file
    is_gh_installed
    read_config_file
    
    # Validate dates
    validate_date "${START_DATE}" "start date"
    get_end_date
    validate_date "${END_DATE}" "end date"
    
    # Calculate days to process
    calculate_days
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Create temporary directory
    setup_temp_dir
    
    # Read organizations
    local organizations=$(read_organizations)
    
    print_status "${GREEN}" "Starting daily PR search..."
    if [[ "${TEST_MODE}" == true ]]; then
        print_status "${YELLOW}" "Running in TEST mode"
    fi
    echo
    
    # Initialize output CSV with header
    echo "date,branch,organization,pr_number,pr_title,pr_url,author,merged_at,created_at" > "30-pr-daily-search-results.csv"
    
    # Process each date
    local current_date="${START_DATE}"
    while [[ $(date -d "${current_date}" +%s) -le $(date -d "${END_DATE}" +%s) ]]; do
        PROCESSED_DAYS=$((PROCESSED_DAYS + 1))
        
        process_date "${current_date}" "${organizations}"
        
        # Break if in test mode and processed enough days
        if [[ "${TEST_MODE}" == true && ${PROCESSED_DAYS} -ge 3 ]]; then
            print_status "${YELLOW}" "Test mode limit reached (3 days)"
            break
        fi
        
        # Move to next day
        current_date=$(date -d "${current_date} + 1 day" +%Y-%m-%d)
    done
    
    print_status "${GREEN}" "Processing complete!"
    print_status "${GREEN}" "  Days processed: ${PROCESSED_DAYS}"
    print_status "${GREEN}" "  Output file: 30-pr-daily-search-results.csv"
    
    # Show summary of results
    if [[ -f "30-pr-daily-search-results.csv" ]]; then
        local total_prs=$(tail -n +2 "30-pr-daily-search-results.csv" | wc -l)
        local unique_orgs=$(tail -n +2 "30-pr-daily-search-results.csv" | cut -d',' -f3 | sort | uniq | wc -l)
        local main_prs=$(tail -n +2 "30-pr-daily-search-results.csv" | awk -F',' '$2 == "main"' | wc -l)
        local master_prs=$(tail -n +2 "30-pr-daily-search-results.csv" | awk -F',' '$2 == "master"' | wc -l)
        
        echo
        print_status "${BLUE}" "Results Summary:"
        print_status "${BLUE}" "  📊 Total PRs found: ${total_prs}"
        print_status "${BLUE}" "  🏢 Organizations: ${unique_orgs}"
        print_status "${GREEN}" "  🌟 Main branch PRs: ${main_prs}"
        print_status "${YELLOW}" "  🔄 Master branch PRs: ${master_prs}"
        
        # Show top 5 organizations by PR count
        print_status "${BLUE}" "  🏆 Top 5 organizations by PR count:"
        tail -n +2 "30-pr-daily-search-results.csv" | cut -d',' -f3 | sort | uniq -c | sort -nr | head -5 | while read -r count org; do
            print_status "${GREEN}" "    • ${org}: ${count} PRs"
        done
        
        # Show daily summary
        print_status "${BLUE}" "  📅 Daily PR distribution:"
        tail -n +2 "30-pr-daily-search-results.csv" | cut -d',' -f1 | sort | uniq -c | sort -k2 | head -10 | while read -r count date; do
            print_status "${GREEN}" "    • ${date}: ${count} PRs"
        done
    fi
}

# Run main function with all arguments
main "$@"