#!/usr/bin/env bash

# SYNC AND DEPLOY for WordPress
#
# Please have a look at the .env.example to define your variables (outside of this folder)
#
# COMMANDS provided by this script
#
# Sync the database from your production or staging server:
# `./wp-sync-deploy/wp-sync-deploy.sh sync <production|staging>`
#
# Deploy to production or staging (dry)
# `./wp-sync-deploy/wp-sync-deploy.sh deploy <production|staging>`
#
# Deploy to production or staging (RUN!)
# `./wp-sync-deploy/wp-sync-deploy.sh deploy <production|staging> run`

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
USAGE_MESSAGE="Usage: https://github.com/hirasso/wp-sync-deploy#usage

./wp-sync-deploy/wp-sync-deploy.sh [<sync|deploy>] [[<production|staging>] [run]] "

# Exit early if we received no arguments
[ $# -eq 0 ] && log "$USAGE_MESSAGE" && exit 1

# Required positional arguments
JOB_NAME="$1"
REMOTE_ENV="$2"

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
    ;;

    staging)
        # Define your staging vars
        export REMOTE_HOST=$STAG_HOST
        export REMOTE_PROTOCOL=$STAG_PROTOCOL
        export REMOTE_HTTP_AUTH=$STAG_HTTP_AUTH
        export REMOTE_SSH=$STAG_SSH
        export REMOTE_WEB_ROOT=$STAG_WEB_ROOT
    ;;

    *)
        logError "Please provide the remote environment (production or staging)"
    ;;
esac

# Construct the directories to deploy from the provided env variables
export DEPLOY_DIRS="$WP_CORE_DIR $WP_CONTENT_DIR/plugins $WP_CONTENT_DIR/themes/$WP_THEME"

case $JOB_NAME in

    # SYNC the production database to the local database
    # @see https://gist.github.com/samhernandez/25e26269438e4ceaf37f
    sync)
        # Confirmation dialog
        log "🔄 Would you really like to 💥 ${RED}reset the local database${NC} ($LOCAL_HOST)"
        log "and sync from ${BLUE}$REMOTE_ENV${NC} ($REMOTE_HOST)?"
        read -r -p "[y/N] " PROMPT_RESPONSE

        # Return early if not confirmed
        [[ $(checkPromptResponse "$PROMPT_RESPONSE") != 1 ]] && exit 1;

        # Activate maintenance mode
        wp maintenance-mode activate

        REMOTE_FILE="remote-$REMOTE_DB_NAME.sql"
        LOCAL_FILE="local-$LOCAL_DB_NAME.sql"

        log "💾 Dumping remote database to ${GREEN}$REMOTE_FILE${NC}"
        SSH_COMMAND="mysqldump --no-tablespaces -h$REMOTE_DB_HOST -u$REMOTE_DB_USER -p$REMOTE_DB_PASS $REMOTE_DB_NAME --default-character-set=utf8mb4"
        ssh $REMOTE_SSH "$SSH_COMMAND" > "$SCRIPT_DIR/$REMOTE_FILE"

        log "💾 Dumping local database to ${GREEN}$LOCAL_FILE${NC}"
        MYSQL_PWD="$LOCAL_DB_PASS" mysqldump -h "$LOCAL_DB_HOST" -u"$LOCAL_DB_USER" "$LOCAL_DB_NAME" --default-character-set=utf8mb4 > "$SCRIPT_DIR/$LOCAL_FILE"

        log "🍭 Importing ${GREEN}remote${NC} database into the ${GREEN}local${NC} database"
        MYSQL_PWD="$LOCAL_DB_PASS" mysql -h "$LOCAL_DB_HOST" -u"$LOCAL_DB_USER" "$LOCAL_DB_NAME" < "$SCRIPT_DIR/$REMOTE_FILE"

        rm "$SCRIPT_DIR/$REMOTE_FILE";

        log "\n🔄 Replacing ${GREEN}$REMOTE_HOST${NC} with ${GREEN}$LOCAL_HOST${NC} ..."

        logLine

        # Replace the remote URL with the local URL
        wp search-replace "//$REMOTE_HOST" "//$LOCAL_HOST" --all-tables-with-prefix

        # Deactivate maintenance mode
        wp maintenance-mode deactivate

        deleteSuperCacheDir local

        log "\n🔄 Syncing ACF field groups ..."
        # @see https://gist.github.com/hirasso/c48c04def92f839f6264349a1be773b3
        # If you don't need this, go ahead and comment it out
        wp rhau acf-sync-field-groups

        # Delete local transients
        wp transient delete --all

        log "\n✅ Done!"
    ;;

    # DEPLOY to the production or staging server
    deploy)
        log "🚀 Would you really like to deploy to ${GREEN}$REMOTE_HOST${NC}" ?
        read -r -p "[y/N] " PROMPT_RESPONSE

        # Return early if not confirmed
        [[ $(checkPromptResponse "$PROMPT_RESPONSE") != 1 ]] && exit 1;

        # Perform checks
        checkIsRemoteAllowed
        checkDirectories
        checkPHPVersions
        checkProductionBranch
        logSuccess "All checks successful! Proceeding ..."
        logLine

        DEPLOY_MODE="dry"
        if [[ ! -z "${3+x}" && $3 == 'run' ]]; then
            DEPLOY_MODE="run";
        fi

        case $DEPLOY_MODE in

            dry)
                log "🚀 ${GREEN}${BOLD}[ DRY-RUN ]${NORMAL}${NC} Deploying to ${GREEN}$REMOTE_ENV${NC} ..."

                # Execute rsync from $LOCAL_WEB_ROOT in a subshell to make sure we are staying in the current pwd
                (
                    cd "$LOCAL_WEB_ROOT";
                    rsync --dry-run -avz --delete --relative \
                        --exclude-from="$SCRIPT_DIR/.deployignore" \
                        $DEPLOY_DIRS "$REMOTE_SSH:$REMOTE_WEB_ROOT"
                )
                logLine
                log "🔥 Would clear the cache at ${GREEN}$REMOTE_ENV${NC}"

                logLine
                log "✅ ${GREEN}${BOLD}[ DRY-RUN ]${NORMAL}${NC} Deploy preview to ${GREEN}$REMOTE_ENV${NC} completed"
            ;;

            run)
                log "🚀 ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Deploying to ${GREEN}$REMOTE_ENV${NC} ..."

                # Execute rsync from $LOCAL_WEB_ROOT in a subshell to make sure we are staying in the current pwd
                (
                    cd "$LOCAL_WEB_ROOT";
                    rsync -avz --delete --relative \
                        --exclude-from="$SCRIPT_DIR/.deployignore" \
                        $DEPLOY_DIRS "$REMOTE_SSH:$REMOTE_WEB_ROOT"
                )

                log "\n✅ ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Deploy to ${GREEN}$REMOTE_ENV${NC} completed"

                wpRemote rewrite flush
                wpRemote transient delete --all

                deleteSuperCacheDir remote

                REMOTE_URL=$(constructURL remote)
                log "\n✅ Done! Be sure to check ${GREEN}$REMOTE_ENV${NC} for possible regressions:"
                log "\n${GREEN}$REMOTE_URL${NC}"
            ;;

            *)
                logError $USAGE_MESSAGE
            ;;

        esac
    ;;

    # Nothing matched, print an error
    *)
        logError "$USAGE_MESSAGE"
    ;;

esac