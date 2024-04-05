# github-scripts

Personal set of scripts to automate some tasks on GitHub.

## Usage

```bash
CASE="name-of-your-case"
terminalizer record $CASE
terminalizer render $CASE
```

## Common

All scripts have a common features:
- `common/audit.sh` - Generate a HASH for the current state of the script and execute.
- `common/config.sh`- All scripts use a  `same-name-script.csv` as a config file. 

## Scripts

- `01-add-team-as-admin.sh` - Add a set of repo/teams from repositores.csv as admin.
