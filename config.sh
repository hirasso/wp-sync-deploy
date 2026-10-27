#!/usr/bin/env bash

# CONFIGURE wp-sync-deploy
#
# COMMANDS:
#
# Create wp-sync-deploy.config.php and wp-sync-deploy.tasks.php in the current directory
# `vendor/bin/wp-sync-deploy config init`
#
# Validate the config locally and on the remote servers
# `vendor/bin/wp-sync-deploy config validate [production|staging] [--local]`
#
# Migrate a 3.x setup (.env.wp-sync-deploy, .deployignore, tasks file)
# `vendor/bin/wp-sync-deploy config migrate`
#

# The directory relative to the script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Source files
source "$SCRIPT_DIR/lib/functions.sh"

USAGE_MESSAGE="Usage: https://github.com/hirasso/wp-sync-deploy#configuration

vendor/bin/wp-sync-deploy config <init|validate|migrate> [args]"

# Create the config and tasks files in the current directory
function initConfig() {
	local CONFIG_FILE="wp-sync-deploy.config.php"
	local TASKS_FILE="wp-sync-deploy.tasks.php"

	log "🚀 Setup ${BLUE}wp-sync-deploy${NC} at this location?"
	log "  ${GREEN}$(pwd)${NC}"

	read -r -p " [y/n] " PROMPT_RESPONSE
	[[ "$PROMPT_RESPONSE" != "y" ]] && exit 1

	log "🚀 Installing ${GREEN}wp-sync-deploy${NC} ... \n"

	if [ ! -e $CONFIG_FILE ]; then
		cp "$SCRIPT_DIR/wp-sync-deploy.config.example.php" $CONFIG_FILE
		logSuccess "File ${GREEN}$CONFIG_FILE${NC} created! "
	else
		logSuccess "File ${GREEN}$CONFIG_FILE${NC} already exists. "
	fi

	if [ ! -e $TASKS_FILE ]; then
		cp "$SCRIPT_DIR/wp-sync-deploy.tasks.example.php" $TASKS_FILE
		logSuccess "File ${GREEN}$TASKS_FILE${NC} created!"
	else
		logSuccess "File ${GREEN}$TASKS_FILE${NC} already exists. "
	fi

	log "\n🚀 Setup complete! Adjust both files to your setup, then run ${BLUE}vendor/bin/wp-sync-deploy config validate${NC}"
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
		log "✅ $LABEL"
	else
		log "❌ ${RED}$LABEL${NC}"
		VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
	fi
}

# Compare a configured URL with the home URL of a WordPress install
function checkHomeUrl() {
	local CONFIGURED=$(normalizeUrl "$1")
	local ACTUAL=$(normalizeUrl "$2")
	if [[ "$CONFIGURED" == "$ACTUAL" ]]; then
		log "✅ URL matches the home URL in WordPress: ${BLUE}$ACTUAL${NC}"
	else
		log "❌ ${RED}URL ${CONFIGURED} doesn't match the home URL in WordPress: ${ACTUAL:-(unknown)}${NC}"
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
		log "✅ Tasks file ${BLUE}$(prettyPath "$TASKS_FILE")${NC}"
	else
		log "ℹ️  No tasks file found, no tasks will run after a sync or deploy"
	fi
}

# Validate a remote environment. Runs in a subshell after lib/bootstrap.sh
function validateRemote() {
	VALIDATION_ERRORS=0
	log "🔍 ${BOLD}$REMOTE_ENV${NORMAL}"

	$SSH_CONNECTION true </dev/null || logError "SSH connection to ${RED}$REMOTE_SSH${NC} (port $REMOTE_SSH_PORT) failed"
	log "✅ SSH connection ${BLUE}$REMOTE_SSH${NC}"

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
	local ONLY_ENV="" LOCAL_ONLY=false CONFIG_ARGS=() arg
	for arg in "$@"; do
		case $arg in
		--local) LOCAL_ONLY=true ;;
		--config=*) CONFIG_ARGS+=("$arg") WP_SYNC_DEPLOY_CONFIG_FILE="${arg#*=}" ;;
		production | staging) ONLY_ENV="$arg" ;;
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
			[[ -n "$ONLY_ENV" && "$ENV" != "$ONLY_ENV" ]] && continue
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

# Migrate a 3.x setup, then validate the result
function migrateConfig() {
	local MIGRATED=false TODOS="" ENV_FILE CONFIG DIR COUNT FILE

	ENV_FILE=$(findUp ".env.wp-sync-deploy" $SCRIPT_DIR)
	[ -z "$ENV_FILE" ] && ENV_FILE=$(findUp "wp-sync-deploy.env" $SCRIPT_DIR)
	DIR=$(dirname "${ENV_FILE:-$PWD/.}")
	CONFIG="$DIR/wp-sync-deploy.config.php"
	local DEPLOYIGNORE="$DIR/.deployignore"
	[ -e "$PWD/.deployignore" ] && DEPLOYIGNORE="$PWD/.deployignore"

	if [ -n "$ENV_FILE" ] && [ -e "$CONFIG" ]; then
		log "ℹ️  ${BLUE}$(prettyPath "$CONFIG")${NC} already exists, skipping ${BLUE}$(prettyPath "$ENV_FILE")${NC}"
		TODOS="$TODOS\n\r   - Compare ${BLUE}$(prettyPath "$ENV_FILE")${NC} with your config, then delete it"
	elif [ -n "$ENV_FILE" ]; then
		(
			set -a
			source "$ENV_FILE"
			set +a
			php "$SCRIPT_DIR/lib/migrate.php" config "$CONFIG" "$DEPLOYIGNORE" 2>"$CONFIG.notes"
		) >"$CONFIG.tmp" || {
			rm -f "$CONFIG.tmp" "$CONFIG.notes"
			logError "Failed to migrate ${RED}$ENV_FILE${NC}"
		}
		mv "$CONFIG.tmp" "$CONFIG"
		logSuccess "Created ${GREEN}$(prettyPath "$CONFIG")${NC} from ${BLUE}$(prettyPath "$ENV_FILE")${NC}"
		while IFS= read -r FILE; do
			TODOS="$TODOS\n\r   - $FILE"
		done <"$CONFIG.notes"
		rm -f "$CONFIG.notes"
		removeLegacyFile "$ENV_FILE"
		MIGRATED=true
	fi

	if [ -e "$DEPLOYIGNORE" ] && [[ "$MIGRATED" == true ]]; then
		log "✅ Moved custom rules from ${BLUE}$(prettyPath "$DEPLOYIGNORE")${NC} to ${BLUE}ignore: new Ignore()${NC}"
		removeLegacyFile "$DEPLOYIGNORE"
	elif [ -e "$DEPLOYIGNORE" ]; then
		TODOS="$TODOS\n\r   - Move the rules from ${BLUE}$(prettyPath "$DEPLOYIGNORE")${NC} to ${BLUE}ignore: new Ignore(patterns: [...])${NC}, then delete it"
		MIGRATED=true
	fi

	FILE=$(findUp "wp-sync-deploy.tasks.php" $SCRIPT_DIR)
	if [ -n "$FILE" ]; then
		COUNT=$(php "$SCRIPT_DIR/lib/migrate.php" tasks "$FILE")
		if [ -n "$COUNT" ]; then
			log "✅ Using the ${BLUE}run()${NC} helper for $COUNT WP-CLI command(s) in ${BLUE}$(prettyPath "$FILE")${NC}"
			MIGRATED=true
		fi
	fi

	# The `run` argument was removed in 4.0.0
	local FILES=("$DIR/composer.json" "$DIR/package.json")
	[[ "$PWD" != "$DIR" ]] && FILES+=("$PWD/composer.json" "$PWD/package.json")
	for FILE in "${FILES[@]}"; do
		[ -f "$FILE" ] || continue
		if grep -qE 'wp-sync-deploy deploy[^"]* run\b' "$FILE"; then
			TODOS="$TODOS\n\r   - Remove the ${BLUE}run${NC} argument in ${BLUE}$(prettyPath "$FILE")${NC}, deploys are live by default. Preview with ${BLUE}--dry-run${NC}"
			MIGRATED=true
		fi
	done

	if [[ "$MIGRATED" != true ]]; then
		logSuccess "Nothing to migrate"
		return
	fi

	[ -n "$TODOS" ] && log "📋 ${BOLD}Still to do:${NORMAL}$TODOS"
	[ ! -e "$CONFIG" ] && return

	logLine
	validateConfig "--config=$CONFIG"
}

SUBCOMMAND="${1:-}"
[ $# -gt 0 ] && shift

case $SUBCOMMAND in
init) initConfig ;;
validate) validateConfig "$@" ;;
migrate) migrateConfig ;;
*) logError "$USAGE_MESSAGE" ;;
esac
