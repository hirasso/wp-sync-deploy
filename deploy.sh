#!/usr/bin/env bash

# DEPLOY your WordPress core, theme and plugins to staging or production
#
# Please have a look at ./wp-sync-deploy.example.env to see all required variables
#
# COMMANDS:
#
# Deploy to production or staging (dry run)
# `./wp-sync-deploy/deploy.sh <production|staging>`
#
# Deploy to production or staging (RUN!)
# `./wp-sync-deploy/deploy.sh <production|staging> run`

# Make this script more strict
set -o errexit
set -o nounset
set -o pipefail

# The directory relative to the script
export SCRIPT_DIR=$(realpath $(dirname $0))
export CURRENT_DIR=$(pwd)

# Font Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export BLUE="\033[0;34m"
export NC='\033[0m' # No Color

# Font styles
export BOLD=$(tput bold)
export NORMAL=$(tput sgr0)

# Source files
source "$SCRIPT_DIR/lib/functions.sh"

# Will be displayed if no arguments are being provided
USAGE_MESSAGE="Usage: https://github.com/hirasso/wp-sync-deploy#deploy-your-local-files-to-remote-environments

./wp-sync-deploy/deploy.sh <production|staging> [run] "

# Exit early if we received no arguments
[ $# -eq 0 ] && logError "$USAGE_MESSAGE"

# Required positional arguments
REMOTE_ENV="$1"

# Deployment to production will only be possible from these two branches
MAIN_BRANCH="master|main"

# Find the closest wp-sync-deploy.env file
ENV_FILE=$(findUp "wp-sync-deploy.env" $SCRIPT_DIR)
[ -z "$ENV_FILE" ] && logError "No wp-sync-deploy.env file found, exiting..."

# Make env vars available everywhere
# @see https://stackoverflow.com/a/30969768/586823
set -o allexport
source $ENV_FILE
set +o allexport

# Set SSH paths based on provided environment (production/staging)
case $REMOTE_ENV in

production)
    # Define your production vars
    export REMOTE_HOST=$PROD_HOST
    export REMOTE_PROTOCOL=$PROD_PROTOCOL
    export REMOTE_HTTP_AUTH=$PROD_HTTP_AUTH
    export REMOTE_SSH=$PROD_SSH
    export REMOTE_WEB_ROOT=$PROD_WEB_ROOT
    export REMOTE_PHP_BINARY=$PROD_PHP_BINARY
    ;;

staging)
    # Define your staging vars
    export REMOTE_HOST=$STAG_HOST
    export REMOTE_PROTOCOL=$STAG_PROTOCOL
    export REMOTE_HTTP_AUTH=$STAG_HTTP_AUTH
    export REMOTE_SSH=$STAG_SSH
    export REMOTE_WEB_ROOT=$STAG_WEB_ROOT
    export REMOTE_PHP_BINARY=$STAG_PHP_BINARY
    ;;

*)
    logError "Please provide the remote environment (production or staging)"
    ;;
esac

# Prepare variables for printing
export PRETTY_LOCAL_ENV=$(printf "${BOLD}local${NORMAL}")
export PRETTY_REMOTE_ENV=$(printf "${BOLD}$REMOTE_ENV${NORMAL}")

# Validate required variables
test -z "$LOCAL_WEB_ROOT" && logError "LOCAL_WEB_ROOT is not defined"
test -z "$REMOTE_WEB_ROOT" && logError "REMOTE_WEB_ROOT is not defined"
test -z "$WP_CONTENT_DIR" && logError "WP_CONTENT_DIR is not defined"
test -z "$WP_CORE_DIR" && logError "WP_CORE_DIR is not defined"
test -z "$REMOTE_SSH" && logError "REMOTE_SSH is not defined"
test -z "$REMOTE_HOST" && logError "REMOTE_HOST is not defined"
test -z "$REMOTE_PROTOCOL" && logError "REMOTE_PROTOCOL is not defined"

# Normalize paths from the .env file
LOCAL_WEB_ROOT=$(normalizePath $LOCAL_WEB_ROOT)
REMOTE_WEB_ROOT=$(normalizePath $REMOTE_WEB_ROOT)
WP_CONTENT_DIR=$(trimLeadingSlash $(normalizePath $WP_CONTENT_DIR))
WP_CORE_DIR=$(trimLeadingSlash $(normalizePath $WP_CORE_DIR))

# Construct the directories to deploy from the provided env variables
export DEPLOY_DIRS="$WP_CORE_DIR $WP_CONTENT_DIR/plugins $WP_CONTENT_DIR/themes/$WP_THEME"

# DEPLOY to the production or staging server

log "🚀 Would you really like to deploy to ${GREEN}$REMOTE_HOST${NC}" ?
read -r -p "[y/n] " PROMPT_RESPONSE

# Return early if not confirmed
[[ $(checkPromptResponse "$PROMPT_RESPONSE") != 1 ]] && exit 1

# Perform checks
checkProductionBranch
checkCommandLinePHPVersions
checkWebFacingPHPVersions
checkIsRemoteAllowed
checkDirectories
logSuccess "All checks successful! Proceeding ..."
logLine

DEPLOY_MODE="dry"
[ ! -z "${2+x}" ] && DEPLOY_MODE="$2"

case $DEPLOY_MODE in

dry)
    log "🚀 ${GREEN}${BOLD}[ DRY-RUN ]${NORMAL}${NC} Deploying to $PRETTY_REMOTE_ENV ..."

    # Execute rsync from $LOCAL_WEB_ROOT in a subshell to make sure we are staying in the current pwd
    (
        cd "$LOCAL_WEB_ROOT"
        rsync --dry-run -avz --delete --relative \
            --exclude-from="$SCRIPT_DIR/.deployignore" \
            $DEPLOY_DIRS "$REMOTE_SSH:$REMOTE_WEB_ROOT"
    )
    logLine
    log "🔥 Would clear the cache at $PRETTY_REMOTE_ENV"

    logLine
    log "✅ ${GREEN}${BOLD}[ DRY-RUN ]${NORMAL}${NC} Deploy preview to $PRETTY_REMOTE_ENV completed"
    ;;

run)
    log "🚀 ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Deploying to $PRETTY_REMOTE_ENV ..."

    # Execute rsync from $LOCAL_WEB_ROOT in a subshell to make sure we are staying in the current pwd
    (
        cd "$LOCAL_WEB_ROOT"
        rsync -avz --delete --relative \
            --exclude-from="$SCRIPT_DIR/.deployignore" \
            $DEPLOY_DIRS "$REMOTE_SSH:$REMOTE_WEB_ROOT"
    )

    log "\n✅ ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Deploy to $PRETTY_REMOTE_ENV completed"

    logLine

    runRemoteWpWithPrompt rewrite flush
    runRemoteWpWithPrompt transient delete --all

    deleteSuperCacheDir remote

    REMOTE_URL=$(constructURL remote)
    log "\n✅ Done! Be sure to check if everything works as expected on your $PRETTY_REMOTE_ENV site:"
    log "\n${GREEN}$REMOTE_URL${NC}"
    ;;

*)
    logError $USAGE_MESSAGE
    ;;

esac
