#!/usr/bin/env bash

# Log a string
function log() {
    printf "\r\n$1 ";
}

# Log an empty line
function logLine() {
    log ""
}

# Log an error message and exit with code 1
function logError() {
    log "🚨${BOLD}${RED} Error: ${NC}$1";
    exit 1;
}

# Log a success message
function logSuccess() {
    log "✅${BOLD}${GREEN} Success: ${NC}$1";
}

# Remove unnecessary slashes from a path
# Prepends a leading slash to the provided path
# to prevent realpath from making the path absolute
#
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
    [ '/' = "$dir" ] && return 0 # couldn't find a way to handle return code 1, so leaving it at zero for now

    findUp "$file" "$(dirname "$dir")"
}

# Check the git branch from the theme
function checkProductionBranch() {
    # Bail early if not deploying to production
    [[ $REMOTE_ENV != "production" ]] && return;

    # Get the branch from the theme
    cd "$LOCAL_WEB_ROOT/content/themes/$WP_THEME";
    BRANCH=$(git branch --show);
    cd $LOCAL_WEB_ROOT;

    # Check it
    if [[ ! $BRANCH =~ $MAIN_BRANCH ]]; then
        logError "Deploying to production is only allowed from ${NC}\$MAIN_BRANCH${RED} ($MAIN_BRANCH)"
    else
        logSuccess "Branch $BRANCH allowed in production"
    fi
}

# Check if there is a file `.allow-deployment` present at the remote root
function checkIsRemoteAllowed() {
    local FILE_PATH="$REMOTE_WEB_ROOT/.allow-deployment"
    IS_ALLOWED=$(ssh "$REMOTE_SSH" test -e "$FILE_PATH" && echo "yes" || echo "no")

    if [[ $IS_ALLOWED != "yes" ]]; then
        logError "Remote root ${RED}not allowed${NC} for deployment (missing file ${GREEN}.allow-deployment${NC})"
    else
        logSuccess ".allow-deployment detected on remote server"
    fi;
}

# Create a hash from a string
function createHash() {
    echo "$1" | sha256sum | head -c 10
}

# Construct a URL
function constructURL() {
    ENV="$1"

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
            logError "Usage: constructURL <local|remote>"
        ;;

    esac

    if [[ -n "$AUTH" ]]; then
        echo "$PROTOCOL://$AUTH@$HOST"
    else
        echo "$PROTOCOL://$HOST"
    fi
}

# Check the web-facing PHP versions between two environments
function checkWebFacingPHPVersions() {
    local LOCAL_URL=$(constructURL local)
    local REMOTE_URL=$(constructURL remote)
    local FILE_NAME="___wp-sync-deploy-php-version.php"

    # Create the test file on the local server
    echo "<?= phpversion();" > "$LOCAL_WEB_ROOT/$FILE_NAME"
    # Get the output of the test file
    local LOCAL_OUTPUT=$(curl -s "$LOCAL_URL/$FILE_NAME")
    # Cleanup the test file
    rm "$LOCAL_WEB_ROOT/$FILE_NAME"
    # substring from position 0-3
    local LOCAL_VERSION=${LOCAL_OUTPUT:0:3}
    # validate if the version looks legit
    [[ ! $LOCAL_VERSION =~ ^[0-9]\. ]] && logError "Invalid PHP version number: $LOCAL_VERSION"
    # Log the detected PHP version
    log "- PHP version ${GREEN}$LOCAL_VERSION${NC} detected at ${BOLD}$LOCAL_HOST${NC}"


    # Append a hash to the remote test file to make it harder to detect
    local HASH=$(createHash $REMOTE_WEB_ROOT)
    FILE_NAME="___wp-sync-deploy-php-version-$HASH.php"
    # Create the test file on the remote server
    ssh "$REMOTE_SSH" "cd $REMOTE_WEB_ROOT; echo '<?= phpversion();' > ./$FILE_NAME"
    # Get the output of the test file
    local REMOTE_OUTPUT=$(curl -s "$REMOTE_URL/$FILE_NAME")
    # Cleanup the test file
    ssh "$REMOTE_SSH" "cd $REMOTE_WEB_ROOT; rm ./$FILE_NAME"
    # substring from position 0-3
    local REMOTE_VERSION=${REMOTE_OUTPUT:0:3}
    # validate if the version looks legit
    [[ ! $REMOTE_VERSION =~ ^[0-9]\. ]] && logError "Invalid PHP version number: $REMOTE_VERSION"
    # Log the detected PHP version
    log "- PHP version ${GREEN}$REMOTE_VERSION${NC} detected at ${BOLD}$REMOTE_HOST${NC}"

    # Error out if the two PHP versions aren't a match
    if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
        logError "PHP version mismatch, aborting"
    else
        logSuccess "PHP versions match between environments"
    fi
}

# Checks if a file exists on a remote server
function checkRemoteFile() {
    ssh $REMOTE_SSH "[ -e \"$1\" ] && echo 1";
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

# Run wp cli on a remote server, forwarding all arguments
function wpRemote() {
    ARGS="$@"

    log "Would you like to run ${BLUE}wp $ARGS${NC} on the ${BOLD}$REMOTE_ENV${NORMAL} server?"
    read -r -p "[y/N] " PROMPT_RESPONSE

    # Return early if not confirmed
    [[ $(checkPromptResponse "$PROMPT_RESPONSE") != 1 ]] && return;

    log "proceeding ..."

    local PREFLIGHT=$(wp --ssh="$REMOTE_SSH$REMOTE_WEB_ROOT" option get home 2>&1)
    local FIRST_LINE=$(echo "$PREFLIGHT" | head -n 1)
    # Check for "error" or "command not found" in the response
    if [[ $PREFLIGHT == *"Error"* || $PREFLIGHT == *"command not found"* ]]; then
        log "🚨 Unable to run WP-CLI on ${BOLD}$REMOTE_ENV${NORMAL}: \n\n $PREFLIGHT"
        return;
    fi

    # preflight passed, exectute the command
    wp --ssh="$REMOTE_SSH$REMOTE_WEB_ROOT" $ARGS
}

# Checks a prompt response
checkPromptResponse() {
    (
        shopt -s nocasematch

        [[ "$1" =~ ^(yes|y)$ ]] && echo 1
    )
}

# Delete the supercache directory on either the local or remote server
deleteSuperCacheDir() {
    ENV="$1"

    local SUPERCACHE_DIR

    case $ENV in

        local)
            SUPERCACHE_DIR="$LOCAL_WEB_ROOT/$WP_CONTENT_DIR/cache/supercache"

            if [[ -d $SUPERCACHE_DIR ]]; then
                rm -r $SUPERCACHE_DIR
                log "🔥 Deleted the supercache directory at the ${BOLD}local${NC} server"
            fi
        ;;

        remote)
            SUPERCACHE_DIR="$REMOTE_WEB_ROOT/$WP_CONTENT_DIR/cache/supercache"

            if [[ $(checkRemoteFile $SUPERCACHE_DIR) == 1 ]]; then

                log "Would you like to 💥 ${BOLD}delete the cache directory${NORMAL} on the ${BOLD}$REMOTE_ENV${NORMAL} server:"
                log "$SUPERCACHE_DIR"
                read -r -p "[y/N] " PROMPT_RESPONSE

                # Return early if not confirmed
                [[ $(checkPromptResponse "$PROMPT_RESPONSE") != 1 ]] && return;

                ssh $REMOTE_SSH "[ -d $SUPERCACHE_DIR ] && rm -r $SUPERCACHE_DIR"
                log "🔥 Deleted the supercache directory at the ${BOLD}$REMOTE_ENV${NC} server"
            fi
        ;;

        *)
            logError "Usage: deleteSuperCacheDir <local|remote>"
        ;;

    esac


}