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
#   - output_format: Output format (json|csv) - optional, defaults to csv
#
# Output Files:
#   CSV format generates:
#     - {org}_pools_agents.csv: All pools and their agents (organization-level)
#     - {org}_projects_environments.csv: All projects and their environments
#   
#   JSON format generates:
#     - {org}_pools_agents.json: All pools and their agents data
#     - {org}_projects_environments.json: All projects and their environments data
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
  echo -e "  ${YELLOW}output_format${NC} - Output format: json or csv (default: csv)"
  echo ""
  echo -e "${YELLOW}Output Files:${NC}"
  echo -e "  ${CYAN}CSV format generates:${NC}"
  echo -e "    - {org}_pools_agents.csv: All pools and their agents"
  echo -e "    - {org}_projects_environments.csv: All projects and their environments"
  echo ""
  echo -e "  ${CYAN}JSON format generates:${NC}"
  echo -e "    - {org}_pools_agents.json: All pools and their agents data"
  echo -e "    - {org}_projects_environments.json: All projects and their environments data"
  echo ""
  echo -e "${YELLOW}Examples:${NC}"
  echo -e "  $0 your_token myorg csv"
  echo -e "  $0 your_token myorg json"
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
  
  if [ "$OUTPUT_FORMAT" = "csv" ]; then
    echo -e "${CYAN}Fetching ${description}...${NC}" >&2
  fi
  
  local http_status=$(curl --silent --show-error --output "$response_file" --write-out "%{http_code}" --user ":$TOKEN" "$url")
  
  if [ "$http_status" -eq 200 ]; then
    cat "$response_file"
    rm -f "$response_file"
    return 0
  else
    if [ "$OUTPUT_FORMAT" = "csv" ]; then
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
# Parameters: $1 - project ID (not name, to avoid URL encoding issues)
get_environments() {
  local project_id="$1"
  local url="https://dev.azure.com/${ORG}/${project_id}/_apis/distributedtask/environments?api-version=${API_VERSION}"
  api_call "$url" "environments for project ID $project_id"
}

# Function: output_json
# Description: Outputs data separated into two JSON files
output_json() {
  local pools_file="${ORG}_pools_agents.json"
  local projects_file="${ORG}_projects_environments.json"
  
  echo -e "${GREEN}=== Azure DevOps Organization Scan: ${ORG} ===${NC}"
  echo -e "${YELLOW}Generating JSON files...${NC}"
  
  # Generate pools and agents JSON
  local pools_data=$(get_pools)
  if [ -n "$pools_data" ]; then
    local pools_output='{"organization": "'$ORG'", "scan_timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'", "pools": []}'
    
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
        
        pools_output=$(echo "$pools_output" | jq --argjson pool "$pool_json" '.pools += [$pool]')
      done <<< "$pool_ids"
    fi
    
    echo "$pools_output" | jq '.' > "$pools_file"
    echo -e "${GREEN}✓ Generated: $pools_file${NC}"
  else
    echo -e "${RED}✗ Failed to generate pools JSON${NC}"
  fi
  
  # Generate projects and environments JSON
  local projects_data=$(get_projects)
  if [ -n "$projects_data" ]; then
    local projects_output='{"organization": "'$ORG'", "scan_timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'", "projects": []}'
    
    local project_ids=$(echo "$projects_data" | jq -r '.value[]?.id // empty')
    if [ -n "$project_ids" ]; then
      while IFS= read -r project_id; do
        [ -z "$project_id" ] && continue
        local environments_data=$(get_environments "$project_id")
        local project_json=$(echo "$projects_data" | jq --arg id "$project_id" '.value[] | select(.id == $id)')
        
        if [ -n "$environments_data" ]; then
          local environments=$(echo "$environments_data" | jq '.value // []')
          project_json=$(echo "$project_json" | jq --argjson envs "$environments" '. += {"environments": $envs}')
        else
          project_json=$(echo "$project_json" | jq '. += {"environments": []}')
        fi
        
        projects_output=$(echo "$projects_output" | jq --argjson proj "$project_json" '.projects += [$proj]')
      done <<< "$project_ids"
    fi
    
    echo "$projects_output" | jq '.' > "$projects_file"
    echo -e "${GREEN}✓ Generated: $projects_file${NC}"
  else
    echo -e "${RED}✗ Failed to generate projects JSON${NC}"
  fi
  
  echo -e "${GREEN}=== JSON generation completed ===${NC}"
}

# Function: output_csv
# Description: Outputs data separated into two CSV files
output_csv() {
  local pools_file="${ORG}_pools_agents.csv"
  local projects_file="${ORG}_projects_environments.csv"
  
  echo -e "${GREEN}=== Azure DevOps Organization Scan: ${ORG} ===${NC}"
  echo -e "${YELLOW}Generating CSV files...${NC}"
  
  # Generate pools and agents CSV
  local pools_data=$(get_pools)
  if [ -n "$pools_data" ]; then
    # CSV Header for pools
    echo "pool_id,pool_name,pool_type,pool_size,agent_id,agent_name,agent_status,agent_enabled,agent_version,agent_os_description" > "$pools_file"
    
    local pool_count=0
    local agent_count=0
    local pool_data_array=$(echo "$pools_data" | jq -r '.value[]? | select(.name) | (.id | tostring) + "|" + .name + "|" + (.poolType // "Unknown") + "|" + (.size | tostring)')
    
    if [ -n "$pool_data_array" ]; then
      while IFS='|' read -r pool_id pool_name pool_type pool_size; do
        [ -z "$pool_id" ] && continue
        ((pool_count++))
        
        # Get agents for this pool
        local agents_data=$(get_agents "$pool_id")
        if [ -n "$agents_data" ]; then
          # Clean pool data for CSV (remove newlines and commas)
          local clean_pool_name=$(echo "$pool_name" | tr -d '\n\r' | sed 's/,/;/g')
          local clean_pool_type=$(echo "$pool_type" | tr -d '\n\r' | sed 's/,/;/g')
          
          local agents_csv=$(echo "$agents_data" | jq -r --arg pool_id "$pool_id" --arg pool_name "$clean_pool_name" --arg pool_type "$clean_pool_type" --arg pool_size "$pool_size" '.value[]? | select(.name) | $pool_id + "," + $pool_name + "," + $pool_type + "," + $pool_size + "," + (.id | tostring) + "," + (.name | gsub("\n|\r"; " ") | gsub(","; ";")) + "," + ((.status // "Unknown") | gsub("\n|\r"; " ") | gsub(","; ";")) + "," + (.enabled | tostring) + "," + ((.version // "Unknown") | gsub("\n|\r"; " ") | gsub(","; ";")) + "," + ((.osDescription // "Unknown") | gsub("\n|\r"; " ") | gsub(","; ";"))')
          
          if [ -n "$agents_csv" ]; then
            echo "$agents_csv" >> "$pools_file"
            agent_count=$((agent_count + $(echo "$agents_csv" | wc -l)))
          fi
        else
          # Pool without agents - clean the pool name for CSV
          local clean_pool_name=$(echo "$pool_name" | tr -d '\n\r' | sed 's/,/;/g')
          local clean_pool_type=$(echo "$pool_type" | tr -d '\n\r' | sed 's/,/;/g')
          echo "$pool_id,$clean_pool_name,$clean_pool_type,$pool_size,,,,,," >> "$pools_file"
        fi
      done <<< "$pool_data_array"
    fi
    
    echo -e "${GREEN}✓ Generated: $pools_file ($pool_count pools, $agent_count agents)${NC}"
  else
    echo -e "${RED}✗ Failed to generate pools CSV${NC}"
  fi
  
  # Generate projects and environments CSV
  local projects_data=$(get_projects)
  if [ -n "$projects_data" ]; then
    # CSV Header for projects
    echo "project_id,project_name,project_state,project_visibility,project_url,environment_id,environment_name,environment_description" > "$projects_file"
    
    local project_count=0
    local env_count=0
    local project_data_array=$(echo "$projects_data" | jq -r '.value[]?.id + "|" + (.name | gsub("\n|\r"; " ")) + "|" + ((.state // "Unknown") | gsub("\n|\r"; " ")) + "|" + ((.visibility // "Unknown") | gsub("\n|\r"; " ")) + "|" + (.url // "")')
    
    if [ -n "$project_data_array" ]; then
      while IFS='|' read -r proj_id proj_name proj_state proj_visibility proj_url; do
        [ -z "$proj_id" ] && continue
        ((project_count++))
        
        # Clean project data for CSV
        proj_name=$(echo "$proj_name" | sed 's/,/;/g')
        proj_state=$(echo "$proj_state" | sed 's/,/;/g')
        proj_visibility=$(echo "$proj_visibility" | sed 's/,/;/g')
        proj_url=$(echo "$proj_url" | sed 's/,/;/g')
        
        # Get environments for this project using project ID
        local environments_data=$(get_environments "$proj_id")
        if [ -n "$environments_data" ]; then
          local env_csv=$(echo "$environments_data" | jq -r --arg proj_id "$proj_id" --arg proj_name "$proj_name" --arg proj_state "$proj_state" --arg proj_visibility "$proj_visibility" --arg proj_url "$proj_url" '.value[]? | select(.name) | $proj_id + "," + $proj_name + "," + $proj_state + "," + $proj_visibility + "," + $proj_url + "," + (.id | tostring) + "," + (.name | gsub("\n|\r"; " ") | gsub(","; ";")) + "," + ((.description // "") | gsub("\n|\r"; " ") | gsub(","; ";"))')
          
          if [ -n "$env_csv" ]; then
            echo "$env_csv" >> "$projects_file"
            env_count=$((env_count + $(echo "$env_csv" | wc -l)))
          else
            # Project without environments
            echo "$proj_id,$proj_name,$proj_state,$proj_visibility,$proj_url,,," >> "$projects_file"
          fi
        else
          # Project without environments
          echo "$proj_id,$proj_name,$proj_state,$proj_visibility,$proj_url,,," >> "$projects_file"
        fi
      done <<< "$project_data_array"
    fi
    
    echo -e "${GREEN}✓ Generated: $projects_file ($project_count projects, $env_count environments)${NC}"
  else
    echo -e "${RED}✗ Failed to generate projects CSV${NC}"
  fi
  
  echo -e "${GREEN}=== CSV generation completed ===${NC}"
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
OUTPUT_FORMAT="${3:-csv}"

# Validate output format
if [[ "$OUTPUT_FORMAT" != "json" && "$OUTPUT_FORMAT" != "csv" ]]; then
  echo -e "${RED}Error: Invalid output format. Use 'json' or 'csv'${NC}"
  usage
fi

# Execute based on output format
case "$OUTPUT_FORMAT" in
  "json")
    output_json
    ;;
  "csv")
    output_csv
    ;;
esac

exit $?
