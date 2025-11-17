#!/usr/bin/env bash

# Upload arbitrary files and folders to the remote root
#
# Please have a look at ./wp-sync-deploy.example.env to see all required variables.
#
# The remote folder must exist and be empty, otherwise this script will fail.
#
# COMMANDS:
#
# Upload to production or staging
# `./wp-sync-deploy/upload.sh <production|staging> --paths="file1 folder1 folder2"`

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

checkIsDeploymentAllowed

logSuccess "All checks successful! Proceeding ..."
logLine

# Confirm the upload
log "📦 Remote host: ${BLUE}$PRETTY_REMOTE_HOST${NC}"
log "📦 Remote dir: ${BLUE}$REMOTE_ROOT_DIR${NC}"
log "📦 Upload: ${BLUE}$(echo "$DEPLOY_PATHS" | sed 's/ /, /g')${NC}"
log "📦 Existing files & folders on the remote server will be skipped. Proceed?"
read -r -p "[y/n] " PROMPT_RESPONSE

# Exit if not confirmed
[[ "$PROMPT_RESPONSE" != "y" ]] && exit 1

log "🚀 ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Pushing to $PRETTY_REMOTE_ENV ..."

# Always include all files to upload
for file in $DEPLOY_PATHS; do
    INCLUDE_ARGS+="--include=$file "
done

# Execute rsync from $LOCAL_ROOT_DIR in a subshell to make sure we are staying in the current pwd
(
  cd "$LOCAL_ROOT_DIR"
  rsync -avz --ignore-existing --relative \
    --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r \
    -e "ssh -p $REMOTE_SSH_PORT" \
    $INCLUDE_ARGS \
    --exclude-from="$DEPLOYIGNORE_FILE" \
    $DEPLOY_PATHS "$REMOTE_SSH:$REMOTE_ROOT_DIR"
)

log "\n✅ ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Push to $PRETTY_REMOTE_ENV completed"
