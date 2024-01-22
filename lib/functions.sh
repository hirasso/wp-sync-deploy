#!/usr/bin/env bash

# Font Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE="\033[0;36m"
NC='\033[0m' # No Color

# Font styles
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Log a string and redirect to stderr
# @see https://unix.stackexchange.com/a/331620/504158
function log() {
    printf "\n\r$1 " >&2
}

# Log an empty line
function logLine() {
    log ""
}

# Log an error message and exit with code 1
function logError() {
    log "🚨${BOLD}${RED} Error: ${NC}$1"
    exit 1
}

# Log a success message
function logSuccess() {
    log "✅${BOLD}${GREEN} Success: ${NC}$1"
}

# Normalize a path:
# Prepends a leading slash to the provided path
# to prevent realpath from making the path absolute
function normalizePath() {
    realpath -sm "/$1"
}

# Trim a leading slash from a string
function trimLeadingSlash() {
    local input_path="$1"
    local trimmed_path="${input_path#/}"
    echo "$trimmed_path"
}

# Find the closest file in parent directories
# @see https://unix.stackexchange.com/a/573499/504158
function findUp() {
    local file="$1"
    local dir="$2"

    test -e "$dir/$file" && echo "$dir/$file" && return 0
    [ "/" = "$dir" ] && return 0 # couldn't find a way to handle return code 1, so leaving it at zero for now

    findUp "$file" "$(dirname "$dir")"
}

# Check the git branch from the theme
function checkProductionBranch() {
    # Bail early if not deploying to production
    [[ $REMOTE_ENV != "production" ]] && return

    # Get the branch from the theme
    cd "$LOCAL_WEB_ROOT/content/themes/$WP_THEME"
    BRANCH=$(git branch --show)
    cd $LOCAL_WEB_ROOT

    # Check it
    if [[ ! $BRANCH =~ $MAIN_BRANCH ]]; then
        logError "Deploying to production is only allowed from ${NC}\$MAIN_BRANCH${RED} ($MAIN_BRANCH)"
    else
        logSuccess "Branch ${BLUE}$BRANCH${NC} allowed in production"
    fi
}

# Check if there is a file `.allow-deployment` present at the remote root
function checkIsRemoteAllowed() {
    local FILE_PATH="$REMOTE_WEB_ROOT/.allow-deployment"
    IS_ALLOWED=$(ssh "$REMOTE_SSH" test -e "$FILE_PATH" && echo "yes" || echo "no")

    if [[ $IS_ALLOWED != "yes" ]]; then
        logError "Remote root ${RED}not allowed${NC} for deployment (missing file ${GREEN}.allow-deployment${NC})"
    else
        logSuccess "${BLUE}.allow-deployment${NC} detected on remote server"
    fi
}

# Create a hash from a string
function createHash() {
    echo "$1" | sha256sum | head -c 10
}

# Construct CURL args for a URL with optional -u (HTTP AUTH) flag
function constructCURLArgs() {
    FILE="$1"
    ENV="$2"

    local PROTOCOL
    local HOST
    local AUTH

    case $ENV in
    local)
        HOST=$LOCAL_HOST
        PROTOCOL=$LOCAL_PROTOCOL
        AUTH=$LOCAL_HTTP_AUTH
        ;;
    remote)
        HOST=$REMOTE_HOST
        PROTOCOL=$REMOTE_PROTOCOL
        AUTH=$REMOTE_HTTP_AUTH
        ;;
    *)
        logError "Usage: constructCURLArgs file <local|remote>"
        ;;

    esac

    if [[ -n "$AUTH" ]]; then
        echo "-u $AUTH $PROTOCOL://$HOST/$FILE"
    else
        echo "$PROTOCOL://$HOST/$FILE"
    fi
}

# Check the PHP versions on the command line between two environments
function checkCommandLinePHPVersions() {
    local LOCAL_OUTPUT=$(php -r 'echo PHP_VERSION;')
    local LOCAL_VERSION=${LOCAL_OUTPUT:0:3}
    log "- Command line PHP version at $PRETTY_LOCAL_ENV server: ${BLUE}$LOCAL_VERSION${NC}"

    local REMOTE_OUTPUT=$(ssh "$REMOTE_SSH" "$REMOTE_PHP_BINARY -r 'echo PHP_VERSION;'")
    local REMOTE_VERSION=${REMOTE_OUTPUT:0:3}
    log "- Command line PHP version at $PRETTY_REMOTE_ENV server: ${BLUE}$REMOTE_VERSION${NC}"

    if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
        log "🚨 Command line PHP version mismatch detected. Proceed anyways?"
        read -r -p "[y/n] " PROMPT_RESPONSE

        # Exit early if not confirmed
        if [[ "$PROMPT_RESPONSE" != "y" ]]; then
            log "🚨 Deploy to $PRETTY_REMOTE_ENV canceled ..."
            exit
        fi
    else
        logSuccess "Command line PHP versions match between $PRETTY_LOCAL_ENV and $PRETTY_REMOTE_ENV"
    fi
}

# Check the web-facing PHP versions between two environments
function checkWebFacingPHPVersions() {
    # Append a hash to the test file to make it harder to detect on the remote server
    local HASH=$(createHash $REMOTE_WEB_ROOT)
    FILE_NAME="___wp-sync-deploy-php-version-$HASH.php"

    local LOCAL_CURL_ARGS=$(constructCURLArgs "$FILE_NAME" local)
    local REMOTE_CURL_ARGS=$(constructCURLArgs "$FILE_NAME" remote)

    # Create the test file on the local server
    echo "<?= phpversion();" >"$LOCAL_WEB_ROOT/$FILE_NAME"
    # Get the output of the test file
    local LOCAL_OUTPUT=$(curl -s $LOCAL_CURL_ARGS)
    # Cleanup the test file
    rm "$LOCAL_WEB_ROOT/$FILE_NAME"
    # substring from position 0-3
    local LOCAL_VERSION=${LOCAL_OUTPUT:0:3}
    # validate if the version looks legit
    [[ ! $LOCAL_VERSION =~ ^[0-9]\. ]] && logError "Invalid PHP version number: $LOCAL_VERSION"
    # Log the detected PHP version
    log "- Web-facing PHP version at $PRETTY_LOCAL_HOST: ${BLUE}$LOCAL_VERSION${NC}"

    # Create the test file on the remote server
    ssh "$REMOTE_SSH" "cd $REMOTE_WEB_ROOT; echo '<?= phpversion();' > ./$FILE_NAME"

    # Get the output of the test file
    local REMOTE_OUTPUT=$(curl -s $REMOTE_CURL_ARGS)

    # Cleanup the test file
    ssh "$REMOTE_SSH" "cd $REMOTE_WEB_ROOT; rm ./$FILE_NAME"
    # substring from position 0-3
    local REMOTE_VERSION=${REMOTE_OUTPUT:0:3}
    # validate if the version looks legit
    [[ ! $REMOTE_VERSION =~ ^[0-9]\. ]] && logError "Invalid PHP version number: $REMOTE_VERSION"
    # Log the detected PHP version
    log "- Web-facing PHP version at $PRETTY_REMOTE_HOST: ${BLUE}$REMOTE_VERSION${NC}"

    # Error out if the two PHP versions aren't a match
    if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
        logError "PHP version mismatch, aborting"
    else
        logSuccess "Web-facing PHP versions match between $PRETTY_LOCAL_ENV and $PRETTY_REMOTE_ENV"
    fi
}

# Check if a file exists on a remote server
function checkRemoteFile() {
    ssh $REMOTE_SSH "[ -e \"$1\" ] && echo 1 || echo 0"
}

# Validate that the required directories exist locally and remotely
function checkDirectories() {
    for DEPLOY_DIR in $DEPLOY_DIRS; do
        # check on local machine
        if [ ! -d "$LOCAL_WEB_ROOT/$DEPLOY_DIR" ]; then
            logError "The directory ${RED}$LOCAL_WEB_ROOT/$DEPLOY_DIR${NC} does not exist locally"
        fi
        # check on remote machine
        if [[ $(checkRemoteFile "$REMOTE_WEB_ROOT/$DEPLOY_DIR") != 1 ]]; then
            logError "The directory ${RED}$DEPLOY_DIR${RED} does not exist on the remote server"
        fi
    done

    logSuccess "All directories exist in both environments"
}

# Get the remote wp-cli.phar file name
function getRemoteWPCLIFilename() {
    local HASH=$(createHash $REMOTE_WEB_ROOT)
    echo "wp-cli-$HASH.phar"
}

# Install WP-CLI on the remote server
# This makes it possible to easily run wp-cli with a custom command line PHP version

function installRemoteWpCli() {
    # Get the hashed filename of the wp-cli.phar
    local WP_CLI_PHAR=$(getRemoteWPCLIFilename)

    # Don't install twice
    if [ $(checkRemoteFile "$REMOTE_WEB_ROOT/$WP_CLI_PHAR") == 1 ]; then
        logSuccess "WP-CLI available on the remote server."
        return
    fi

    log "🚀 Installing WP-CLI on the remote server ..."

    RESULT=$(ssh "$REMOTE_SSH" "cd $REMOTE_WEB_ROOT && curl -s -o $WP_CLI_PHAR https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && echo success")

    [ ! "$RESULT" == 'success' ] && logError "Failed to install WP-CLI on the server"

    logSuccess "WP-CLI installed on the remote server\n"
}

# Run wp cli on a remote server, forwarding all arguments
function wpRemote() {
    local ARGS="$@"

    # Install WP-CLI on remote server
    installRemoteWpCli

    # Log an empty line
    logLine

    # Get the hashed file name of the wp-cli.phar
    local WP_CLI_PHAR=$(getRemoteWPCLIFilename)

    # Construct the remote command
    local COMMAND="cd $REMOTE_WEB_ROOT && $REMOTE_PHP_BINARY ./$WP_CLI_PHAR $ARGS"

    # Exectute the command
    ssh "$REMOTE_SSH" "$COMMAND"
}

# Runs the task file on the remote server
function runRemoteTasks() {
    [ ! -e "$TASKS_FILE" ] && return

    local TASK="$1"

    log "Running ${BLUE}wp eval-file wp-sync-deploy.tasks.php $TASK${NC} on $PRETTY_REMOTE_ENV server ... \n"

    # Upload the file to the remote web root
    scp -q "$TASKS_FILE" "$REMOTE_SSH:$REMOTE_WEB_ROOT"

    # Execute the file on the remote server
    wpRemote eval-file "$REMOTE_WEB_ROOT/wp-sync-deploy.tasks.php" "$TASK"
}

# Pull the remote database into the local database
function pullDatabase() {
    # Confirmation dialog
    log "🔄 Would you really like to 💥 ${RED}reset the local database${NC} ($PRETTY_LOCAL_HOST)"
    log "and sync from ${BOLD}$REMOTE_ENV${NORMAL} ($PRETTY_REMOTE_HOST)?"
    read -r -p "[y/n] " PROMPT_RESPONSE

    # Return early if not confirmed
    [[ "$PROMPT_RESPONSE" != "y" ]] && exit 1

    # Activate maintenance mode
    wp maintenance-mode activate &&

        # Import the remote database into the local database
        wpRemote db export --default-character-set=utf8mb4 - | wp db import - &&

        # Replace the remote URL with the local URL
        wp search-replace "//$REMOTE_HOST" "//$LOCAL_HOST" --all-tables-with-prefix

    # Deactivate maintenance mode
    wp maintenance-mode deactivate

    # Run tasks on the local server
    wp eval-file "$TASKS_FILE" sync

    # Delete local transients
    wp transient delete --all

    logLine && logSuccess "Database imported from ${GREEN}$REMOTE_URL${NC} to ${GREEN}$LOCAL_URL${NC}"
}

# Push the local database to the remote environment
function pushDatabase() {

    [ "$REMOTE_ENV" == "production" ] && logError "Syncing to the production database is not allowed for security reasons"

    # Confirmation dialog
    log "🚨 Would you really like to 💥 ${RED}reset the $REMOTE_ENV database${NC} ($PRETTY_REMOTE_HOST)"
    log "and ${RED}push from local${NC}?"
    read -r -p "Type '$REMOTE_HOST' to continue ... " PROMPT_RESPONSE

    # Return early if not confirmed
    [[ "$PROMPT_RESPONSE" != "$REMOTE_HOST" ]] && logError "Permission denied, aborting ..."

    # Activate maintenance mode on the remote server
    wpRemote maintenance-mode activate &&

        # Import the local database into the remote database
        wp db export --default-character-set=utf8mb4 - | wpRemote db import - &&

        # Replace the local URL with the remote URL
        wpRemote search-replace "//$LOCAL_HOST" "//$REMOTE_HOST" --all-tables-with-prefix

    # Deactivate maintenance mode on the remote server
    wpRemote maintenance-mode deactivate

    # Run tasks on the remote server
    runRemoteTasks sync

    # Delete remote transients
    wpRemote transient delete --all


    logLine && logSuccess "Pushed the database from ${GREEN}$LOCAL_URL${NC} to ${GREEN}$REMOTE_URL${NC}"
}