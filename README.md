# github-scripts

Personal set of scripts to automate some tasks on GitHub.

## Usage

```bash
CASE="name-of-your-case"
terminalizer record $CASE
terminalizer render $CASE
```

## How that works?

All scripts have a file .csv with the same name of the script. This file is used to configure the script and as a data source.

## Common

All scripts have a common features:
- `common/audit.sh` - Generate a HASH for the current state of the script and execute.
- `common/config.sh`- All scripts use a  `same-name-script.csv` as a config file. 

## Scripts

- `01-add-team-as-admin.sh` - Add a set of repo/teams from 01-add-team-as-admin.csv
- `02-archive-repos.sh` - Archive a set of repos from 02-archive-repos.csv
- `03-force-code-owners-all-teams.sh` - Migrate to: https://github.com/endersonmenezes/codeowners-superpowers
- `04-app-token.sh` - Generate a token for a set of apps from 04-app-token.csv
- `05-list-repos-and-teams.sh` - List all repos and teams from Organization.
- `06-analyze-logs.py` - Transform JSONL to CSV for logging analysis.
- `07-delete-teams.sh` - Delete a set of teams from 07-delete-teams.csv
- `08-organization-roles.sh` - Manage organization roles for a given organization.
- `09-archive-or-delete-repo.sh` - Archive a repository if it has content, delete if it does not.
- `10-repo-activity.sh` - Return a CSV for activity in repositories.
- `11-if-archived-remove-all-access.sh` - Remove all access from archived repositories.
- `12-list-public-repos.sh` - List all public repositories for given organizations.
- `13-audit-repos.sh` - Audit repositories based on a CSV file.
- `14-remove-all-admin-to-write.sh` - Downgrade all team permissions on repositories from admin to write.
- `15-public-to-private-and-archive.sh` - Transform a public repository to private and archive it.

## functions.sh

The `functions.sh` file contains common functions used by the scripts. It includes functions to verify if GitHub CLI is installed, read configuration files, and create SHA256 hashes for audit purposes.
