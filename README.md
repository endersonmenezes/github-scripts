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
