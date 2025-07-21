#!/bin/bash

# Script: 26-search-and-replace.sh
# Description: Search for code patterns across GitHub repositories and apply regex replacements
# Author: Enderson Menezes
# E-mail: mail@enderson.dev
# Created: 2025-07-21
# Updated: 2025-07-21
#
# Usage: bash 26-search-and-replace.sh [--dry-run] [--debug]
#
# Parameters:
#   --dry-run: Show what would be changed without actually making changes
#   --debug: Enable debug output
#
# CSV Format: query,search_pattern,replace_pattern,file_pattern,commit_message
#
# Column Details:
#   query: GitHub search query without quotes (e.g., "org:stone-payments spot path:.github")
#   search_pattern: Regex pattern with capture groups (e.g., "runs-on: (.+)-spot")
#   replace_pattern: Replacement with group references (e.g., "runs-on: \1")
#   file_pattern: File patterns separated by semicolons (e.g., "*.yml;*.yaml")
#   commit_message: Commit message and PR title
#
# Example CSV entries:
#   org:stone-payments spot path:.github,"runs-on: (.+)-spot","runs-on: \1","*.yml;*.yaml","Remove -spot from runners"
#   repo:owner/name python-version,"python-version: '3.8'","python-version: '3.11'","*.py;*.yml","Update Python version"
#
# Features:
# - GitHub API search with pagination
# - Regex-based search and replace
# - Automatic pull request creation
# - Dry-run mode for safe testing
# - Debug mode with detailed output
# - Support for multiple file patterns
# - Capture group references in replacements

set -euo pipefail

# Import shared functions
source ./functions.sh

# Global variables
DRY_RUN=false
DEBUG=false
TEMP_DIR=""
RESULTS_DIR=""

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

# Function to print debug messages
debug() {
    if [[ "${DEBUG}" == true ]]; then
        print_status "${BLUE}" "[DEBUG] $1"
    fi
}

# Function to create temporary directories
setup_temp_dirs() {
    TEMP_DIR=$(mktemp -d)
    RESULTS_DIR="${TEMP_DIR}/results"
    mkdir -p "${RESULTS_DIR}"
    
    print_status "${GREEN}" "Created temporary directory: ${TEMP_DIR}"
    debug "Results directory: ${RESULTS_DIR}"
}

# Function to cleanup temporary directories
cleanup() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        print_status "${YELLOW}" "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi
}

# Function to search for code using GitHub CLI API
search_code() {
    local query=$1
    local output_file="${RESULTS_DIR}/search_results.json"
    local all_results_file="${RESULTS_DIR}/all_search_results.json"
    
    print_status "${BLUE}" "Searching for code with query: ${query}"
    
    # URL encode the query more carefully
    # Use python for proper URL encoding
    local encoded_query=$(printf '%s' "${query}" | python3 -c "import urllib.parse; import sys; print(urllib.parse.quote_plus(sys.stdin.read().strip()), end='')")
    
    debug "Encoded query: ${encoded_query}"
    
    # Initialize empty results
    echo '{"total_count": 0, "items": []}' > "${all_results_file}"
    
    local page=1
    local per_page=100
    local total_items=0
    local fetched_items=0
    
    # Fetch all pages
    while true; do
        debug "Fetching page ${page}..."
        
        local page_file="${RESULTS_DIR}/page_${page}.json"
        
        # Use gh api to search for code matches
        if gh api \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "/search/code?q=${encoded_query}&per_page=${per_page}&page=${page}" > "${page_file}" 2>/dev/null; then
            
            # Check if this page has results
            local page_items=$(jq '.items | length' "${page_file}" 2>/dev/null || echo "0")
            local page_total=$(jq '.total_count // 0' "${page_file}" 2>/dev/null || echo "0")
            
            if [[ "${page_items}" -eq 0 ]]; then
                debug "No more results on page ${page}"
                rm -f "${page_file}"
                break
            fi
            
            debug "Page ${page}: ${page_items} items"
            fetched_items=$((fetched_items + page_items))
            total_items="${page_total}"
            
            # Merge results
            if [[ "${page}" -eq 1 ]]; then
                cp "${page_file}" "${all_results_file}"
            else
                # Merge items from this page into all_results_file
                jq -s '.[0].items + .[1].items as $combined | .[0] | .items = $combined' "${all_results_file}" "${page_file}" > "${RESULTS_DIR}/temp.json"
                mv "${RESULTS_DIR}/temp.json" "${all_results_file}"
            fi
            
            rm -f "${page_file}"
            
            # If we got fewer items than requested, we're done
            if [[ "${page_items}" -lt "${per_page}" ]]; then
                debug "Last page reached (${page_items} < ${per_page})"
                break
            fi
            
            page=$((page + 1))
            
            # GitHub API rate limiting - small delay between requests
            sleep 0.5
            
        else
            if [[ "${page}" -eq 1 ]]; then
                print_status "${RED}" "Search failed or no results found"
                echo '{"total_count": 0, "items": []}' > "${all_results_file}"
            fi
            break
        fi
        
        # Safety check to avoid infinite loops
        if [[ "${page}" -gt 10 ]]; then
            print_status "${YELLOW}" "Reached maximum page limit (10 pages)"
            break
        fi
    done
    
    # Use the combined results
    cp "${all_results_file}" "${output_file}"
    
    debug "Search completed successfully, results saved to ${output_file}"
    debug "Total items across all pages: ${fetched_items}/${total_items}"
    
    # Extract unique repositories from the API response
    jq -r '.items[]? | .repository.full_name' "${output_file}" | sort | uniq > "${RESULTS_DIR}/repositories.txt"
    
    local repo_count=$(wc -l < "${RESULTS_DIR}/repositories.txt")
    print_status "${GREEN}" "Found ${repo_count} repositories with matches (${fetched_items} total code matches)"
    
    # Also save the detailed results for reference
    jq -r '.items[]? | "\(.repository.full_name),\(.path),\(.html_url)"' "${output_file}" > "${RESULTS_DIR}/detailed_results.csv"
    
    debug "Repositories found:"
    if [[ "${DEBUG}" == true ]]; then
        cat "${RESULTS_DIR}/repositories.txt"
    fi
    
    debug "Files found with matches:"
    if [[ "${DEBUG}" == true ]]; then
        jq -r '.items[]? | "\(.repository.full_name): \(.path)"' "${output_file}"
    fi
    
    debug "Total items found:"
    if [[ "${DEBUG}" == true ]]; then
        echo "${fetched_items}"
    fi
}

# Function to clone a repository
clone_repository() {
    local repo=$1
    local clone_dir="${TEMP_DIR}/repos/${repo}"
    
    debug "Cloning repository: ${repo} to ${clone_dir}" >&2
    
    mkdir -p "$(dirname "${clone_dir}")"
    
    debug "Attempting to clone with gh repo clone command..." >&2
    if gh repo clone "${repo}" "${clone_dir}" -- --depth 1 >&2 2>&1; then
        debug "Successfully cloned ${repo}" >&2
        debug "Repository contents: $(ls -la "${clone_dir}" 2>/dev/null || echo 'Failed to list contents')" >&2
        echo "${clone_dir}"
        return 0
    else
        print_status "${RED}" "Failed to clone ${repo}"
        debug "Clone error for ${repo} - checking if we have access..." >&2
        gh repo view "${repo}" --json name 2>/dev/null || debug "No access to repository ${repo}" >&2
        return 1
    fi
}

# Function to find and replace in files
find_and_replace() {
    local repo_dir=$1
    local search_pattern=$2
    local replace_pattern=$3
    local file_pattern=$4
    local repo_name=$5
    
    debug "Searching in ${repo_name} for pattern: ${search_pattern}"
    
    local changed_files=()
    local total_changes=0
    
    # Convert semicolon-separated file patterns to array
    IFS=';' read -ra PATTERNS <<< "${file_pattern}"
    
    # Find files matching the patterns
    local find_args=()
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "${pattern}" | xargs) # trim whitespace
        if [[ ${#find_args[@]} -gt 0 ]]; then
            find_args+=("-o")
        fi
        find_args+=("-name" "${pattern}")
    done
    
    debug "Looking for files in ${repo_dir} with patterns: ${PATTERNS[*]}"
    
    # Use find to locate files and apply regex
    debug "Find command: find \"${repo_dir}\" \\( ${find_args[*]} \\) -type f"
    
    while IFS= read -r -d '' file; do
        debug "Checking file: ${file}"
        if [[ -f "${file}" ]]; then
            # Check if file contains the pattern
            if grep -qE "${search_pattern}" "${file}"; then
                debug "Found pattern in file: ${file}"
                
                if [[ "${DRY_RUN}" == true ]]; then
                    local relative_file="${file#${repo_dir}/}"
                    print_status "${YELLOW}" "[DRY-RUN] No arquivo ${relative_file} do repo ${repo_name} faremos as seguintes edições:"
                    echo ""
                    while IFS= read -r line_info; do
                        local line_num=$(echo "${line_info}" | cut -d: -f1)
                        local line_content=$(echo "${line_info}" | cut -d: -f2-)
                        local new_content=$(echo "${line_content}" | sed -E "s/${search_pattern}/${replace_pattern}/g")
                        echo "  Linha ${line_num}:"
                        echo "    Linha original:   ${line_content}"
                        echo "    Linha modificada: ${new_content}"
                        echo ""
                    done < <(grep -nE "${search_pattern}" "${file}")
                else
                    # Create backup
                    cp "${file}" "${file}.bak"
                    
                    # Apply replacement using sed with extended regex
                    if sed -E "s/${search_pattern}/${replace_pattern}/g" "${file}.bak" > "${file}"; then
                        # Check if file actually changed
                        if ! cmp -s "${file}" "${file}.bak"; then
                            changed_files+=("${file}")
                            local file_changes=$(diff -U 0 "${file}.bak" "${file}" | grep -E '^[-+]' | grep -v '^[-+][-+][-+]' | wc -l)
                            total_changes=$((total_changes + file_changes))
                            print_status "${GREEN}" "Changed file: ${file} (${file_changes} changes)"
                        fi
                    else
                        print_status "${RED}" "Failed to apply replacement in ${file}"
                        mv "${file}.bak" "${file}" # restore original
                    fi
                    
                    # Remove backup
                    rm -f "${file}.bak"
                fi
            fi
        fi
    done < <(find "${repo_dir}" \( "${find_args[@]}" \) -type f -print0)
    
    if [[ ${#changed_files[@]} -gt 0 ]]; then
        print_status "${GREEN}" "Repository ${repo_name}: ${#changed_files[@]} files changed, ${total_changes} total changes"
        return 0
    else
        debug "No changes made in repository ${repo_name}"
        return 1
    fi
}

# Function to create pull request
create_pull_request() {
    local repo_dir=$1
    local repo_name=$2
    local commit_message=$3
    local search_pattern=$4
    local replace_pattern=$5
    local branch_name="search-and-replace-$(date +%Y%m%d-%H%M%S)"
    
    if [[ "${DRY_RUN}" == true ]]; then
        print_status "${YELLOW}" "[DRY-RUN] Would create PR in ${repo_name} with message: ${commit_message}"
        return 0
    fi
    
    cd "${repo_dir}"
    
    # Configure git if needed
    if ! git config user.email >/dev/null 2>&1; then
        git config user.email "automation@enderson.dev"
        git config user.name "GitHub Scripts Automation"
    fi
    
    # Create and switch to new branch
    git checkout -b "${branch_name}"
    
    # Add all changed files
    git add .
    
    # Check if there are changes to commit
    if git diff --cached --quiet; then
        print_status "${YELLOW}" "No changes to commit in ${repo_name}"
        return 1
    fi
    
    # Count the changes for the PR description
    local files_changed=$(git diff --cached --name-only | wc -l)
    local lines_changed=$(git diff --cached --numstat | awk '{added+=$1; deleted+=$2} END {print added+deleted}')
    
    # Create detailed PR body
    local pr_body="## Automated Search and Replace
    
This PR was generated automatically by the search-and-replace script.

### Changes Made
- **Search Pattern**: \`${search_pattern}\`
- **Replace Pattern**: \`${replace_pattern}\`
- **Files Changed**: ${files_changed}
- **Lines Modified**: ${lines_changed}

### Files Modified
\`\`\`
$(git diff --cached --name-only)
\`\`\`

### Preview of Changes
\`\`\`diff
$(git diff --cached | head -20)
\`\`\`

---
*This PR was created automatically. Please review the changes before merging.*"
    
    # Commit changes
    git commit -m "${commit_message}"
    
    # Push branch
    if git push origin "${branch_name}" >/dev/null 2>&1; then
        # Create pull request with detailed description
        local pr_url
        if pr_url=$(gh pr create \
            --title "${commit_message}" \
            --body "${pr_body}" \
            --head "${branch_name}" \
            --base main 2>/dev/null); then
            print_status "${GREEN}" "Created PR for ${repo_name}: ${pr_url}"
        elif pr_url=$(gh pr create \
            --title "${commit_message}" \
            --body "${pr_body}" \
            --head "${branch_name}" \
            --base master 2>/dev/null); then
            print_status "${GREEN}" "Created PR for ${repo_name}: ${pr_url}"
        else
            print_status "${RED}" "Failed to create PR for ${repo_name}"
            return 1
        fi
        
        # Save to results files
        echo "${repo_name},${pr_url}" >> "${RESULTS_DIR}/pull_requests.csv"
        echo "${repo_name}: ${pr_url}" >> "${RESULTS_DIR}/pull_requests.txt"
        
        return 0
    else
        print_status "${RED}" "Failed to push branch for ${repo_name}"
        return 1
    fi
}

# Function to process a single configuration
process_config() {
    local query=$1
    local search_pattern=$2
    local replace_pattern=$3
    local file_pattern=$4
    local commit_message=$5
    
    print_status "${BLUE}" "Processing configuration:"
    print_status "${BLUE}" "  Query: ${query}"
    print_status "${BLUE}" "  Search: ${search_pattern}"
    print_status "${BLUE}" "  Replace: ${replace_pattern}"
    print_status "${BLUE}" "  Files: ${file_pattern}"
    print_status "${BLUE}" "  Commit: ${commit_message}"
    echo
    
    # Search for code
    search_code "${query}"
    
    # Initialize results file
    echo "repository,status,changes" > "${RESULTS_DIR}/processing_results.csv"
    echo "repository,pr_url" > "${RESULTS_DIR}/pull_requests.csv"
    echo "# Pull Requests Created by Search and Replace Script" > "${RESULTS_DIR}/pull_requests.txt"
    echo "# Generated on: $(date)" >> "${RESULTS_DIR}/pull_requests.txt"
    echo "# Query: ${query}" >> "${RESULTS_DIR}/pull_requests.txt"
    echo "# Search: ${search_pattern}" >> "${RESULTS_DIR}/pull_requests.txt"
    echo "# Replace: ${replace_pattern}" >> "${RESULTS_DIR}/pull_requests.txt"
    echo "" >> "${RESULTS_DIR}/pull_requests.txt"
    
    local processed=0
    local successful=0
    
    # Process each repository
    while IFS= read -r repo; do
        [[ -z "${repo}" ]] && continue
        
        processed=$((processed + 1))
        print_status "${BLUE}" "Processing repository ${processed}: ${repo}"
        
        debug "About to clone repository: ${repo}"
        
        # Clone repository
        local repo_dir
        if repo_dir=$(clone_repository "${repo}"); then
            debug "Repository cloned successfully to: ${repo_dir}"
            # Apply find and replace
            if find_and_replace "${repo_dir}" "${search_pattern}" "${replace_pattern}" "${file_pattern}" "${repo}"; then
                # Create pull request if not dry run
                if create_pull_request "${repo_dir}" "${repo}" "${commit_message}" "${search_pattern}" "${replace_pattern}"; then
                    echo "${repo},success,yes" >> "${RESULTS_DIR}/processing_results.csv"
                    successful=$((successful + 1))
                else
                    echo "${repo},pr_failed,yes" >> "${RESULTS_DIR}/processing_results.csv"
                fi
            else
                echo "${repo},no_changes,no" >> "${RESULTS_DIR}/processing_results.csv"
            fi
        else
            echo "${repo},clone_failed,no" >> "${RESULTS_DIR}/processing_results.csv"
        fi
        
        echo
    done < "${RESULTS_DIR}/repositories.txt"
    
    print_status "${GREEN}" "Processing complete!"
    print_status "${GREEN}" "  Repositories processed: ${processed}"
    print_status "${GREEN}" "  Successful changes: ${successful}"
    
    # Copy results to current directory with timestamp
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local output_file="search-and-replace-results-${timestamp}.txt"
    
    if [[ -f "${RESULTS_DIR}/pull_requests.txt" ]] && [[ $(wc -l < "${RESULTS_DIR}/pull_requests.txt") -gt 6 ]]; then
        cp "${RESULTS_DIR}/pull_requests.txt" "${output_file}"
        cp "${RESULTS_DIR}/processing_results.csv" "search-and-replace-processing-${timestamp}.csv"
        
        print_status "${GREEN}" "Pull requests created:"
        cat "${RESULTS_DIR}/pull_requests.txt" | grep -E "^[^#]" | grep -v "^$"
        echo
        print_status "${GREEN}" "Results saved to:"
        print_status "${GREEN}" "  📄 Pull Requests: ${output_file}"
        print_status "${GREEN}" "  📊 Processing Log: search-and-replace-processing-${timestamp}.csv"
    elif [[ "${DRY_RUN}" == false ]]; then
        print_status "${YELLOW}" "No pull requests were created."
        echo "No pull requests created - no changes found or all failed." > "${output_file}"
        print_status "${GREEN}" "  📄 Results: ${output_file}"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: bash 26-search-and-replace.sh [--dry-run] [--debug]

This script searches for code patterns across GitHub repositories and applies regex replacements.

Parameters:
  --dry-run    Show what would be changed without actually making changes
  --debug      Enable debug output

CSV Format (26-search-and-replace.csv):
query,search_pattern,replace_pattern,file_pattern,commit_message

Column Descriptions:
- query:           GitHub search query (e.g., 'org:stone-payments spot path:.github')
                   Supports: org:name, repo:owner/name, keywords, path:, extension:
                   Tip: Avoid quotes around queries for better results
- search_pattern:  Regex pattern to find in file contents (e.g., 'runs-on: (.+)-spot')
                   Supports capture groups: (.+), (\\d+), ([a-z]+), etc.
- replace_pattern: Replacement text with group references (e.g., 'runs-on: \\1')
                   Use \\1, \\2, etc. to reference capture groups
- file_pattern:    File patterns separated by semicolons (e.g., '*.yml;*.yaml;*.py')
                   Supports: *.ext, specific-file.txt, **/*.js (recursive)
- commit_message:  Commit message and PR title (e.g., 'Remove -spot from runners')

Example CSV entries:
org:your-org spot path:.github,"runs-on: (.+)-spot","runs-on: \\1","*.yml;*.yaml","Remove -spot from GitHub Actions runners"
repo:owner/repo python-version,"python-version: '3.8'","python-version: '3.11'","*.yml;*.yaml","Update Python to 3.11"

The script will:
1. Search GitHub for code matching the query using GitHub API
2. Clone each repository found into temporary directories
3. Apply the regex search and replace to matching files
4. Create detailed pull requests with the changes
5. Generate output files with PR links and processing results

Output Files:
- search-and-replace-results-TIMESTAMP.txt    : List of created pull requests
- search-and-replace-processing-TIMESTAMP.csv : Detailed processing log

Features:
- Detailed PR descriptions with diff previews
- Automatic branch creation with timestamps
- Support for multiple file patterns (*.yml,*.yaml)
- Comprehensive error handling and logging
- Safe temporary directory management

EOF
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --debug)
                DEBUG=true
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
    
    # Create temporary directories
    setup_temp_dirs
    
    print_status "${GREEN}" "Starting search and replace process..."
    if [[ "${DRY_RUN}" == true ]]; then
        print_status "${YELLOW}" "Running in DRY-RUN mode - no changes will be made"
    fi
    echo
    
    # Read and process each line from CSV
    local line_number=0
    while IFS=',' read -r query search_pattern replace_pattern file_pattern commit_message; do
        line_number=$((line_number + 1))
        
        debug "Reading CSV line ${line_number}: query='${query}', search='${search_pattern}'"
        
        # Skip header line
        [[ ${line_number} -eq 1 ]] && continue
        
        # Skip empty lines
        [[ -z "${query}" ]] && continue
        
        # Remove quotes from CSV fields
        query=$(echo "${query}" | sed 's/^"//;s/"$//;s/^'\''//;s/'\''$//')
        search_pattern=$(echo "${search_pattern}" | sed 's/^"//;s/"$//')
        replace_pattern=$(echo "${replace_pattern}" | sed 's/^"//;s/"$//')
        file_pattern=$(echo "${file_pattern}" | sed 's/^"//;s/"$//')
        commit_message=$(echo "${commit_message}" | sed 's/^"//;s/"$//')
        
        process_config "${query}" "${search_pattern}" "${replace_pattern}" "${file_pattern}" "${commit_message}"
        
    done < "26-search-and-replace.csv"
    
    print_status "${GREEN}" "All configurations processed successfully!"
}

# Run main function
main "$@"
