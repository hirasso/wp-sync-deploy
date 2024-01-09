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

# Font Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export BLUE="\033[0;34m"
export NC='\033[0m' # No Color

# Font styles
export BOLD=$(tput bold)
export NORMAL=$(tput sgr0)

# Required positional arguments
JOB_NAME="$1"
REMOTE_ENV="$2"

# Print a message and exit with code 1
errorOut() {
    printf "\n🚨${BOLD}${RED} $1";
    exit 1;
}

# The directory relative to the script
DIR=$(pwd)
SCRIPT_DIR=$(realpath $(dirname $0))

# Deployment to production will only be possible from these two branches
MAIN_BRANCH="master|main"

# Find the closest file in parent directories
# @see https://unix.stackexchange.com/a/573499/504158
findUp() {
    local file="$1"
    local dir="$2"

    test -e "$dir/$file" && echo "$dir/$file" && return 0
    [ '/' = "$dir" ] && return 0 # couldn't find a way to handle return code 1, so leaving it at zero for now

    findUp "$file" "$(dirname "$dir")"
}

# Find the closest .env file
ENV_FILE=$(findUp ".env" $SCRIPT_DIR)
[ -z "$ENV_FILE" ] && errorOut "No matching .env file found"

# Make env vars available everywhere
# @see https://stackoverflow.com/a/30969768/586823
set -o allexport
source $ENV_FILE
set +o allexport

# Validate the dir this script should be called from
if [[ "$DIR" == "$SCRIPT_DIR" ]]; then
    errorOut "This script should always be called from the parent directory"
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

# Set SSH paths based on provided environment (production/staging)
case $REMOTE_ENV in

    production)
        # Define your production vars
        export REMOTE_URL=$PROD_URL
        export SSH_USER=$PROD_SSH_USER
        export SSH_HOST=$PROD_SSH_HOST
        export SSH_PATH=$PROD_WEB_ROOT
    ;;

    staging)
        # Define your staging vars
        export REMOTE_URL=$STAGING_URL
        export SSH_USER=$STAGING_SSH_USER
        export SSH_HOST=$STAGING_SSH_HOST
        export SSH_PATH=$STAGING_WEB_ROOT
    ;;

    *)
        errorOut "Please provide the remote environment (production or staging)"
    ;;
esac

export REMOTE_CACHE_PATH="$SSH_PATH$PROD_CACHE_PATH"

ERROR_MESSAGE="That did not work. Please check your command and try again"

# Checks if a file exists on a remote server
checkRemoteFile() {
    ssh $SSH_USER@$SSH_HOST "[ -e \"$SSH_PATH/$1\" ] && echo 1";
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
    eval "ssh $SSH_USER@$SSH_HOST 'cd $SSH_PATH; [ -f \"$SSH_PATH/.allow-deployment\" ] && echo yes'"
}

case $JOB_NAME in

    # SYNC the production database to the local database
    # @see https://gist.github.com/samhernandez/25e26269438e4ceaf37f
    sync)
        # Confirmation dialog
        read -r -p "
        🔄  Would you really like to 💥 ${BOLD}reset the local database${NORMAL} ($DEV_URL)
        and sync from ${BOLD}$REMOTE_ENV${NORMAL} ($REMOTE_URL)? [y/N] " response

        # Exit if not confirmed
        [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]] && exit 1;

        # Activate maintenance mode
        wp maintenance-mode activate --skip-plugins="qtranslate-xt"

        REMOTE_FILE="remote-$REMOTE_DB_NAME.sql"
        LOCAL_FILE="local-$LOCAL_DB_NAME.sql"

        printf "\r\n💾 Dumping remote database to $REMOTE_FILE\n"
        eval "ssh $SSH_USER@$SSH_HOST 'mysqldump -h $REMOTE_DB_HOST -u$REMOTE_DB_USER -p$REMOTE_DB_PASS $REMOTE_DB_NAME --default-character-set=utf8mb4' > '$SCRIPT_DIR/$REMOTE_FILE'"

        printf "\r\n💾 Dumping local database to $LOCAL_FILE\n"
        eval "mysqldump -h $LOCAL_DB_HOST -u$LOCAL_DB_USER -p$LOCAL_DB_PASS $LOCAL_DB_NAME > '$SCRIPT_DIR/$LOCAL_FILE'"

        printf "\r\n⬇️ Importing remote database into local database"
        eval "mysql -h $LOCAL_DB_HOST -u$LOCAL_DB_USER -p$LOCAL_DB_PASS $LOCAL_DB_NAME < '$SCRIPT_DIR/$REMOTE_FILE'"

        rm "$SCRIPT_DIR/$REMOTE_FILE";
        rm "$SCRIPT_DIR/$LOCAL_FILE";

        printf "\r\n🔄 Replacing $REMOTE_URL with $DEV_URL..."
        wp search-replace "$REMOTE_URL" "$DEV_URL" --all-tables-with-prefix --skip-plugins="qtranslate-xt"

        printf "\n🔄 Syncing ACF field groups..."
        # @see https://gist.github.com/hirasso/c48c04def92f839f6264349a1be773b3
        # If you don't need this, go ahead and comment it out
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
            errorOut "Remote root not allowed for deployment (missing file .allow-deployment): ${GREEN}$SSH_PATH";
        fi;

        # Check for a matching PHP version between the local and remote environment
        chmod +x "$SCRIPT_DIR/check-php.sh"
        "$SCRIPT_DIR/check-php.sh"
        exit;

        DEPLOY_MODE="dry"
        if [[ ! -z "${3+x}" && $3 == 'run' ]]; then
            DEPLOY_MODE="run";
        fi

        case $DEPLOY_MODE in

            # ./deployment/deploy.sh deploy production
            dry)
                printf "\r\n🚀 ${GREEN}${BOLD}[ DRY-RUN ]${NORMAL}${NC} Deploying to production\r\n"
                rsync --dry-run -az --delete --progress --relative --exclude-from "$SCRIPT_DIR/.deployignore" $DEPLOY_DIRS "$SSH_USER@$SSH_HOST:$SSH_PATH" | tee "$SCRIPT_DIR/.deploy-$REMOTE_ENV.log"
            ;;

            # ./deployment/deploy.sh deploy production run
            run)
                # Build assets in your theme. Deactivate/modify this if you don't have a npm script called "build"
                cd "$DIR/content/themes/$WP_THEME";
                npm run build
                cd $DIR;

                # Deploy
                printf "\r\n🚀 ${GREEN}${BOLD}[ LIVE ]${NORMAL}${NC} Deploying to production…"
                rsync -avz --delete --relative --exclude-from "$SCRIPT_DIR/.deployignore" $DEPLOY_DIRS "$SSH_USER@$SSH_HOST:$SSH_PATH" | tee "$SCRIPT_DIR/.deploy-$REMOTE_ENV.log"

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