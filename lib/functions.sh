#!/usr/bin/env bash

# Font Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE="\033[0;36m"
NC='\033[0m' # No Color

# Font styles
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Log a string and redirect to stderr to prevent function return pollution
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

# Dump something and exit
function dd() {
	log "$1"
	exit 1
}

# Load the env file for wp-sync-deploy
# - first, look for .env.wp-sync-deploy file
# - second, fall back to the deprecated wp-sync-deploy.env file
function loadEnvFile() {
	# Find the closest wp-sync-deploy.env file
	ENV_FILE=$(findUp ".env.wp-sync-deploy" $SCRIPT_DIR)

	if [[ -z "$ENV_FILE" ]]; then
		ENV_FILE=$(findUp "wp-sync-deploy.env" $SCRIPT_DIR)
		[ -e "$ENV_FILE" ] && log "💡 Using ${RED}wp-sync-deploy.env${NC}. \n\r   Consider renaming the file to ${GREEN}.env.wp-sync-deploy${NC} instead\n\n\r"
	fi

	# Throw an error if no env file could be found
	[ -z "$ENV_FILE" ] && logError "No wp-sync-deploy.env file found. Please run ${BLUE}./wp-sync-deploy/setup.sh${NC} and adjust your env file afterwards"

	# Load the environment variables
	source $ENV_FILE
}

# Normalize a path:
#
# Feed the provided path into `realpath` to make sure the path is correct.
# (Prepends a leading slash to the provided path to prevent
# realpath from automatically making the path absolute)
#
function normalizePath() {
	realpath -sm "/$1"
}

# Normalize a URL
# - trim whitespace
# - trim trailing slashes
function normalizeUrl() {
	local URL=$(trimTrailingSlashes $(trimWhitespace "$1"))
	echo $URL
}

# Trim all leading slashes from a string
function relativePath() {
	[[ "$1" == "/" || "$1" == "" ]] && echo "." && return
	(
		shopt -s extglob
		echo "${1##*(/)}"
	)
}

# Trim all trailing slashes from a string
function trimTrailingSlashes() {
	[ "$1" == "/" ] && echo "$1" && return
	(
		shopt -s extglob
		echo "${@%%+(/)}"
	)
}

# Trim slashes from both ends of a string
function trimSlashes() {
	[ "$1" == "/" ] && echo "$1" && return
	echo $(relativePath $(trimTrailingSlashes "$1"))
}

# Trim whitespace from the beginning and end of a string
function trimWhitespace() {
	(
		shopt -s extglob
		# trim from the beginning
		local trimmed="${@##*( )}"
		# trim from the end and echo
		echo "${trimmed%%+( )}"
	)
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
function validateProductionBranch() {

	# Bail early if $GIT_DIR is not defined
	if [[ -z "${GIT_DIR+x}" ]]; then
		log "ℹ️  Skipping branch validation because ${BLUE}\$GIT_DIR${NC} is not defined"
		return
	fi

	# normalize the git directory
	ABSOLUTE_GIT_DIR=$(normalizePath "${LOCAL_ROOT_DIR}/${GIT_DIR}")

	# Get the branch from git directory
	cd "${ABSOLUTE_GIT_DIR}"
	local CURRENT_BRANCH=$(git branch --show)
	cd $LOCAL_WEB_ROOT

	# Validate the branch
	if [[ "${REMOTE_ENV}" == "production" && ! $CURRENT_BRANCH =~ $PRODUCTION_BRANCH ]]; then
		log "🚨 You are on the branch ${RED}${CURRENT_BRANCH}${NC}. Proceed deploy to ${BOLD}production${NORMAL}?"
		read -r -p "[y/n] " PROMPT_RESPONSE

		# Exit early if not confirmed
		if [[ "$PROMPT_RESPONSE" != "y" ]]; then
			log "❌ Deploy to $PRETTY_REMOTE_ENV canceled"
			exit
		fi
	else
		logSuccess "Branch ${BLUE}${CURRENT_BRANCH}${NC} allowed in ${BLUE}${REMOTE_ENV}${NC}"
	fi

}

# Check if there is a file `.allow-deployment` present at the remote root
function checkIsRemoteAllowed() {
	local FILE_PATH="$REMOTE_ROOT_DIR/.allow-deployment"

	IS_ALLOWED=$(ssh "$REMOTE_SSH" test -e "$FILE_PATH" && echo "yes" || echo "no")

	if [[ $IS_ALLOWED != "yes" ]]; then
		logError "Remote root ${RED}not allowed${NC} for deployment (missing file ${GREEN}.allow-deployment${NC})"
	else
		logSuccess "${BLUE}.allow-deployment${NC} detected on remote server"
	fi
}

# Check if the remote root is empty
function checkIsRemoteRootExistsAndIsEmpty() {
	# Check if the remote root directory exists
	EXISTS=$(ssh "$REMOTE_SSH" "[ -d \"$REMOTE_ROOT_DIR\" ] && echo \"yes\" || echo \"no\"")

	if [[ $EXISTS == "no" ]]; then
					logError "${RED}Remote root does not exist${NC}"
					return 1
	fi

	# Run the `find` command on the remote server to check for contents
	IS_EMPTY=$(ssh "$REMOTE_SSH" "find \"$REMOTE_ROOT_DIR\" -mindepth 1 -print -quit | grep -q . && echo \"no\" || echo \"yes\"")

	if [[ $IS_EMPTY == "yes" ]]; then
		logSuccess "${BLUE}Remote root is empty${NC}"
	else
		logError "Remote root ${RED}is not empty${NC} (contains files or directories)"
	fi
}

# Create the `.allow-deployment` file in the remote root directory
function createAllowDeploymentFileInRemoteRoot() {
	ssh "$REMOTE_SSH" "touch \"$REMOTE_ROOT_DIR/.allow-deployment\"" &&
		logSuccess "${BLUE}.allow-deployment${NC} file created in remote root" ||
		logError "Failed to create ${RED}.allow-deployment${NC} file in remote root"
}

# Check if the remote root directory contains only `.allow-deployment`
function checkIsRemoteRootPrepared() {
	IS_FRESH=$(ssh "$REMOTE_SSH" "
        shopt -s dotglob;
        FILES=(\"$REMOTE_ROOT_DIR\"/*);
        [[ \${#FILES[@]} -eq 1 && \"\${FILES[0]}\" == \"$REMOTE_ROOT_DIR/.allow-deployment\" ]] && echo \"yes\" || echo \"no\";
    ")

	if [[ $IS_FRESH == "yes" ]]; then
		logSuccess "${BLUE}Remote root is fresh${NC} (contains only .allow-deployment)"
	else
		logError "Remote root ${RED}is not fresh${NC} (it must contain one file ${BLUE}.allow-deployment${NC}, but nothing else)"
	fi
}

# Create a hash from a string
function createHash() {
	echo "$1" | sha256sum | head -c 10
}

# Check if a URL is available
function validateUrlIsAvailable() {
	local URL="$1"

	if ! curl -s -f "$URL" >/dev/null; then
		logError "The URL '$URL' is not available."
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

# Fetch something with CURL.
# - follow redirects (--location)
# - optional http authentication, e.g. "username:password" as second argument
function fetch() {
	local URL="$1"
	local AUTH="${2:-}"

	if [ -z "$AUTH" ]; then
		curl --silent --fail --location "$URL" || logError "couldn't fetch URL: ${RED}$URL${NC}"
	else
		curl --silent --fail --location --user "$AUTH" "$URL" || logError "couldn't fetch URL: ${RED}$URL${NC}"
	fi
}

# Check the web-facing PHP versions between two environments
function checkWebFacingPHPVersions() {
	# Append a hash to the test file to make it harder to detect on the remote server
	local HASH=$(createHash $REMOTE_WEB_ROOT)
	FILE_NAME="___wp-sync-deploy-php-version-$HASH.php"

	# Create the test file on the local server
	echo "<?= phpversion();" >"$LOCAL_WEB_ROOT/$FILE_NAME"
	# Get the output of the test file
	local LOCAL_OUTPUT=$(fetch "$LOCAL_URL/$FILE_NAME" "$LOCAL_HTTP_AUTH")
	# Cleanup the test file
	rm "$LOCAL_WEB_ROOT/$FILE_NAME"
	# substring from position 0-3
	local LOCAL_VERSION=${LOCAL_OUTPUT:0:3}
	# validate if the version looks legit
	[[ ! $LOCAL_VERSION =~ ^[0-9]\. ]] && logError "Invalid local web-facing PHP version number: $LOCAL_VERSION"
	# Log the detected PHP version
	log "- Web-facing PHP version at $PRETTY_LOCAL_HOST: ${BLUE}$LOCAL_VERSION${NC}"

	# Create the test file on the remote server
	ssh "$REMOTE_SSH" "cd $REMOTE_WEB_ROOT; echo '<?= phpversion();' > ./$FILE_NAME"

	# Get the output of the test file
	local REMOTE_OUTPUT=$(fetch "$REMOTE_URL/$FILE_NAME" "$REMOTE_HTTP_AUTH")

	# Cleanup the test file
	ssh "$REMOTE_SSH" "cd $REMOTE_WEB_ROOT; rm ./$FILE_NAME"
	# substring from position 0-3
	local REMOTE_VERSION=${REMOTE_OUTPUT:0:3}
	# validate if the version looks legit
	[[ ! $REMOTE_VERSION =~ ^[0-9]\. ]] && logError "Invalid remote web-facing PHP version number: $REMOTE_VERSION"
	# Log the detected PHP version
	log "- Web-facing PHP version at $PRETTY_REMOTE_HOST: ${BLUE}$REMOTE_VERSION${NC}"

	# Error out if the two PHP versions aren't a match
	if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
		logError "Web-Facing PHP versions mismatch. Aborting."
	else
		logSuccess "Web-facing PHP versions match between $PRETTY_LOCAL_ENV and $PRETTY_REMOTE_ENV"
	fi
}

# Check if a file exists on a remote server
function checkRemoteFile() {
	ssh -p $REMOTE_SSH_PORT $REMOTE_SSH "[ -e \"$1\" ] && echo 1 || echo 0"
}

# Validate that the required directories exist locally and remotely
function checkDeployPaths() {
	for DEPLOY_DIR in $DEPLOY_PATHS; do
		local LOCAL_PATH="${LOCAL_ROOT_DIR}/${DEPLOY_DIR}"
		local REMOTE_PATH="${REMOTE_ROOT_DIR}/${DEPLOY_DIR}"

		# check on local machine
		if [ ! -e "$LOCAL_PATH" ]; then
			logError "The directory ${RED}$LOCAL_PATH${NC} does not exist locally"
		fi
		# check on remote machine
		if [[ $(checkRemoteFile "$REMOTE_PATH") != 1 ]]; then
			logError "The directory ${RED}$REMOTE_PATH${RED} does not exist on the remote server"
		fi
		logSuccess "Folder exists at ${PRETTY_REMOTE_ENV}: ${BLUE}$DEPLOY_DIR${NC}"
	done
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
	local SSH_COMMAND="ssh -p $REMOTE_SSH_PORT $REMOTE_SSH 'cd $REMOTE_WEB_ROOT && $REMOTE_PHP_BINARY $WP_CLI_PHAR $ARGS'"

	# @see ChatGPT
	eval $SSH_COMMAND
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
	wp maintenance-mode activate

	# Import the remote database into the local database
	# Removes lines containing '999999' followed by 'enable the sandbox'
	# @see https://mariadb.org/mariadb-dump-file-compatibility-change/
	wpRemote db export --default-character-set=utf8mb4 - | sed '/999999.*enable the sandbox/d' | wp db import -

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

# Backup a remote database and store it locally
function backupDatabase() {
	local NAME="$REMOTE_HOST-$(date +"%Y-%m-%d_%H-%M-%S").sql"
	wpRemote db export --default-character-set=utf8mb4 - | sed '/999999.*enable the sandbox/d' >"$NAME"
	logLine && logSuccess "Database backup saved to ${GREEN}$NAME${NC}"
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
