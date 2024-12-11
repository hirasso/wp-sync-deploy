#!/usr/bin/env bash

# PUSH arbitrary files and folders to the remote root
#
# Please have a look at ./wp-sync-deploy.example.env to see all required variables.
#
# The remote folder must exist and be empty, otherwise this script will fail.
#
# COMMANDS:
#
# Push to production or staging
# `./wp-sync-deploy/push.sh <production|staging> --paths="file1 folder1 folder2"`

# The directory relative to the script
SCRIPT_DIR=$(realpath $(dirname $0))

# Source files
source "$SCRIPT_DIR/lib/functions.sh"
source "$SCRIPT_DIR/lib/bootstrap.sh"

# Default value for DEPLOY_PATHS
DEPLOY_PATHS=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        --paths=*)
            DEPLOY_PATHS="${arg#*=}"
            shift
            ;;
    esac
done

# Check if DEPLOY_PATHS is empty
if [[ -z "$DEPLOY_PATHS" ]]; then
    logError "The --paths option was not provided or is empty."
fi

# Will be displayed if no arguments are being provided
USAGE_MESSAGE="Usage:
    ./wp-sync-deploy/push.sh <production|staging> --paths='file1 folder1 folder2'"

checkIsRemoteRootExistsAndIsEmpty
createAllowDeploymentFileInRemoteRoot
checkIsRemoteRootPrepared

logSuccess "All checks successful! Proceeding ..."
logLine

# Confirm the deployment if the deploy strategy is conservative
log "🚀 Would you really like to push to ${BLUE}$REMOTE_ROOT_DIR${NC} on $PRETTY_REMOTE_HOST" ?
read -r -p "[y/n] " PROMPT_RESPONSE

# Exit if not confirmed
[[ "$PROMPT_RESPONSE" != "y" ]] && exit 1

log "🚀 ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Pushing to $PRETTY_REMOTE_ENV ..."

# Execute rsync from $LOCAL_ROOT_DIR in a subshell to make sure we are staying in the current pwd
(
  cd "$LOCAL_ROOT_DIR"
  rsync -avz --delete --relative \
    -e "ssh -p $REMOTE_SSH_PORT" \
    --exclude-from="$DEPLOYIGNORE_FILE" \
    $DEPLOY_PATHS "$REMOTE_SSH:$REMOTE_ROOT_DIR"
)

log "\n✅ ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Push to $PRETTY_REMOTE_ENV completed"
