#!/bin/bash

# Script: 28-go-dependencies-audit.sh
# Description: Audit Go repositories and extract dependencies and project structure
# Author: Enderson Menezes
# E-mail: mail@enderson.dev
# Created: 2025-08-07
# Updated: 2025-08-07
#
# Usage: bash 28-go-dependencies-audit.sh [organization_name] [--test]
#
# Parameters:
#   organization_name: GitHub organization to audit (required)
#   --test: Test mode - process only first 10 repositories
#
# Output Files:
#   {timestamp}_dependencies_{org}_.csv: Go dependencies extracted from go.mod files
#   {timestamp}_project_{org}_.csv: Project structure analysis
#
# Features:
# - GitHub API with automatic pagination
# - Go.mod dependency parsing
# - Project structure analysis (app, domain, extensions, gateways, proto, protogen, telemetry folders)
# - Latest commit date tracking
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
ORG_NAME=""

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

# Function to parse go.mod dependencies
parse_go_dependencies() {
    local repo_name="$1"
    local org="$2"
    local has_app="$3"
    local has_domain="$4"
    local has_extensions="$5"
    local has_gateways="$6"
    local has_proto="$7"
    local has_protogen="$8"
    local has_telemetry="$9"
    local deps_file="${10}"
    local temp_file="${TEMP_DIR}/go_mod_${PROCESSED_COUNT}.txt"
    
    # Try to get go.mod content with timeout
    if timeout 10s gh api "repos/$org/$repo_name/contents/go.mod" --jq '.content' 2>/dev/null | base64 -d > "$temp_file"; then
        # Parse go.mod for direct dependencies (not indirect)
        local in_require_block=false
        local dep_count=0
        
        while IFS= read -r line; do
            # Remove leading/trailing whitespace
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # Check if we're entering a require block
            if [[ "$line" =~ ^require[[:space:]]*\( ]]; then
                in_require_block=true
                continue
            fi
            
            # Check if we're exiting a require block
            if [[ "$line" =~ ^\) ]] && [[ "$in_require_block" == true ]]; then
                in_require_block=false
                continue
            fi
            
            # Parse single line require or dependency in require block
            if [[ "$line" =~ ^require[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]] || 
               [[ "$in_require_block" == true && "$line" =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
                
                local dependency="${BASH_REMATCH[1]}"
                local version="${BASH_REMATCH[2]}"
                
                # Skip if it contains "// indirect" - this matches the Go code logic
                if [[ ! "$line" =~ "// indirect" ]] && [[ -n "$dependency" ]] && [[ -n "$version" ]]; then
                    echo "$org,$repo_name,$dependency,$version,$has_app,$has_domain,$has_extensions,$has_gateways,$has_proto,$has_protogen,$has_telemetry" >> "$deps_file"
                    dep_count=$((dep_count + 1))
                fi
            fi
        done < "$temp_file"
        
        print_status "${GREEN}" "  📦 Dependencies extracted: $dep_count"
        
        # Clean up temp file
        rm -f "$temp_file"
    fi
}

# Function to check folder structure
check_folder_structure() {
    local repo_name="$1"
    local org="$2"
    
    local has_app="FALSE"
    local has_domain="FALSE"
    local has_extensions="FALSE"
    local has_gateways="FALSE"
    local has_proto="FALSE"
    local has_protogen="FALSE"
    local has_telemetry="FALSE"
    local is_go_project="FALSE"
    
    # Get repository contents with timeout
    local contents
    contents=$(timeout 10s gh api "repos/$org/$repo_name/contents" 2>/dev/null || echo "[]")
    
    # If timeout or error, return default values
    if [[ $? -ne 0 ]] || [[ "$contents" == "[]" ]]; then
        print_status "${YELLOW}" "  ⚠ Timeout or error getting contents for $repo_name"
        echo "FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,"
        return
    fi
    
    # Check for folders and go.mod
    while IFS= read -r item; do
        case "$item" in
            "app") has_app="TRUE" ;;
            "domain") has_domain="TRUE" ;;
            "extensions") has_extensions="TRUE" ;;
            "gateways") has_gateways="TRUE" ;;
            "proto") has_proto="TRUE" ;;
            "protogen") has_protogen="TRUE" ;;
            "telemetry") has_telemetry="TRUE" ;;
            "go.mod") is_go_project="TRUE" ;;
        esac
    done < <(echo "$contents" | jq -r '.[] | select(.type == "dir" or .name == "go.mod") | .name' 2>/dev/null || echo "")
    
    # Get latest commit date with timeout
    local latest_commit=""
    local commit_data
    commit_data=$(timeout 10s gh api "repos/$org/$repo_name/commits" --jq '.[0].commit.author.date' 2>/dev/null || echo "")
    if [[ -n "$commit_data" ]] && [[ $? -eq 0 ]]; then
        latest_commit=$(date -d "$commit_data" +%Y-%m-%d 2>/dev/null || echo "$commit_data")
    fi
    
    echo "$is_go_project,$has_app,$has_domain,$has_extensions,$has_gateways,$has_proto,$has_protogen,$has_telemetry,$latest_commit"
}

# Function to process a single repository
process_repository() {
    local repo_name="$1"
    local org="$2"
    local deps_file="$3"
    local proj_file="$4"
    
    print_status "${BLUE}" "[$((PROCESSED_COUNT + 1))/${TOTAL_COUNT}] Processing Repository: $repo_name"
    
    # Add timestamp for debugging timeouts
    local start_time=$(date +%s)
    
    # Check folder structure and if it's a Go project
    print_status "${BLUE}" "  📁 Checking folder structure..."
    local folder_info
    folder_info=$(check_folder_structure "$repo_name" "$org")
    
    # Extract values from folder_info
    IFS=',' read -r is_go_project has_app has_domain has_extensions has_gateways has_proto has_protogen has_telemetry latest_commit <<< "$folder_info"
    
    # Write project info
    echo "$org,$repo_name,$is_go_project,$has_app,$has_domain,$has_extensions,$has_gateways,$has_proto,$has_protogen,$has_telemetry,$latest_commit" >> "$proj_file"
    
    # If it's a Go project, get dependencies
    if [[ "$is_go_project" == "TRUE" ]]; then
        print_status "${GREEN}" "  ✓ Go project detected, extracting dependencies..."
        parse_go_dependencies "$repo_name" "$org" "$has_app" "$has_domain" "$has_extensions" "$has_gateways" "$has_proto" "$has_protogen" "$has_telemetry" "$deps_file"
    else
        print_status "${YELLOW}" "  ⚠ Not a Go project (no go.mod found)"
    fi
    
    # Show processing time for debugging
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    print_status "${BLUE}" "  ⏱ Processed in ${duration}s"
    
    # Rate limiting - increased delay to prevent timeouts
    sleep 0.5
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: bash 28-go-dependencies-audit.sh <organization_name> [--test]

This script audits Go repositories in a GitHub organization and extracts:
- Go dependencies from go.mod files
- Project structure analysis (specific folders)
- Latest commit dates
- Excludes archived repositories automatically

Parameters:
  organization_name    GitHub organization to audit (required)
  --test              Test mode - process only the first 10 repositories

Output Files:
  {timestamp}_dependencies_{org}_.csv: Dependencies with project structure info
  {timestamp}_project_{org}_.csv: Project analysis with folder structure

Dependencies CSV Format:
  Organization,Repository,Dependency,Version,app folder,domain folder,extensions folder,gateways folder,proto folder,protogen folder,telemetry folder

Project CSV Format:
  Organization,Repository,go project,app folder,domain folder,extensions folder,gateways folder,proto folder,protogen folder,telemetry folder,latest commit

Analyzed Folders:
  - app: Application layer
  - domain: Domain logic
  - extensions: Extensions/plugins
  - gateways: External integrations
  - proto: Protocol buffer definitions
  - protogen: Generated protocol files
  - telemetry: Observability/monitoring

Examples:
  bash 28-go-dependencies-audit.sh stone-payments
  bash 28-go-dependencies-audit.sh dlpco --test

Features:
- Uses GitHub Search API for efficient repository discovery
- Automatic pagination for large organizations
- Direct dependency extraction (excludes indirect dependencies)
- Project structure pattern analysis
- Excludes archived repositories automatically
- Test mode for safe validation
- Comprehensive error handling
- Progress tracking with colored output

Note: Requires GitHub CLI (gh) to be installed and authenticated.

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
                if [[ -z "$ORG_NAME" ]]; then
                    ORG_NAME="$1"
                else
                    print_status "${RED}" "Unknown option: $1"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check if organization name is provided
    if [[ -z "$ORG_NAME" ]]; then
        print_status "${RED}" "Please provide the organization name as a command-line argument."
        show_usage
        exit 1
    fi
    
    # Show execution info
    audit_file
    is_gh_installed
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Create temporary directory
    setup_temp_dir
    
    # Create output files with timestamp
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local deps_file="${timestamp}_dependencies_${ORG_NAME}_.csv"
    local proj_file="${timestamp}_project_${ORG_NAME}_.csv"
    
    # Create CSV headers
    echo "Organization,Repository,Dependency,Version,app folder,domain folder,extensions folder,gateways folder,proto folder,protogen folder,telemetry folder" > "$deps_file"
    echo "Organization,Repository,go project,app folder,domain folder,extensions folder,gateways folder,proto folder,protogen folder,telemetry folder,latest commit" > "$proj_file"
    
    print_status "${GREEN}" "Starting Go dependencies audit for organization: $ORG_NAME"
    if [[ "$TEST_MODE" == true ]]; then
        print_status "${YELLOW}" "Running in TEST mode - processing first 10 repositories only"
    fi
    
    print_status "${BLUE}" "Output files created:"
    print_status "${BLUE}" "  Dependencies: $deps_file"
    print_status "${BLUE}" "  Projects: $proj_file"
    echo
    
    # Get all repositories for the organization using Search API (much more efficient)
    print_status "${BLUE}" "Fetching repository list using GitHub Search API..."
    local page=1
    local per_page=50  # Reduced per_page for faster initial response
    local total_repos=0
    local all_repos_file="${TEMP_DIR}/all_repositories.txt"
    
    # Initialize empty file
    touch "$all_repos_file"
    
    # In test mode, limit to fewer pages
    local max_pages=999
    if [[ "$TEST_MODE" == true ]]; then
        max_pages=2  # Only fetch 2 pages in test mode (100 repos max)
        print_status "${YELLOW}" "Test mode: limiting to $max_pages pages"
    fi
    
    # Use GitHub Search API to get non-archived repositories directly
    # This is much more efficient than filtering from org/repos endpoint
    while true; do
        local api_response
        # URL encode the search query (replace spaces with +)
        local search_query="org:$ORG_NAME+archived:false"
        
        # Use GitHub Search API for repositories
        api_response=$(gh api "search/repositories?q=${search_query}&per_page=$per_page&page=$page&sort=updated&order=desc" 2>/dev/null)
        
        # Check if API call was successful
        if [[ $? -ne 0 ]] || [[ -z "$api_response" ]]; then
            print_status "${RED}" "Error: Failed to fetch repositories from GitHub Search API"
            print_status "${RED}" "Make sure you have proper access to the organization: $ORG_NAME"
            exit 1
        fi
        
        # Check if response contains an error message
        if echo "$api_response" | jq -e '.message' >/dev/null 2>&1; then
            local error_msg
            error_msg=$(echo "$api_response" | jq -r '.message')
            print_status "${RED}" "GitHub API Error: $error_msg"
            if echo "$api_response" | jq -e '.documentation_url' >/dev/null 2>&1; then
                local doc_url
                doc_url=$(echo "$api_response" | jq -r '.documentation_url')
                print_status "${RED}" "Documentation: $doc_url"
            fi
            exit 1
        fi
        
        # Extract repository names from search results
        local repos
        repos=$(echo "$api_response" | jq -r '.items[].name' 2>/dev/null || echo "")
        
        # Get total count and current page info
        local total_count
        total_count=$(echo "$api_response" | jq -r '.total_count' 2>/dev/null || echo "0")
        local items_on_page
        items_on_page=$(echo "$api_response" | jq -r '.items | length' 2>/dev/null || echo "0")
        
        if [[ -z "$repos" ]] || [[ $items_on_page -eq 0 ]]; then
            break
        fi
        
        local repo_count
        repo_count=$(echo "$repos" | grep -c '^' || echo "0")
        
        if [[ $repo_count -gt 0 ]]; then
            # Append repos to file
            echo "$repos" >> "$all_repos_file"
            total_repos=$((total_repos + repo_count))
        fi
        
        print_status "${BLUE}" "  Fetched page $page ($repo_count repositories - total: $total_repos/$total_count active repos)"
        
        # If we got less than per_page results, we're done
        if [[ $items_on_page -lt $per_page ]]; then
            break
        fi
        
        # Break early in test mode
        if [[ "$TEST_MODE" == true && $page -ge $max_pages ]]; then
            print_status "${YELLOW}" "Test mode: reached page limit ($max_pages pages)"
            break
        fi
        
        page=$((page + 1))
        
        # Rate limiting for Search API (more restrictive to avoid timeouts)
        sleep 0.5
    done
    
    # Set total count
    TOTAL_COUNT=$total_repos
    if [[ "$TEST_MODE" == true && $TOTAL_COUNT -gt 10 ]]; then
        TOTAL_COUNT=10
        print_status "${YELLOW}" "Test mode enabled - limiting to first 10 repositories"
    fi
    
    print_status "${GREEN}" "Found $total_repos active repositories via Search API, processing $TOTAL_COUNT"
    echo
    
    # Process each repository
    while IFS= read -r repo_name; do
        if [[ -n "$repo_name" ]]; then
            process_repository "$repo_name" "$ORG_NAME" "$deps_file" "$proj_file"
            PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
            
            # Break if in test mode and processed 10 repositories
            if [[ "$TEST_MODE" == true && $PROCESSED_COUNT -ge 10 ]]; then
                print_status "${YELLOW}" "Test mode limit reached (10 repositories)"
                break
            fi
        fi
    done < "$all_repos_file"
    
    echo
    print_status "${GREEN}" "Audit complete!"
    print_status "${GREEN}" "  Repositories processed: $PROCESSED_COUNT"
    print_status "${GREEN}" "  Output files:"
    print_status "${GREEN}" "    Dependencies: $deps_file"
    print_status "${GREEN}" "    Projects: $proj_file"
    
    # Show summary of results
    if [[ -f "$proj_file" ]]; then
        local total_projects=$(tail -n +2 "$proj_file" | wc -l)
        local go_projects=$(tail -n +2 "$proj_file" | awk -F',' '$3 == "TRUE"' | wc -l)
        local non_go_projects=$(tail -n +2 "$proj_file" | awk -F',' '$3 == "FALSE"' | wc -l)
        
        echo
        print_status "${BLUE}" "Results Summary:"
        print_status "${BLUE}" "  📊 Total repositories analyzed: $total_projects"
        print_status "${GREEN}" "  🟢 Go projects: $go_projects"
        print_status "${YELLOW}" "  🟡 Non-Go projects: $non_go_projects"
        
        if [[ -f "$deps_file" ]]; then
            local total_deps=$(tail -n +2 "$deps_file" | wc -l)
            print_status "${BLUE}" "  📦 Total dependencies extracted: $total_deps"
        fi
        
        # Show folder structure analysis
        print_status "${BLUE}" "  📁 Project Structure Analysis:"
        local has_app=$(tail -n +2 "$proj_file" | awk -F',' '$4 == "TRUE"' | wc -l)
        local has_domain=$(tail -n +2 "$proj_file" | awk -F',' '$5 == "TRUE"' | wc -l)
        local has_extensions=$(tail -n +2 "$proj_file" | awk -F',' '$6 == "TRUE"' | wc -l)
        local has_gateways=$(tail -n +2 "$proj_file" | awk -F',' '$7 == "TRUE"' | wc -l)
        local has_proto=$(tail -n +2 "$proj_file" | awk -F',' '$8 == "TRUE"' | wc -l)
        local has_protogen=$(tail -n +2 "$proj_file" | awk -F',' '$9 == "TRUE"' | wc -l)
        local has_telemetry=$(tail -n +2 "$proj_file" | awk -F',' '$10 == "TRUE"' | wc -l)
        
        print_status "${BLUE}" "    • app folder: $has_app projects"
        print_status "${BLUE}" "    • domain folder: $has_domain projects"
        print_status "${BLUE}" "    • extensions folder: $has_extensions projects"
        print_status "${BLUE}" "    • gateways folder: $has_gateways projects"
        print_status "${BLUE}" "    • proto folder: $has_proto projects"
        print_status "${BLUE}" "    • protogen folder: $has_protogen projects"
        print_status "${BLUE}" "    • telemetry folder: $has_telemetry projects"
    fi
}

# Run main function
main "$@"
