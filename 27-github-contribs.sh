#!/bin/bash

# Script: 27-github-contribs.sh
# Description: Collect GitHub repository contributors statistics
# Author: Enderson Menezes
# E-mail: mail@enderson.dev
# Created: 2025-07-24
# Updated: 2025-07-24
#
# Usage: bash 27-github-contribs.sh [--test]
#
# Parameters:
#   --test: Test mode - process only first 10 repositories
#
# CSV Input: 27-github-contribs.csv
# Format: reporsitory (sic)
#
# CSV Output: 27-completed.csv
# Format: repo,total_contribs,contribs
# Fields:
#   repo: Repository name (owner/repo)
#   total_contribs: Total number of contributions across all contributors
#   contribs: Contributors in format "user:contributions;user:contributions"
#
# Features:
# - GitHub API with automatic pagination
# - Test mode for validation
# - Comprehensive error handling
# - Progress tracking

set -euo pipefail

# Import shared functions
source ./functions.sh

# Global variables
TEST_MODE=false
TEMP_DIR=""
PROCESSED_COUNT=0
TOTAL_COUNT=0

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

# Function to count total repositories
count_repositories() {
    # Count lines excluding header
    TOTAL_COUNT=$(tail -n +2 "27-github-contribs.csv" | wc -l)
    print_status "${BLUE}" "Found ${TOTAL_COUNT} repositories to process"
    
    if [[ "${TEST_MODE}" == true ]]; then
        TOTAL_COUNT=$(( TOTAL_COUNT > 10 ? 10 : TOTAL_COUNT ))
        print_status "${YELLOW}" "Test mode enabled - processing first ${TOTAL_COUNT} repositories"
    fi
}

# Function to get contributors for a repository
get_contributors() {
    local repo=$1
    local temp_file="${TEMP_DIR}/contributors_${PROCESSED_COUNT}.json"
    
    print_status "${BLUE}" "[$((PROCESSED_COUNT + 1))/${TOTAL_COUNT}] Processing: ${repo}"
    
    # Call GitHub API with pagination - using /contributors endpoint (more reliable)
    if gh api \
        --paginate \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/${repo}/contributors" > "${temp_file}" 2>/dev/null; then
        
        # Check if the file contains valid JSON and has data
        if jq -e '. | length > 0' "${temp_file}" >/dev/null 2>&1; then
            # Process the response and calculate totals
            local total_contribs=0
            local contribs_list=""
            
            # Parse each contributor
            while IFS= read -r contributor; do
                local login=$(echo "${contributor}" | jq -r '.login // "unknown"')
                local contributions=$(echo "${contributor}" | jq -r '.contributions // 0')
                
                total_contribs=$((total_contribs + contributions))
                
                if [[ -n "${contribs_list}" ]]; then
                    contribs_list="${contribs_list};${login}:${contributions}"
                else
                    contribs_list="${login}:${contributions}"
                fi
            done < <(jq -c '.[]' "${temp_file}")
            
            # Write to output CSV
            echo "${repo},${total_contribs},\"${contribs_list}\"" >> "27-completed.csv"
            print_status "${GREEN}" "  ✓ Contributors: $(echo "${contribs_list}" | tr ';' '\n' | wc -l), Total contributions: ${total_contribs}"
            
        else
            # Empty response or no contributors
            print_status "${YELLOW}" "  ⚠ No contributors data available"
            echo "${repo},0,\"\"" >> "27-completed.csv"
        fi
        
        # Clean up temp file
        rm -f "${temp_file}"
        
    else
        # API call failed
        print_status "${RED}" "  ✗ Failed to fetch contributors (API error or access denied)"
        echo "${repo},0,\"\"" >> "27-completed.csv"
    fi
    
    # Rate limiting - small delay between requests
    sleep 0.5
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: bash 27-github-contribs.sh [--test]

This script collects GitHub repository contributors statistics using the GitHub CLI.

Parameters:
  --test       Test mode - process only the first 10 repositories

Input File: 27-github-contribs.csv
Format:
  reporsitory
  owner/repo1
  owner/repo2
  ...

Output File: 27-completed.csv
Format:
  repo,total_contribs,contribs
  
Fields:
  - repo: Repository name (owner/repo format)
  - total_contribs: Sum of all contributions from all contributors
  - contribs: Contributors formatted as "user:contributions;user:contributions"

Example Output:
  stone-payments/example-repo,245,"user1:120;user2:89;user3:36"
  dlpco/another-repo,89,"developer1:50;developer2:39"

The script uses the GitHub API endpoint:
  /repos/OWNER/REPO/contributors

Features:
- Automatic pagination using --paginate flag
- Rate limiting to respect GitHub API limits
- Test mode for validation with small datasets
- Comprehensive error handling for private/inaccessible repositories
- Progress tracking with colored output

Note: The script uses the /contributors endpoint which provides the total
number of commits per contributor. This is more reliable than /stats/contributors
which may return empty results if statistics are still being computed.

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
            *)
                print_status "${RED}" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Show execution info
    audit_file
    is_gh_installed
    read_config_file
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Create temporary directory
    setup_temp_dir
    
    # Count total repositories
    count_repositories
    
    print_status "${GREEN}" "Starting GitHub contributors collection..."
    if [[ "${TEST_MODE}" == true ]]; then
        print_status "${YELLOW}" "Running in TEST mode - processing first 10 repositories only"
    fi
    echo
    
    # Initialize output CSV with header
    echo "repo,total_contribs,contribs" > "27-completed.csv"
    
    # Process each repository
    local line_number=0
    while IFS= read -r repository; do
        line_number=$((line_number + 1))
        
        # Skip header line
        [[ ${line_number} -eq 1 ]] && continue
        
        # Skip empty lines
        [[ -z "${repository}" ]] && continue
        
        # Clean repository name (remove quotes if present)
        repository=$(echo "${repository}" | sed 's/^"//;s/"$//;s/^'\''//;s/'\''$//')
        
        # Process repository
        get_contributors "${repository}"
        
        PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
        
        # Break if in test mode and processed 10 repositories
        if [[ "${TEST_MODE}" == true && ${PROCESSED_COUNT} -ge 10 ]]; then
            print_status "${YELLOW}" "Test mode limit reached (10 repositories)"
            break
        fi
        
        echo
        
    done < "27-github-contribs.csv"
    
    print_status "${GREEN}" "Processing complete!"
    print_status "${GREEN}" "  Repositories processed: ${PROCESSED_COUNT}"
    print_status "${GREEN}" "  Output file: 27-completed.csv"
    
    # Show summary of results
    if [[ -f "27-completed.csv" ]]; then
        local total_repos=$(tail -n +2 "27-completed.csv" | wc -l)
        local repos_with_contribs=$(tail -n +2 "27-completed.csv" | awk -F',' '$2 > 0' | wc -l)
        local repos_without_contribs=$(tail -n +2 "27-completed.csv" | awk -F',' '$2 == 0' | wc -l)
        
        echo
        print_status "${BLUE}" "Results Summary:"
        print_status "${BLUE}" "  📊 Total repositories: ${total_repos}"
        print_status "${GREEN}" "  ✅ With contributors: ${repos_with_contribs}"
        print_status "${YELLOW}" "  ⚠️  Without contributors: ${repos_without_contribs}"
        
        # Show top 5 repositories by total contributions
        print_status "${BLUE}" "  🏆 Top 5 repositories by contributions:"
        tail -n +2 "27-completed.csv" | sort -t',' -k2 -nr | head -5 | while IFS=',' read -r repo total_contribs contribs; do
            print_status "${GREEN}" "    • ${repo}: ${total_contribs} contributions"
        done
    fi
}

# Run main function
main "$@"
