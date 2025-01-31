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
DEPLOY_PATHS="$WP_CORE_DIR $WP_CONTENT_DIR/plugins $WP_CONTENT_DIR/themes"
# Add /mu-plugins to the deploy dirs if it exists
test -d "$LOCAL_ROOT_DIR/$WP_CONTENT_DIR/mu-plugins" && DEPLOY_PATHS="$DEPLOY_PATHS $WP_CONTENT_DIR/mu-plugins"
# Add /languages to the deploy dirs if it exists
test -d "$LOCAL_ROOT_DIR/$WP_CONTENT_DIR/languages" && DEPLOY_PATHS="$DEPLOY_PATHS $WP_CONTENT_DIR/languages"
# Add $ADDITIONAL_DIRS to the end if defined
[ ! -z "${ADDITIONAL_DIRS+x}" ] && DEPLOY_PATHS="$DEPLOY_PATHS $ADDITIONAL_DIRS"

# Default to dry mode
DEPLOY_MODE="${2:-dry}"


# Perform checks before proceeding
case $DEPLOY_STRATEGY in

risky)
  validateProductionBranch
  checkRemoteRootExists
  ;;

conservative)
  validateProductionBranch
  checkRemoteRootExists
  checkIsDeploymentAllowed
  checkCommandLinePHPVersions
  checkWebFacingPHPVersions
  checkDeployPaths
  ;;

esac

logSuccess "All checks successful! Proceeding ..."
logLine

# Add the favicon.ico in the public dir if it exists.
# Doing that after `checkDeployPaths` as it doesn't require an existence check.
test -f "$LOCAL_WEB_ROOT/favicon.ico" && DEPLOY_PATHS="$DEPLOY_PATHS $PUBLIC_DIR/favicon.ico"

case $DEPLOY_MODE in

dry)
  log "🚀 ${GREEN}${BOLD}[ DRY-RUN ]${NORMAL}${NC} Deploying to $PRETTY_REMOTE_ENV ..."

  # Execute rsync from $LOCAL_ROOT_DIR in a subshell to make sure we are staying in the current pwd
  (
    cd "$LOCAL_ROOT_DIR"
    rsync --dry-run -avz --delete --relative \
      -e "ssh -p $REMOTE_SSH_PORT" \
      --exclude-from="$DEPLOYIGNORE_FILE" \
      $DEPLOY_PATHS "$REMOTE_SSH:$REMOTE_ROOT_DIR"
  )
  logLine
  log "🔥 Would clear the cache at $PRETTY_REMOTE_ENV"

  logLine
  log "✅ ${GREEN}${BOLD}[ DRY-RUN ]${NORMAL}${NC} Deploy preview to $PRETTY_REMOTE_ENV completed"
  ;;

run)

  case $DEPLOY_STRATEGY in

  conservative)
    # Confirm the deployment if the deploy strategy is conservative
    log "🚀 Would you really like to deploy to $PRETTY_REMOTE_HOST" ?
    read -r -p "[y/n] " PROMPT_RESPONSE

    # Exit if not confirmed
    [[ "$PROMPT_RESPONSE" != "y" ]] && exit 1
    ;;

  esac

  log "🚀 ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Deploying to $PRETTY_REMOTE_ENV ..."

  # Execute rsync from $LOCAL_ROOT_DIR in a subshell to make sure we are staying in the current pwd
  (
    cd "$LOCAL_ROOT_DIR"
    rsync -avz --delete --relative \
      -e "ssh -p $REMOTE_SSH_PORT" \
      --exclude-from="$DEPLOYIGNORE_FILE" \
      $DEPLOY_PATHS "$REMOTE_SSH:$REMOTE_ROOT_DIR"
  )

  log "\n✅ ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Deploy to $PRETTY_REMOTE_ENV completed"

  logLine

  runRemoteTasks deploy

  log "\n✅ Done! Be sure to check if everything works as expected on your $PRETTY_REMOTE_ENV site:"
  log "\n${GREEN}$REMOTE_PROTOCOL://$REMOTE_HOST${NC}"
  log ""
  ;;

*)
  logError $USAGE_MESSAGE
  ;;

esac
