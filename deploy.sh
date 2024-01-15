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

# The directory relative to the script
SCRIPT_DIR=$(realpath $(dirname $0))

# Source files
source "$SCRIPT_DIR/lib/functions.sh"
source "$SCRIPT_DIR/lib/bootstrap.sh"

# Will be displayed if no arguments are being provided
USAGE_MESSAGE="Usage: https://github.com/hirasso/wp-sync-deploy#deploy-your-local-files-to-remote-environments

./wp-sync-deploy/deploy.sh <production|staging> [run] "

# Exit early if we received no arguments
[ $# -eq 0 ] && logError "$USAGE_MESSAGE"

# Construct the directories to deploy from the provided env variables
export DEPLOY_DIRS="$WP_CORE_DIR $WP_CONTENT_DIR/plugins $WP_CONTENT_DIR/themes/$WP_THEME"

DEPLOY_MODE="dry"
[ ! -z "${2+x}" ] && DEPLOY_MODE="$2"

# Perform checks
checkProductionBranch
checkCommandLinePHPVersions
checkWebFacingPHPVersions
checkIsRemoteAllowed
checkDirectories
logSuccess "All checks successful! Proceeding ..."
logLine

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
    # Confirmation is needed for a non-dry run
    log "🚀 Would you really like to deploy to ${GREEN}$REMOTE_HOST${NC}" ?
    read -r -p "[y/n] " PROMPT_RESPONSE

    # Exit if not confirmed
    [[ $(checkPromptResponse "$PROMPT_RESPONSE") != 1 ]] && exit 1

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