#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-03-08
# Description: This script delete all teams.
# Usage: bash 08-organization-roles.sh <organization>
##


# Args 
ORGANIZATION=$1
if [ -z "$ORGANIZATION" ]; then
    echo "Please inform the organization name."
    exit 1
fi

# Verify JQ is installed
if ! [ -x "$(command -v jq)" ]; then
    echo "Error: jq is not installed." >&2
    exit 1
fi

# Get Organization Roles
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /orgs/$ORGANIZATION/organization-roles > organization-roles-$ORGANIZATION.json

# Verify Roles Functions

verify_json_file_and_permissions() {
    FILE=$1
    if [ ! -f "$FILE" ]; then
        echo "File $FILE not found."
        exit 1
    fi

    ROLE_NAME=$2
    if [ -z "$ROLE_NAME" ]; then
        echo "Please inform the role name."
        exit 1
    fi

    PERMISSIONS=$3
    if [ -z "$PERMISSIONS" ]; then
        echo "Please inform the permissions."
        exit 1
    fi

    DESCRIPTION=$4
    if [ -z "$DESCRIPTION" ]; then
        echo "Please inform the description."
        exit 1
    fi

    echo ""
    echo "---"
    echo "Verify role $ROLE_NAME"

    # Verify if the role exists
    SUPPORT_ROLE=$(jq -r ".roles[] | select(.name == \"$ROLE_NAME\")" $FILE)
    if [ -z "$SUPPORT_ROLE" ]; then
        echo "Role $ROLE_NAME not found."
        echo "Trying to create the role $ROLE_NAME"
        create_org_role $ROLE_NAME "${PERMISSIONS[@]}" $DESCRIPTION
    fi

    # Verify if the permissions exists
    for PERMISSION in ${PERMISSIONS[@]}; do
        SUPPORT_PERMISSION=$(echo $SUPPORT_ROLE | jq -r ".permissions[] | select(. == \"$PERMISSION\")")
        if [ $? -ne 0 ]; then
            echo "Permission $PERMISSION not found."
            exit 1
        fi
    done
}

create_org_role(){
    ROLE_NAME=$1
    if [ -z "$ROLE_NAME" ]; then
        echo "Please inform the role name."
        exit 1
    fi

    PERMISSIONS=$2
    if [ -z "$PERMISSIONS" ]; then
        echo "Please inform the permissions."
        exit 1
    fi

    DESCRIPTION=$3
    if [ -z "$DESCRIPTION" ]; then
        echo "Please inform the description."
        exit 1
    fi

    permissions=()
    for permission in "${PERMISSIONS[@]}"; do
        permissions+=("-f" "permissions[]=$permission")
    done

    gh api \
        --method POST \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /orgs/$ORGANIZATION/organization-roles \
        -f "name=$ROLE_NAME" \
        -f "description=Permissions to manage custom roles within an org" \
        "${permissions[@]}" > /dev/null
}

### - support - ###
NAME="support"
PERMISSIONS=(
    "edit_org_custom_properties_values"
    "manage_organization_ref_rules"
    "read_audit_logs"
    "read_organization_custom_org_role"
    "read_organization_custom_repo_role"
    "write_organization_actions_secrets"
    "write_organization_actions_variables"
    "write_organization_runners_and_runner_groups"
)
DESCRIPTION="Time de foundation que fornece suporte ao Github"
verify_json_file_and_permissions organization-roles-$ORGANIZATION.json $NAME "${PERMISSIONS[@]}" $DESCRIPTION

### - access-admin - ###
NAME="access-admin"
PERMISSIONS=(
    "read_audit_logs"
    "read_organization_custom_org_role"
    "read_organization_custom_repo_role"
    "write_organization_custom_org_role"
)
DESCRIPTION="role intended to iam team"
verify_json_file_and_permissions organization-roles-$ORGANIZATION.json $NAME "${PERMISSIONS[@]}" $DESCRIPTION

### - security-operations - ###
NAME="security-operations"
PERMISSIONS=(
    "manage_organization_ref_rules"
    "read_organization_actions_usage_metrics"
)
DESCRIPTION="Custom role for custom actions that the Built-in role does not understand."
verify_json_file_and_permissions organization-roles-$ORGANIZATION.json $NAME "${PERMISSIONS[@]}" $DESCRIPTION


