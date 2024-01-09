#!/usr/bin/env bash

# SYNCING AND DEPLOYMENT for WordPress
#
# Please have a look at the .env.example to define your variables (outside of git):

set -o errexit
set -o nounset
set -o pipefail

# Font Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE="\033[0;34m"
NC='\033[0m' # No Color

# Font styles
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Print a message and exit with code 1
errorOut() {
    printf "\n🚨${BOLD}${RED} $1";
    exit 1;
}

# The directory relative to the script
DIR=$(pwd)
SCRIPT_DIR=$(realpath $(dirname $0))

MAIN_BRANCH="master|main"

# Find the closest file in parent directories
# @see https://unix.stackexchange.com/a/573499/504158
# Example `findUp ".env" $(dirname "$0")`
findUp() {
    local file="$1"
    local dir="$2"

    test -e "$dir/$file" && echo "$dir/$file" && return 0
    [ '/' = "$dir" ] && return 1

    findUp "$file" "$(dirname "$dir")"
}

# Make env vars available everywhere
# @see https://stackoverflow.com/a/30969768/586823
set -o allexport
source $(findUp ".env" $SCRIPT_DIR)
set +o allexport

# Validate the dir this script should be called from
if [[ "$DIR" == "$SCRIPT_DIR" ]]; then
    errorOut "This script should be called from the parent directory"
fi;

# Echo the git branch from the theme
getThemeBranch() {
    cd "$DIR/content/themes/$WP_THEME";
    git branch --show;
    cd $DIR;
}

# Exit early if we received no arguments
if [ $# -eq 0 ]
then
    errorOut "No arguments provided, exiting..."
fi

REMOTE_ENV=$2

case $REMOTE_ENV in

    production)
        # Define your production vars
        REMOTE_URL=$PROD_URL
        SSH_USER=$PROD_SSH_USER
        SSH_HOST=$PROD_SSH_HOST
        SSH_PATH=$PROD_WEB_ROOT
    ;;

    staging)
        # Define your staging vars
        REMOTE_URL=$STAGING_URL
        SSH_USER=$STAGING_SSH_USER
        SSH_HOST=$STAGING_SSH_HOST
        SSH_PATH=$STAGING_WEB_ROOT
    ;;

    *)
        errorOut "Please provide the remote environment (production or staging)"
    ;;
esac

SSH_ADDRESS="$SSH_USER@$SSH_HOST:$SSH_PATH"

REMOTE_CACHE_PATH="$SSH_PATH$PROD_CACHE_PATH"

ERROR_MESSAGE="That did not work. Please check your command and try again"

JOB_NAME="$1"

# Checks if a file exists on a remote server
checkRemoteFile() {
    ssh $SSH_USER@$SSH_HOST "[ -e \"$PROD_WEB_ROOT/$1\" ] && echo 1";
}

# Validate that the required directories exist locally and remotely
for deploy_dir in $DEPLOY_DIRS; do
    # check on remote machine
    if [[ $(checkRemoteFile $deploy_dir) != 1 ]]; then
        errorOut "The directory ${GREEN}$deploy_dir${RED} does not exist on the remote server"
    fi
    # check on local machine
    if [ ! -d "$DIR/$deploy_dir" ]; then
        errorOut "The directory ${GREEN}$DIR/$deploy_dir${RED} does not exist locally"
    fi
done


isRemoteRootAllowed() {
    eval "ssh $SSH_USER@$SSH_HOST 'cd $PROD_WEB_ROOT; [ -f \"$PROD_WEB_ROOT/.allow-deployment\" ] && echo yes'"
}

case $JOB_NAME in

    # SYNC the production database to the local database
    # @see https://gist.github.com/samhernandez/25e26269438e4ceaf37f
    sync)
        # Activate maintenance mode
        wp maintenance-mode activate --skip-plugins="qtranslate-xt"

        REMOTE_FILE="remote-$REMOTE_DB_NAME.sql"
        LOCAL_FILE="local-$LOCAL_DB_NAME.sql"

        printf "\n💾 Dumping remote database to $REMOTE_FILE\n"
        eval "ssh $SSH_USER@$SSH_HOST 'mysqldump -h $REMOTE_DB_HOST -u$REMOTE_DB_USER -p$REMOTE_DB_PASS $REMOTE_DB_NAME --default-character-set=utf8mb4' > '$SCRIPT_DIR/$REMOTE_FILE'"

        printf "\n💾 Dumping local database to $LOCAL_FILE\n"
        eval "mysqldump -h $LOCAL_DB_HOST -u$LOCAL_DB_USER -p$LOCAL_DB_PASS $LOCAL_DB_NAME > '$SCRIPT_DIR/$LOCAL_FILE'"

        printf "\n⬇️ Importing remote database into local database"
        eval "mysql -h $LOCAL_DB_HOST -u$LOCAL_DB_USER -p$LOCAL_DB_PASS $LOCAL_DB_NAME < '$SCRIPT_DIR/$REMOTE_FILE'"

        rm "$SCRIPT_DIR/$REMOTE_FILE";
        rm "$SCRIPT_DIR/$LOCAL_FILE";

        printf "\n🔄 Replacing $PROD_URL with $DEV_URL..."
        wp search-replace "$PROD_URL" "$DEV_URL" --all-tables-with-prefix --skip-plugins="qtranslate-xt"

        printf "\n🔄 Syncing ACF field groups..."
        wp rhau acf-sync-field-groups --skip-plugins="qtranslate-xt"

        # Deactivate maintenance mode
        wp maintenance-mode deactivate --skip-plugins="qtranslate-xt"

        printf "\n\n✅ Done!"
    ;;

    # DEPLOY to production or staging server
    deploy)
        # Allow deployment to production only from $MAIN_BRANCH
        if [[ $REMOTE_ENV == "production" && ! $(getThemeBranch) =~ $MAIN_BRANCH ]]; then
            errorOut "Deploying to production is only allowed from ${NC}\$MAIN_BRANCH${RED} ($MAIN_BRANCH)"
        fi

        # Validate if the remote root is writable
        if [[ $(isRemoteRootAllowed) != 'yes' ]]; then
            errorOut "Remote root not allowed for deployment (missing file .allow-deployment): ${GREEN}$PROD_WEB_ROOT";
        fi;

        DEPLOY_MODE="dry"
        if [[ ! -z "${3+x}" && $3 == 'run' ]]; then
            DEPLOY_MODE="run";
        fi

        case $DEPLOY_MODE in

            # ./deployment/deploy.sh deploy production
            dry)
                printf "\r\n🚀 ${GREEN}${BOLD}[ DRY-RUN ]${NORMAL}${NC} Deploying to production\r\n"
                rsync --dry-run -az --delete --progress --relative --exclude-from "$SCRIPT_DIR/.deployignore" $DEPLOY_DIRS $SSH_ADDRESS | tee "$SCRIPT_DIR/.deploy-$REMOTE_ENV.log"
            ;;

            # ./deployment/deploy.sh deploy production run
            run)
                # Build assets in theme
                cd "$DIR/content/themes/$WP_THEME";
                npm run build
                cd $DIR;

                # Deploy
                printf "\r\n🚀 ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Deploying to production…"
                rsync -avz --delete --relative --exclude-from "$SCRIPT_DIR/.deployignore" $DEPLOY_DIRS $SSH_ADDRESS | tee "$SCRIPT_DIR/.deploy-$REMOTE_ENV.log"

                # Clear the cache folder
                printf "\r\n${BOLD}Clearing the cache cache at:${NORMAL}\r\n $REMOTE_CACHE_PATH"
                ssh $SSH_USER@$SSH_HOST "rm -r $REMOTE_CACHE_PATH"
                exit 0;
            ;;

            *)
                errorOut $ERROR_MESSAGE
            ;;

        esac
    ;;

    # Nothing matched, print an error
    *)
        errorOut "$ERROR_MESSAGE"
    ;;

esac