#!/usr/bin/env bash
# SessionStart hook: if the cwd uses an outdated major version of wp-sync-deploy,
# tell Claude to offer an upgrade with the wp-sync-deploy skill. Prints nothing otherwise.
#
# Usage: detect.sh          check the cwd
#        detect.sh snooze   stay quiet for this project for 30 days

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wp-sync-deploy"
SNOOZE_FILE="$CACHE_DIR/snoozed/$(printf '%s' "$PWD" | shasum | cut -c1-16)"

if [[ "${1:-}" == "snooze" ]]; then
    mkdir -p "$(dirname "$SNOOZE_FILE")" && touch "$SNOOZE_FILE"
    exit 0
fi

[ -n "$(find "$SNOOZE_FILE" -mtime -30 2>/dev/null)" ] && exit 0

# Installed version: composer since 3.x, a cloned folder or legacy config before
INSTALLED=""
if [ -f composer.lock ]; then
    INSTALLED=$(jq -r '[.packages[]?, .["packages-dev"][]?] | map(select(.name == "hirasso/wp-sync-deploy")) | .[0].version // empty' composer.lock 2>/dev/null)
fi
if [[ -z "$INSTALLED" ]] && [[ -f wp-sync-deploy/deploy.sh || -f .env.wp-sync-deploy || -f wp-sync-deploy.env ]]; then
    INSTALLED="2.x"
fi
[[ -z "$INSTALLED" ]] && exit 0

INSTALLED_MAJOR="${INSTALLED#v}"
INSTALLED_MAJOR="${INSTALLED_MAJOR%%.*}"
[[ "$INSTALLED_MAJOR" =~ ^[0-9]+$ ]] || exit 0

# Latest stable major from packagist, cached for a day
LATEST_FILE="$CACHE_DIR/latest-major"
if [ -z "$(find "$LATEST_FILE" -mtime -1 2>/dev/null)" ]; then
    LATEST=$(curl -fsSL --max-time 2 "https://repo.packagist.org/p2/hirasso/wp-sync-deploy.json" 2>/dev/null |
        jq -r '.packages["hirasso/wp-sync-deploy"][].version' 2>/dev/null |
        grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | cut -d. -f1 | sort -n | tail -1)
    [[ "$LATEST" =~ ^[0-9]+$ ]] || exit 0
    mkdir -p "$CACHE_DIR" && echo "$LATEST" >"$LATEST_FILE"
fi
LATEST_MAJOR=$(cat "$LATEST_FILE" 2>/dev/null)
[[ "$LATEST_MAJOR" =~ ^[0-9]+$ ]] || exit 0

((INSTALLED_MAJOR < LATEST_MAJOR)) || exit 0

context="This project uses wp-sync-deploy $INSTALLED, but $LATEST_MAJOR.x is available.

Before anything else, ask the user whether to upgrade now with the wp-sync-deploy skill. If they decline, run \`bash $0 snooze\` (quiet for this project for 30 days)."

jq -n --arg ctx "$context" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
