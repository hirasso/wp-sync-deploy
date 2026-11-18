#!/usr/bin/env bash

# ROLL BACK the latest deploy: restores files and database from the snapshot taken before it
#
# Please have a look at ./wp-sync-deploy.config.example.php to see all required options
#
# COMMANDS:
#
# Roll back the latest deploy. Run it again to go back one more deploy
# `vendor/bin/wp-sync-deploy rollback <production|staging> [--yes]`

# The directory relative to the script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Source files
source "$SCRIPT_DIR/lib/functions.sh"

# Will be displayed if no arguments are being provided
USAGE_MESSAGE="Usage: https://github.com/hirasso/wp-sync-deploy#roll-back-a-deploy

vendor/bin/wp-sync-deploy rollback <production|staging> [--yes]"

# Exit early if we received no arguments
[ $# -eq 0 ] && logError "$USAGE_MESSAGE"

source "$SCRIPT_DIR/lib/bootstrap.sh"

SKIP_CONFIRM=false
for arg in "${@:2}"; do
  case $arg in
  --yes) SKIP_CONFIRM=true ;;
  --*) ;;
  *) logError "$USAGE_MESSAGE" ;;
  esac
done

checkRemoteRootExists
checkIsDeploymentAllowed

rollbackLatestSnapshot
logLine
