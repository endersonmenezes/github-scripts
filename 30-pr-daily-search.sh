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
#   Uses 'gh search prs' for efficient organization-wide search.
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
# Format: date,branch,organization,pr_number,pr_title,pr_url,author,merged_at,created_at,repository
#
# Features:
# - Day-by-day PR search with date range support
# - Searches both 'main' and 'master' branches per organization per day
# - Uses 'gh search prs --merged' for efficient API usage
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
CYAN='\033[0;36m'
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
    done < "30-pr-daily-search.csv"
    
    if [[ ${#organizations[@]} -eq 0 ]]; then
        print_status "${RED}" "No organizations found in 30-pr-daily-search.csv" >&2
        exit 1
    fi
    
    print_status "${GREEN}" "Found ${#organizations[@]} organizations: ${organizations[*]}" >&2
    # Return organizations as space-separated string
    echo "${organizations[*]}"
}

# Function to search PRs for a specific date and organization
search_prs_for_date() {
    local search_date=$1
    local organization=$2
    local branch=$3
    local temp_file="${TEMP_DIR}/prs_${search_date}_${organization}_${branch}.json"
    local all_results_file="${TEMP_DIR}/all_prs_${search_date}_${organization}_${branch}.json"
    local page=1
    local per_page=100
    local total_count=0
    
    print_status "${BLUE}" "  Searching ${organization} (${branch}): ${search_date}"
    
    # Initialize results array
    echo '{"items": []}' > "${all_results_file}"
    
    while true; do
        # Build the search query
        local query="org:${organization}+type:pr+is:merged+merged:${search_date}+base:${branch}"
        local api_url="/search/issues?q=${query}&page=${page}&per_page=${per_page}"
        
        # Make API call using gh api
        if timeout 45 gh api \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "${api_url}" > "${temp_file}" 2>/dev/null; then
            
            # Check for API errors or rate limiting
            if jq -e '.message' "${temp_file}" >/dev/null 2>&1; then
                local error_msg=$(jq -r '.message' "${temp_file}")
                print_status "${RED}" "    ✗ API error: ${error_msg}"
                break
            fi
            
            # Get current page results
            local page_count=$(jq -r '.items | length' "${temp_file}" 2>/dev/null || echo "0")
            
            if [[ "${page_count}" -gt 0 ]]; then
                # Add current page items to all results
                jq -s '.[0].items + .[1].items | {items: .}' "${all_results_file}" "${temp_file}" > "${temp_file}.merged"
                mv "${temp_file}.merged" "${all_results_file}"
                
                total_count=$((total_count + page_count))
                
                # Show progress for multiple pages
                if [[ "${page}" -gt 1 ]]; then
                    print_status "${CYAN}" "    → Page ${page}: +${page_count} PRs (total: ${total_count})"
                fi
                
                # Check if we have more pages
                if [[ "${page_count}" -lt "${per_page}" ]]; then
                    break  # Last page
                fi
                
                page=$((page + 1))
                sleep 1  # Rate limiting between pages
            else
                break  # No results on this page
            fi
        else
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                print_status "${RED}" "    ✗ Timeout on page ${page} for ${organization} (${branch})"
            else
                print_status "${RED}" "    ✗ API error on page ${page} for ${organization} (${branch})"
            fi
            break
        fi
    done
    
    # Process results and show final count
    if [[ "${total_count}" -gt 0 ]]; then
        print_status "${GREEN}" "    ✓ Found ${total_count} PRs"
        
        # Convert to CSV format
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
                .created_at,
                (.html_url | split("/") | "\(.[3])/\(.[4])")
            ] | @csv
        ' "${all_results_file}" >> "30-pr-daily-search-results.csv"
    else
        print_status "${YELLOW}" "    ⚠ No PRs found"
    fi
    
    # Clean up temp files
    rm -f "${temp_file}" "${all_results_file}" "${temp_file}.merged"
    
    # Rate limiting between requests
    sleep 2
    
    return 0
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
  date,branch,organization,pr_number,pr_title,pr_url,author,merged_at,created_at,repository

Example Output:
  2025-01-15,main,stone-payments,1234,"Fix user authentication","https://github.com/stone-payments/repo/pull/1234","developer1","2025-01-15T10:30:00Z","2025-01-15T09:15:00Z","stone-payments/repo"

Features:
- Day-by-day search to ensure complete coverage
- Searches both 'main' and 'master' branches per organization
- Uses 'gh search prs --merged' for efficient API usage
- Rate limiting to respect GitHub API limits
- Test mode for validation with small datasets
- Progress tracking with colored output

Examples:
  bash 30-pr-daily-search.sh                           # From 2025-01-01 to today
  bash 30-pr-daily-search.sh 2025-01-01 2025-01-31     # January 2025
  bash 30-pr-daily-search.sh 2025-01-01 2025-01-03 --test  # First 3 days, test mode

Note: This script uses 'gh search prs' which searches across all repositories
in each organization efficiently, respecting GitHub API rate limits.

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
    echo "date,branch,organization,pr_number,pr_title,pr_url,author,merged_at,created_at,repository" > "30-pr-daily-search-results.csv"
    
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
        
        if [[ ${total_prs} -gt 0 ]]; then
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
        else
            print_status "${YELLOW}" "No PRs found for the specified date range and organizations."
            print_status "${BLUE}" "This could be due to:"
            print_status "${BLUE}" "  • No merged PRs in the date range"
            print_status "${BLUE}" "  • No access to the specified organizations"
            print_status "${BLUE}" "  • API rate limiting or connectivity issues"
        fi
    fi
}

# Run main function with all arguments
main "$@"