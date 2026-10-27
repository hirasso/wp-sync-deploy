#!/usr/bin/env bash

# CONFIGURE wp-sync-deploy
#
# COMMANDS:
#
# Create wp-sync-deploy.config.php (asking for your setup) and wp-sync-deploy.tasks.php.
# Migrates a 3.x setup (.env.wp-sync-deploy, .deployignore, tasks file)
# `vendor/bin/wp-sync-deploy config init [-n|--no-interaction]`
#
# Validate the config locally and on the remote servers
# `vendor/bin/wp-sync-deploy config validate [--local]`
#

# The directory relative to the script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Source files
source "$SCRIPT_DIR/lib/functions.sh"

USAGE_MESSAGE="Usage: https://github.com/hirasso/wp-sync-deploy#configuration

vendor/bin/wp-sync-deploy config <init|validate> [args]"

# Ask for a value, prefilled with a default. `-` leaves it empty.
# Returns the default without asking in non-interactive mode
INTERACTIVE=true
function ask() {
	local LABEL="$1" DEFAULT="${2:-}" ANSWER=""
	[[ "$INTERACTIVE" == true ]] && read -r -p "   $LABEL${DEFAULT:+ [$DEFAULT]}: " ANSWER
	ANSWER="${ANSWER:-$DEFAULT}"
	[[ "$ANSWER" == "-" ]] && ANSWER=""
	echo "$ANSWER"
}

# Print a variable's value from the 3.x .env example, which the old `setup` command copied
function legacyExampleValue() {
	case "$1" in
	LOCAL_HOST) echo "example.test" ;;
	LOCAL_ROOT_DIR) echo "/absolute/path/to/local/root" ;;
	PUBLIC_DIR) echo "web" ;;
	WP_CONTENT_DIR) echo "web/app" ;;
	WP_CORE_DIR) echo "web/wp" ;;
	ADDITIONAL_DIRS) echo "vendor config" ;;
	GIT_DIR) echo "" ;;
	PROD_HOST) echo "example.com" ;;
	PROD_ROOT_DIR) echo "/absolute/path/to/production/root" ;;
	STAG_HOST) echo "staging.example.com" ;;
	STAG_ROOT_DIR) echo "/absolute/path/to/staging/root" ;;
	PROD_SSH | STAG_SSH) echo "username@example.com" ;;
	PROD_SSH_PORT | STAG_SSH_PORT) echo "22" ;;
	PROD_PHP_BINARY | STAG_PHP_BINARY) echo "php" ;;
	PROD_DEPLOY_STRATEGY) echo "conservative" ;;
	esac
}

# Ask unless a 3.x .env.wp-sync-deploy set the variable to a value of its own, then use the default without asking.
# Values left as in the example weren't chosen by the user
function askUnlessSetByUser() {
	local NAME="$1" LABEL="$2" DEFAULT="${3:-}"
	if [ -z "${!NAME+x}" ] || [[ "${!NAME}" == "$(legacyExampleValue "$NAME")" ]]; then
		ask "$LABEL" "$DEFAULT"
		return
	fi
	[[ "$INTERACTIVE" == true ]] && printf "   %s: ${BLUE}%s${NC}\n" "$LABEL" "$DEFAULT" >&2
	echo "$DEFAULT"
}

# Express a path relative to a base dir, `.` for the base dir itself
function relativeTo() {
	[[ "$1" == "$2" ]] && echo "." && return
	echo "${1#"$2"/}"
}

# Print a variable's value, or a default if it's empty
function valueOr() {
	local NAME="$1"
	echo "${!NAME:-$2}"
}

# Ask for a remote and export its variables with the given prefix (PROD_ or STAG_).
# Defaults come from a sourced .env.wp-sync-deploy, or the given placeholders
function askRemote() {
	local ENV="$1" PREFIX="$2" URL DEFAULT_URL="$3"
	local HOST="${PREFIX}HOST"
	[ -n "${!HOST:-}" ] && DEFAULT_URL="$(valueOr "${PREFIX}PROTOCOL" https)://${!HOST}"

	[[ "$INTERACTIVE" == true ]] && log "🌍 ${BOLD}$ENV${NORMAL}\n"
	URL=$(trimTrailingSlashes "$(askUnlessSetByUser "$HOST" "URL" "$DEFAULT_URL")")
	export "${PREFIX}PROTOCOL=${URL%%://*}" "${PREFIX}HOST=${URL#*://}"
	export "${PREFIX}SSH=$(askUnlessSetByUser "${PREFIX}SSH" "SSH (user@host)" "$(valueOr "${PREFIX}SSH" "$4")")"
	export "${PREFIX}SSH_PORT=$(askUnlessSetByUser "${PREFIX}SSH_PORT" "SSH port" "$(valueOr "${PREFIX}SSH_PORT" 22)")"
	export "${PREFIX}ROOT_DIR=$(askUnlessSetByUser "${PREFIX}ROOT_DIR" "Root dir (absolute)" "$(valueOr "${PREFIX}ROOT_DIR" "$5")")"
	export "${PREFIX}PHP_BINARY=$(askUnlessSetByUser "${PREFIX}PHP_BINARY" "PHP binary" "$(valueOr "${PREFIX}PHP_BINARY" php)")"
	export "${PREFIX}DEPLOY_STRATEGY=$(askUnlessSetByUser "${PREFIX}DEPLOY_STRATEGY" "Deploy strategy (conservative|risky)" "$(valueOr "${PREFIX}DEPLOY_STRATEGY" conservative)")"
}

# Write a config file from the detected local setup, a 3.x .env.wp-sync-deploy and the answers.
# Runs in a subshell to keep the exported variables
function writeConfig() (
	local FILE="$1" ENV_FILE="$2" DEPLOYIGNORE="$3"
	local WP_CONFIG INFO CORE CONTENT HOME_URL PUBLIC GIT_ROOT ROOT COMPOSER="-" GIT="" DIR NOTE

	# Before sourcing the .env file, as git reads its exported GIT_DIR
	GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || true

	if [ -n "$ENV_FILE" ]; then
		set -a
		source "$ENV_FILE"
		set +a
	fi

	log "🔍 Detecting your local WordPress setup ..."
	WP_CONFIG=$(wpLocal config path 2>/dev/null) || true
	INFO=$(wpLocal eval --skip-plugins --skip-themes 'echo rtrim(ABSPATH, "/"), PHP_EOL, WP_CONTENT_DIR, PHP_EOL, home_url(), PHP_EOL;' 2>/dev/null) || true
	{
		read -r CORE
		read -r CONTENT
		read -r HOME_URL
	} <<<"$INFO"

	# Without a local WordPress or a 3.x config, there is nothing to prefill
	if [[ -z "$HOME_URL" && -z "$ENV_FILE" && "$INTERACTIVE" != true ]]; then
		cp "$SCRIPT_DIR/wp-sync-deploy.config.example.php" "$FILE"
		log "ℹ️  No local WordPress found, created the config from the example"
		return
	fi

	# The public dir holds the index.php loading WordPress, usually next to wp-config.php
	PUBLIC=$(dirname "${WP_CONFIG:-$PWD/.}")
	[ -f "$PUBLIC/index.php" ] || PUBLIC="${CORE:-$PWD}"

	# The root dir is the git repo if it contains the public dir (e.g. Bedrock), else the public dir
	ROOT="$PUBLIC"
	[[ -n "$GIT_ROOT" && "$PUBLIC/" == "$GIT_ROOT/"* ]] && ROOT="$GIT_ROOT"
	ROOT="${LOCAL_ROOT_DIR:-$ROOT}"

	# Any composer.json: the vendor dir might hold the autoloader, and dev packages must never be deployed
	for DIR in "$ROOT" "$GIT_ROOT"; do
		[ -n "$DIR" ] && [ -f "$DIR/composer.json" ] && COMPOSER=$(relativeTo "$DIR" "$ROOT") && break
	done
	[[ " ${ADDITIONAL_DIRS:-} " == *" vendor "* ]] && COMPOSER="."

	[ -n "$GIT_ROOT" ] && [[ "$GIT_ROOT/" == "$ROOT/"* ]] && GIT=$(relativeTo "$GIT_ROOT" "$ROOT")
	[ -n "${GIT_DIR+x}" ] && GIT="${GIT_DIR:-.}"

	[[ "$INTERACTIVE" == true ]] && log "Press enter to accept the [default], ${BLUE}-${NC} leaves a value empty.\n\n📁 ${BOLD}local${NORMAL}\n"

	# WordPress knows the local URL best, e.g. if the protocol changed
	[ -z "$HOME_URL" ] && [ -n "${LOCAL_HOST:-}" ] && HOME_URL="$(valueOr LOCAL_PROTOCOL https)://$LOCAL_HOST"
	local URL=$(trimTrailingSlashes "$(askUnlessSetByUser LOCAL_HOST "URL" "$HOME_URL")")
	export LOCAL_PROTOCOL="${URL%%://*}" LOCAL_HOST="${URL#*://}"
	export LOCAL_ROOT_DIR=$(askUnlessSetByUser LOCAL_ROOT_DIR "Root dir (absolute)" "$ROOT")
	export WP_CORE_DIR=$(askUnlessSetByUser WP_CORE_DIR "WordPress core dir, relative to the root dir" "${WP_CORE_DIR:-$(relativeTo "$CORE" "$LOCAL_ROOT_DIR")}")
	export WP_CONTENT_DIR=$(askUnlessSetByUser WP_CONTENT_DIR "Content dir, relative to the root dir" "${WP_CONTENT_DIR:-$(relativeTo "$CONTENT" "$LOCAL_ROOT_DIR")}")
	[ -n "${PUBLIC_DIR+x}" ] && PUBLIC="${PUBLIC_DIR:-.}" || PUBLIC=$(relativeTo "$PUBLIC" "$LOCAL_ROOT_DIR")
	PUBLIC=$(askUnlessSetByUser PUBLIC_DIR "Public dir, relative to the root dir" "$PUBLIC")
	export PUBLIC_DIR="${PUBLIC#.}"
	export ADDITIONAL_DIRS=$(askUnlessSetByUser ADDITIONAL_DIRS "Additional dirs to deploy, space separated" "$(echo " ${ADDITIONAL_DIRS:-} " | sed 's/ vendor / /' | xargs)")

	[ -n "$GIT" ] && GIT=$(askUnlessSetByUser GIT_DIR "Git repo, relative to the root dir" "$GIT")
	unset GIT_DIR COMPOSER_DIR
	[ -n "$GIT" ] && export GIT_DIR="${GIT#.}"
	COMPOSER=$(ask "Composer dir to deploy vendor from, without dev dependencies" "$COMPOSER")
	[ -n "$COMPOSER" ] && export COMPOSER_DIR="${COMPOSER#.}"

	askRemote production PROD_ https://example.com username@example.com /absolute/path/to/production/root
	if [[ $(askUnlessSetByUser STAG_HOST "Add a staging environment? (y/n)" "$([[ -n "${STAG_HOST:-}" && "$STAG_HOST" != "$(legacyExampleValue STAG_HOST)" ]] && echo y || echo n)") == "y" ]]; then
		askRemote staging STAG_
	else
		unset STAG_HOST
	fi

	php "$SCRIPT_DIR/lib/migrate.php" config "$FILE" "$DEPLOYIGNORE" >"$FILE.tmp" 2>"$FILE.notes" && mv "$FILE.tmp" "$FILE"
	while IFS= read -r NOTE; do
		log "ℹ️  $NOTE"
	done <"$FILE.notes"
	rm -f "$FILE.tmp" "$FILE.notes"
	[ -e "$FILE" ]
)

# Remove a migrated 3.x file: `git rm` if tracked (recoverable), otherwise keep a backup
function removeLegacyFile() {
	local FILE="$1"
	if git -C "$(dirname "$FILE")" rm -q "$FILE" 2>/dev/null; then
		log "🗑️  Removed ${BLUE}$(prettyPath "$FILE")${NC} (git rm)"
	else
		mv "$FILE" "$FILE.bak"
		log "🗑️  Renamed ${BLUE}$(prettyPath "$FILE")${NC} to ${BLUE}$(prettyPath "$FILE").bak${NC}, delete it after reviewing the config"
	fi
}

# Create the config and tasks files, migrating a 3.x setup if found.
# The config goes next to an existing .env.wp-sync-deploy, else into the current directory
function initConfig() {
	local ENV_FILE DIR CONFIG_FILE DEPLOYIGNORE TASKS_FILE COUNT FILE TODOS="" arg
	for arg in "$@"; do
		case $arg in
		-n | --no-interaction) INTERACTIVE=false ;;
		*) logError "$USAGE_MESSAGE" ;;
		esac
	done
	[ -t 0 ] || INTERACTIVE=false

	ENV_FILE=$(findUp ".env.wp-sync-deploy" $SCRIPT_DIR)
	[ -z "$ENV_FILE" ] && ENV_FILE=$(findUp "wp-sync-deploy.env" $SCRIPT_DIR)
	DIR=$(dirname "${ENV_FILE:-$PWD/.}")
	CONFIG_FILE="$DIR/wp-sync-deploy.config.php"
	DEPLOYIGNORE="$DIR/.deployignore"
	[ -e "$PWD/.deployignore" ] && DEPLOYIGNORE="$PWD/.deployignore"

	if [[ "$INTERACTIVE" == true ]]; then
		log "🚀 Setup ${BLUE}wp-sync-deploy${NC} at this location?"
		log "  ${GREEN}$DIR${NC}"
		[ -n "$ENV_FILE" ] && log "  Migrates ${BLUE}$(prettyPath "$ENV_FILE")${NC}, asks only for values you didn't set yourself"
		read -r -p " [y/n] " PROMPT_RESPONSE
		[[ "$PROMPT_RESPONSE" != "y" ]] && exit 1
	fi

	if [ -e "$CONFIG_FILE" ]; then
		logSuccess "File ${GREEN}$(prettyPath "$CONFIG_FILE")${NC} already exists"
		[ -n "$ENV_FILE" ] && TODOS="$TODOS\n\r   - Compare ${BLUE}$(prettyPath "$ENV_FILE")${NC} with your config, then delete it"
		[ -e "$DEPLOYIGNORE" ] && TODOS="$TODOS\n\r   - Move the rules from ${BLUE}$(prettyPath "$DEPLOYIGNORE")${NC} to ${BLUE}ignore: new Ignore(patterns: [...])${NC}, then delete it"
	else
		writeConfig "$CONFIG_FILE" "$ENV_FILE" "$DEPLOYIGNORE" || logError "Failed to create ${RED}$(prettyPath "$CONFIG_FILE")${NC}"
		logSuccess "File ${GREEN}$(prettyPath "$CONFIG_FILE")${NC} created"
		[ -n "$ENV_FILE" ] && removeLegacyFile "$ENV_FILE"
		if [ -e "$DEPLOYIGNORE" ]; then
			logSuccess "Moved custom rules from ${BLUE}$(prettyPath "$DEPLOYIGNORE")${NC} to ${BLUE}ignore: new Ignore()${NC}"
			removeLegacyFile "$DEPLOYIGNORE"
		fi
	fi

	TASKS_FILE=$(findUp "wp-sync-deploy.tasks.php" $SCRIPT_DIR)
	if [ -z "$TASKS_FILE" ]; then
		cp "$SCRIPT_DIR/wp-sync-deploy.tasks.example.php" "$DIR/wp-sync-deploy.tasks.php"
		logSuccess "File ${GREEN}$(prettyPath "$DIR/wp-sync-deploy.tasks.php")${NC} created"
	else
		logSuccess "File ${GREEN}$(prettyPath "$TASKS_FILE")${NC} already exists"
		COUNT=$(php "$SCRIPT_DIR/lib/migrate.php" tasks "$TASKS_FILE")
		[ -n "$COUNT" ] && logSuccess "Using the ${BLUE}run()${NC} helper for $COUNT WP-CLI command(s) in ${BLUE}$(prettyPath "$TASKS_FILE")${NC}"
	fi

	# The `run` argument was removed in 4.0.0
	local FILES=("$DIR/composer.json" "$DIR/package.json")
	[[ "$PWD" != "$DIR" ]] && FILES+=("$PWD/composer.json" "$PWD/package.json")
	for FILE in "${FILES[@]}"; do
		[ -f "$FILE" ] && grep -qE 'wp-sync-deploy deploy[^"]* run\b' "$FILE" &&
			TODOS="$TODOS\n\r   - Remove the ${BLUE}run${NC} argument in ${BLUE}$(prettyPath "$FILE")${NC}, deploys are live by default. Preview with ${BLUE}--dry-run${NC}"
	done

	[ -n "$TODOS" ] && log "📋 ${BOLD}Still to do:${NORMAL}$TODOS"

	if [[ "$INTERACTIVE" != true ]]; then
		log "🚀 Review ${BLUE}$(prettyPath "$CONFIG_FILE")${NC}, then run ${BLUE}vendor/bin/wp-sync-deploy config validate${NC}"
		return
	fi

	# The legacy file check would fail the validation
	[ -e "${ENV_FILE:-}" ] && return

	logLine
	validateConfig "--config=$CONFIG_FILE"
}

# Shorten a path relative to the current directory
function prettyPath() {
	echo "${1#"$PWD"/}"
}

# Log a passed or failed check. Usage: check <label> <command...>
VALIDATION_ERRORS=0
function check() {
	local LABEL="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		logSuccess "$LABEL"
	else
		log "🚨 ${RED}$LABEL${NC}"
		VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
	fi
}

# Compare a configured URL with the home URL of a WordPress install
function checkHomeUrl() {
	local CONFIGURED=$(normalizeUrl "$1")
	local ACTUAL=$(normalizeUrl "$2")
	if [[ "$CONFIGURED" == "$ACTUAL" ]]; then
		logSuccess "URL matches the home URL in WordPress: ${BLUE}$ACTUAL${NC}"
	else
		log "🚨 ${RED}URL ${CONFIGURED} doesn't match the home URL in WordPress: ${ACTUAL:-(unknown)}${NC}"
		VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
	fi
}

# Print the resolved config in a readable way
function logConfigSummary() {
	log "📄 ${BOLD}$(prettyPath "$CONFIG_FILE")${NORMAL}"
	log "   local:      ${BLUE}$LOCAL_PROTOCOL://$LOCAL_HOST${NC} at $LOCAL_ROOT_DIR"
	log "   paths:      core ${BLUE}$WP_CORE_DIR${NC}, content ${BLUE}$WP_CONTENT_DIR${NC}${PUBLIC_DIR:+, public ${BLUE}$PUBLIC_DIR${NC}}${ADDITIONAL_DIRS:+, additional ${BLUE}$ADDITIONAL_DIRS${NC}}"
	[ -n "${GIT_DIR+x}" ] && log "   git:        ${BLUE}${GIT_DIR:-.}${NC}, production branch ${BLUE}$PRODUCTION_BRANCH${NC}"
	[ -n "${COMPOSER_DIR+x}" ] && log "   composer:   ${BLUE}${COMPOSER_DIR:-.}${NC}, vendor deployed without dev dependencies"

	local ENV PREFIX
	for ENV in production staging; do
		PREFIX="PROD_"
		[[ "$ENV" == "staging" ]] && PREFIX="STAG_"
		local HOST_VAR="${PREFIX}HOST"
		[ -z "${!HOST_VAR+x}" ] && continue
		local PROTOCOL="${PREFIX}PROTOCOL" SSH="${PREFIX}SSH" PORT="${PREFIX}SSH_PORT" ROOT="${PREFIX}ROOT_DIR" PHP="${PREFIX}PHP_BINARY" STRATEGY="${PREFIX}DEPLOY_STRATEGY"
		log "   $(printf '%-11s' "$ENV:") ${BLUE}${!PROTOCOL}://${!HOST_VAR}${NC} at ${!SSH}:${!PORT}${!ROOT} (php: ${!PHP}, ${!STRATEGY})"
	done

	local CUSTOM_RULES=$(printf '%s\n' "$IGNORE_RULES" | grep -v '^-p ' | sed 's/^/               /')
	[ -n "$CUSTOM_RULES" ] && log "   ignore:\n\r$CUSTOM_RULES"
	return 0
}

# Validate the local environment
function validateLocal() {
	log "🔍 ${BOLD}local${NORMAL}"
	check "Root dir ${BLUE}$LOCAL_ROOT_DIR${NC}" test -d "$LOCAL_ROOT_DIR"
	check "WordPress core ${BLUE}$WP_CORE_DIR${NC}" test -f "$LOCAL_ROOT_DIR/$WP_CORE_DIR/wp-includes/version.php"
	check "Content dir ${BLUE}$WP_CONTENT_DIR${NC}" test -d "$LOCAL_ROOT_DIR/$WP_CONTENT_DIR/plugins" -a -d "$LOCAL_ROOT_DIR/$WP_CONTENT_DIR/themes"

	local DIR
	for DIR in ${ADDITIONAL_DIRS:-}; do
		check "Additional path ${BLUE}$DIR${NC}" test -e "$LOCAL_ROOT_DIR/$DIR"
	done

	[ -n "${GIT_DIR+x}" ] && check "Git repo ${BLUE}${GIT_DIR:-.}${NC}" git -C "$LOCAL_ROOT_DIR/$GIT_DIR" rev-parse
	[ -n "${COMPOSER_DIR+x}" ] && check "Composer ${BLUE}${COMPOSER_DIR:-.}/composer.json${NC}" test -f "$LOCAL_ROOT_DIR/$COMPOSER_DIR/composer.json"

	check "GNU rsync" bash -c "source '$SCRIPT_DIR/lib/functions.sh'; requireGnuRsync \"\$(resolveRsyncBin)\""
	checkHomeUrl "$LOCAL_PROTOCOL://$LOCAL_HOST" "$(cd "$LOCAL_ROOT_DIR/$PUBLIC_DIR" && wpLocal option get home 2>/dev/null)"

	local TASKS_FILE=$(findUp "wp-sync-deploy.tasks.php" $SCRIPT_DIR)
	if [ -n "$TASKS_FILE" ]; then
		logSuccess "Tasks file ${BLUE}$(prettyPath "$TASKS_FILE")${NC}"
	else
		log "ℹ️  No tasks file found, no tasks will run after a sync or deploy"
	fi
}

# Validate a remote environment. Runs in a subshell after lib/bootstrap.sh
function validateRemote() {
	VALIDATION_ERRORS=0
	log "🔍 ${BOLD}$REMOTE_ENV${NORMAL}"

	$SSH_CONNECTION true </dev/null || logError "SSH connection to ${RED}$REMOTE_SSH${NC} (port $REMOTE_SSH_PORT) failed"
	logSuccess "SSH connection ${BLUE}$REMOTE_SSH${NC}"

	checkRemoteRootExists

	if [[ "$DEPLOY_STRATEGY" == "conservative" ]]; then
		checkIsDeploymentAllowed
	elif [[ $(checkRemoteFile "$REMOTE_ROOT_DIR/.allow-deployment") != 1 ]]; then
		log "ℹ️  No ${BLUE}.allow-deployment${NC} file, only required for deploy strategy ${BLUE}conservative${NC}"
	fi

	DEPLOY_MODE="dry"
	checkCommandLinePHPVersions

	installRemoteWpCli
	checkHomeUrl "$REMOTE_URL" "$(wpRemote option get home 2>/dev/null)"

	return $VALIDATION_ERRORS
}

# Validate the config, locally and on the remote servers
function validateConfig() {
	local LOCAL_ONLY=false CONFIG_ARGS=() arg
	for arg in "$@"; do
		case $arg in
		--local) LOCAL_ONLY=true ;;
		--config=*) CONFIG_ARGS+=("$arg") WP_SYNC_DEPLOY_CONFIG_FILE="${arg#*=}" ;;
		*) logError "$USAGE_MESSAGE" ;;
		esac
	done

	loadConfigFile
	logConfigSummary
	logLine
	validateLocal

	if [[ "$LOCAL_ONLY" != true ]]; then
		local ENV
		for ENV in production staging; do
			[[ "$ENV" == "staging" && -z "${STAG_HOST+x}" ]] && continue
			logLine
			(
				set -- "$ENV" "${CONFIG_ARGS[@]}"
				source "$SCRIPT_DIR/lib/bootstrap.sh"
				validateRemote
			) || VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
		done
	fi

	logLine
	[[ "$VALIDATION_ERRORS" != "0" ]] && logError "The config has ${RED}$VALIDATION_ERRORS${NC} problem(s)"
	logSuccess "The config is valid"
}

SUBCOMMAND="${1:-}"
[ $# -gt 0 ] && shift

case $SUBCOMMAND in
init) initConfig "$@" ;;
validate) validateConfig "$@" ;;
*) logError "$USAGE_MESSAGE" ;;
esac

logLine
