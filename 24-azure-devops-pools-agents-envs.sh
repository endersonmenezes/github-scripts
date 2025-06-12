#!/bin/bash

###############################################################################
# Azure DevOps Organization Scanner
#
# Author: Enderson Menezes
# Created: 2025-06-12
# Updated: 2025-06-12
#
# Description:
#   This script scans an Azure DevOps organization and provides comprehensive
#   information about:
#   - All projects in the organization
#   - All agent pools (organization-level)
#   - All agents within each pool
#   - All environments within each project
#
# Usage: bash 24-azure-devops-pools-agents-envs.sh <token> <organization> [output_format]
#
# Parameters:
#   - token: Azure DevOps Personal Access Token (PAT)
#   - organization: Azure DevOps organization name
#   - output_format: Output format (json|table) - optional, defaults to table
#
# Dependencies:
#   - curl: Used for making HTTP requests to the Azure DevOps API.
#   - jq: Used for parsing JSON responses from the API.
#   - functions.sh: Contains common utility functions (audit_file, is_gh_installed).
###############################################################################

# Read Common Functions
source functions.sh

# Create a SHA256 of the file for audit (Define SHA256 variable)
audit_file

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Configuration ---
API_VERSION="7.1"

# --- Helper Functions ---

# Function: usage
# Description: Displays help message explaining how to use the script and exits.
usage() {
  echo -e "${YELLOW}Usage:${NC} $0 <token> <organization> [output_format]"
  echo -e "  ${YELLOW}token${NC}         - Azure DevOps Personal Access Token (PAT)"
  echo -e "  ${YELLOW}organization${NC}  - Azure DevOps organization name"
  echo -e "  ${YELLOW}output_format${NC} - Output format: json or table (default: table)"
  echo ""
  echo -e "${YELLOW}Example:${NC}"
  echo -e "  $0 your_token myorg table"
  echo -e "  $0 your_token myorg json > scan_results.json"
  exit 1
}

# Function: check_dependencies
# Description: Checks if required tools are installed
check_dependencies() {
  local missing_deps=()
  
  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi
  
  if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
  fi
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    echo -e "${RED}Error: Missing dependencies: ${missing_deps[*]}${NC}"
    echo -e "${YELLOW}Please install the missing dependencies:${NC}"
    echo -e "${YELLOW}  Debian/Ubuntu: sudo apt-get update && sudo apt-get install ${missing_deps[*]}${NC}"
    echo -e "${YELLOW}  macOS: brew install ${missing_deps[*]}${NC}"
    exit 1
  fi
}

# Function: api_call
# Description: Makes an authenticated API call to Azure DevOps
# Parameters: $1 - API URL, $2 - description for logging
api_call() {
  local url="$1"
  local description="$2"
  local response_file=$(mktemp)
  
  if [ "$OUTPUT_FORMAT" = "table" ]; then
    echo -e "${CYAN}Fetching ${description}...${NC}" >&2
  fi
  
  local http_status=$(curl --silent --show-error --output "$response_file" --write-out "%{http_code}" --user ":$TOKEN" "$url")
  
  if [ "$http_status" -eq 200 ]; then
    cat "$response_file"
    rm -f "$response_file"
    return 0
  else
    if [ "$OUTPUT_FORMAT" = "table" ]; then
      echo -e "${RED}Failed to fetch ${description} (Status: $http_status)${NC}" >&2
      if jq '.' "$response_file" 2>/dev/null >&2; then
        echo >&2
      else
        cat "$response_file" >&2
        echo >&2
      fi
    fi
    rm -f "$response_file"
    return 1
  fi
}

# Function: get_projects
# Description: Fetches all projects in the organization
get_projects() {
  local url="https://dev.azure.com/${ORG}/_apis/projects?api-version=${API_VERSION}"
  api_call "$url" "projects list"
}

# Function: get_pools
# Description: Fetches all agent pools in the organization
get_pools() {
  local url="https://dev.azure.com/${ORG}/_apis/distributedtask/pools?api-version=${API_VERSION}"
  api_call "$url" "agent pools list"
}

# Function: get_agents
# Description: Fetches all agents for a specific pool
# Parameters: $1 - pool ID
get_agents() {
  local pool_id="$1"
  local url="https://dev.azure.com/${ORG}/_apis/distributedtask/pools/${pool_id}/agents?api-version=${API_VERSION}"
  api_call "$url" "agents for pool $pool_id"
}

# Function: get_environments
# Description: Fetches all environments for a specific project
# Parameters: $1 - project name
get_environments() {
  local project="$1"
  local url="https://dev.azure.com/${ORG}/${project}/_apis/distributedtask/environments?api-version=${API_VERSION}"
  api_call "$url" "environments for project $project"
}

# Function: output_json
# Description: Outputs all data in JSON format
output_json() {
  local projects_data=$(get_projects)
  local pools_data=$(get_pools)
  
  if [ -z "$projects_data" ] || [ -z "$pools_data" ]; then
    echo '{"error": "Failed to fetch basic data"}' >&2
    return 1
  fi
  
  local json_output='{"organization": "'$ORG'", "scan_timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'", "projects": [], "pools": []}'
  
  # Process projects
  local project_names=$(echo "$projects_data" | jq -r '.value[]?.name // empty')
  if [ -n "$project_names" ]; then
    while IFS= read -r project_name; do
      [ -z "$project_name" ] && continue
      local environments_data=$(get_environments "$project_name")
      local project_json=$(echo "$projects_data" | jq --arg name "$project_name" '.value[] | select(.name == $name)')
      
      if [ -n "$environments_data" ]; then
        local environments=$(echo "$environments_data" | jq '.value // []')
        project_json=$(echo "$project_json" | jq --argjson envs "$environments" '. += {"environments": $envs}')
      else
        project_json=$(echo "$project_json" | jq '. += {"environments": []}')
      fi
      
      json_output=$(echo "$json_output" | jq --argjson proj "$project_json" '.projects += [$proj]')
    done <<< "$project_names"
  fi
  
  # Process pools and their agents
  local pool_ids=$(echo "$pools_data" | jq -r '.value[]?.id // empty')
  if [ -n "$pool_ids" ]; then
    while IFS= read -r pool_id; do
      [ -z "$pool_id" ] && continue
      local agents_data=$(get_agents "$pool_id")
      local pool_json=$(echo "$pools_data" | jq --arg id "$pool_id" '.value[] | select(.id == ($id | tonumber))')
      
      if [ -n "$agents_data" ]; then
        local agents=$(echo "$agents_data" | jq '.value // []')
        pool_json=$(echo "$pool_json" | jq --argjson agents "$agents" '. += {"agents": $agents}')
      else
        pool_json=$(echo "$pool_json" | jq '. += {"agents": []}')
      fi
      
      json_output=$(echo "$json_output" | jq --argjson pool "$pool_json" '.pools += [$pool]')
    done <<< "$pool_ids"
  fi
  
  echo "$json_output" | jq '.'
}

# Function: output_table
# Description: Outputs all data in table format
output_table() {
  echo -e "${GREEN}=== Azure DevOps Organization Scan: ${ORG} ===${NC}"
  echo -e "${YELLOW}Scan started at: $(date)${NC}"
  echo ""
  
  # Projects Section
  echo -e "${BLUE}📁 PROJECTS${NC}"
  echo -e "${BLUE}===================${NC}"
  local projects_data=$(get_projects)
  
  if [ -n "$projects_data" ]; then
    local project_count=$(echo "$projects_data" | jq '.count // 0')
    echo -e "Total projects found: ${GREEN}$project_count${NC}"
    echo ""
    
    local project_names=$(echo "$projects_data" | jq -r '.value[]? | select(.name) | .name')
    if [ -n "$project_names" ]; then
      while IFS= read -r project_name; do
        [ -z "$project_name" ] && continue
        local project_info=$(echo "$projects_data" | jq -r --arg name "$project_name" '.value[] | select(.name == $name) | "ID: " + .id + " | State: " + .state + " | Visibility: " + .visibility')
        echo -e "${CYAN}Project:${NC} $project_name"
        echo -e "  $project_info"
        
        # Get environments for this project
        local environments_data=$(get_environments "$project_name")
        if [ -n "$environments_data" ]; then
          local env_count=$(echo "$environments_data" | jq '.count // 0')
          if [ "$env_count" -gt 0 ]; then
            echo -e "  ${YELLOW}Environments ($env_count):${NC}"
            echo "$environments_data" | jq -r '.value[]? | select(.name) | "    - " + .name + " (ID: " + (.id | tostring) + ")"'
          else
            echo -e "  ${YELLOW}Environments: None${NC}"
          fi
        else
          echo -e "  ${YELLOW}Environments: Error fetching${NC}"
        fi
        echo ""
      done <<< "$project_names"
    fi
  else
    echo -e "${RED}Failed to fetch projects${NC}"
  fi
  
  # Pools Section
  echo -e "${BLUE}🏊 AGENT POOLS${NC}"
  echo -e "${BLUE}===================${NC}"
  local pools_data=$(get_pools)
  
  if [ -n "$pools_data" ]; then
    local pool_count=$(echo "$pools_data" | jq '.count // 0')
    echo -e "Total pools found: ${GREEN}$pool_count${NC}"
    echo ""
    
    local pool_data_array=$(echo "$pools_data" | jq -r '.value[]? | select(.name) | .id + "|" + .name + "|" + .poolType + "|" + (.size | tostring)')
    if [ -n "$pool_data_array" ]; then
      while IFS='|' read -r pool_id pool_name pool_type pool_size; do
        [ -z "$pool_id" ] && continue
        echo -e "${CYAN}Pool:${NC} $pool_name"
        echo -e "  ID: $pool_id | Type: $pool_type | Size: $pool_size"
        
        # Get agents for this pool
        local agents_data=$(get_agents "$pool_id")
        if [ -n "$agents_data" ]; then
          local agent_count=$(echo "$agents_data" | jq '.count // 0')
          if [ "$agent_count" -gt 0 ]; then
            echo -e "  ${YELLOW}Agents ($agent_count):${NC}"
            echo "$agents_data" | jq -r '.value[]? | select(.name) | "    - " + .name + " (Status: " + .status + ", Enabled: " + (.enabled | tostring) + ")"'
          else
            echo -e "  ${YELLOW}Agents: None${NC}"
          fi
        else
          echo -e "  ${YELLOW}Agents: Error fetching${NC}"
        fi
        echo ""
      done <<< "$pool_data_array"
    fi
  else
    echo -e "${RED}Failed to fetch pools${NC}"
  fi
  
  echo -e "${GREEN}=== Scan completed at: $(date) ===${NC}"
}

# --- Main Script ---

# Validate required arguments
if [ $# -lt 2 ]; then
  echo -e "${RED}Error: Token and organization are required${NC}"
  usage
fi

# Check dependencies
check_dependencies

# Assign arguments to variables
TOKEN="$1"
ORG="$2"
OUTPUT_FORMAT="${3:-table}"

# Validate output format
if [[ "$OUTPUT_FORMAT" != "json" && "$OUTPUT_FORMAT" != "table" ]]; then
  echo -e "${RED}Error: Invalid output format. Use 'json' or 'table'${NC}"
  usage
fi

# Execute based on output format
case "$OUTPUT_FORMAT" in
  "json")
    output_json
    ;;
  "table")
    output_table
    ;;
esac

exit $?
