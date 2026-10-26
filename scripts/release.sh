#!/usr/bin/env bash

# Release a new version of wp-sync-deploy
#
# Usage: scripts/release.sh [patch|minor|major|rc|<version>] [--minimum] [--dry-run]
#
# - rc: release candidate for the next major version
# - major: if release candidates exist, promotes them to stable
# - --minimum: bump .minimum-version (stable releases only)
# - --dry-run: show what would happen

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR=$(dirname "$(dirname "$(realpath "$0")")")
cd "$ROOT_DIR"

source lib/functions.sh

TYPE=""
BUMP_MINIMUM=""
DRY_RUN=false
for arg in "$@"; do
    case $arg in
    --minimum) BUMP_MINIMUM=true ;;
    --dry-run) DRY_RUN=true ;;
    -*) logError "Unknown option: $arg" ;;
    *) TYPE="$arg" ;;
    esac
done

git fetch --tags --quiet

STABLE_TAG=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
IFS=. read -r MAJOR MINOR PATCH <<<"$STABLE_TAG"
NEXT_MAJOR="$((MAJOR + 1)).0.0"

# The latest release candidate for the next major version, if any
RC_TAG=$(git tag --list "$NEXT_MAJOR-rc.*" | sort -V | tail -1)
RC_NUMBER=${RC_TAG##*-rc.}
NEXT_RC="$NEXT_MAJOR-rc.$((${RC_NUMBER:-0} + 1))"

function versionFor() {
    case $1 in
    patch) echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor) echo "$MAJOR.$((MINOR + 1)).0" ;;
    major) echo "$NEXT_MAJOR" ;;
    rc) echo "$NEXT_RC" ;;
    *) echo "$1" ;;
    esac
}

# Ask for the release type if none was provided
if [[ -z "$TYPE" ]]; then
    log "Current version: ${BLUE}$STABLE_TAG${NC}${RC_TAG:+ (latest release candidate: ${BLUE}$RC_TAG${NC})}"
    for i in patch minor major rc; do
        log "  $i: ${GREEN}$(versionFor $i)${NC}"
    done
    read -r -p "Release type [patch|minor|major|rc]: " TYPE
fi

VERSION=$(versionFor "$TYPE")

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || logError "Invalid version: ${RED}$VERSION${NC}"
git rev-parse --quiet --verify "refs/tags/$VERSION" >/dev/null && logError "Tag ${RED}$VERSION${NC} already exists"

IS_RC=false
[[ "$VERSION" == *-rc.* ]] && IS_RC=true

BRANCH=$(git branch --show-current)
[[ "$BRANCH" != "main" ]] && logError "Releases must be created from ${BLUE}main${NC} (current: ${RED}$BRANCH${NC})"
[ -n "$(git status --porcelain)" ] && logError "Working tree is not clean"
[[ "$DRY_RUN" == false ]] && ! gh auth status >/dev/null 2>&1 && logError "Not logged in to ${BLUE}gh${NC}"

# Release candidates log changes since the previous release candidate, stable releases since the previous stable release
PREVIOUS_TAG="$STABLE_TAG"
[[ "$IS_RC" == true && -n "$RC_TAG" ]] && PREVIOUS_TAG="$RC_TAG"

if [[ "$IS_RC" == false && -z "$BUMP_MINIMUM" ]]; then
    read -r -p "Bump .minimum-version to $VERSION? [y/N] " PROMPT_RESPONSE
    [[ "$PROMPT_RESPONSE" == "y" ]] && BUMP_MINIMUM=true
fi
[[ "$IS_RC" == true && -n "$BUMP_MINIMUM" ]] && logError "--minimum is only supported for stable releases"

# Let the user edit the release notes
NOTES_FILE=$(mktemp)
trap 'rm -f "$NOTES_FILE"' EXIT
{
    echo "<!-- Release notes for $VERSION. Add a '### Breaking changes' section if needed. This line will be removed. -->"
    echo ""
    git log --no-merges --format='- %s' "$PREVIOUS_TAG..HEAD"
} >"$NOTES_FILE"
NOTES_EDITOR="${VISUAL:-${EDITOR:-$(git var GIT_EDITOR)}}"
# GUI editors like VS Code return immediately without --wait
[[ "$NOTES_EDITOR" =~ ^(code|cursor|subl|zed)$ ]] && NOTES_EDITOR="$NOTES_EDITOR --wait"
eval "$NOTES_EDITOR \"\$NOTES_FILE\""
NOTES=$(grep -v '^<!--' "$NOTES_FILE" | sed -e '/./,$!d')
[ -z "$NOTES" ] && logError "Release notes are empty, aborting"
printf '%s\n' "$NOTES" >"$NOTES_FILE"

logLine
log "🚀 Releasing ${GREEN}$VERSION${NC} from ${BLUE}$BRANCH${NC} (changes since ${BLUE}$PREVIOUS_TAG${NC})"
[[ "$IS_RC" == true ]] && log "   Pre-release, CHANGELOG.md stays untouched"
[[ "$BUMP_MINIMUM" == true ]] && log "   Bumping .minimum-version to $VERSION"
log "\n$NOTES\n"

if [[ "$DRY_RUN" == true ]]; then
    log "✅ ${GREEN}${BOLD}[ DRY-RUN ]${NORMAL}${NC} Nothing was released"
    exit 0
fi

read -r -p "Release? [y/n] " PROMPT_RESPONSE
[[ "$PROMPT_RESPONSE" != "y" ]] && exit 1

if [[ "$IS_RC" == false ]]; then
    {
        echo "# Changelog"
        echo ""
        echo "## $VERSION - $(date +%Y-%m-%d)"
        echo ""
        echo "$NOTES"
        tail -n +2 CHANGELOG.md
    } >CHANGELOG.md.tmp
    mv CHANGELOG.md.tmp CHANGELOG.md
    [[ "$BUMP_MINIMUM" == true ]] && echo "$VERSION" >.minimum-version
    git add CHANGELOG.md .minimum-version
    git commit --quiet -m "Release $VERSION"
fi

git tag "$VERSION"
git push --quiet --atomic origin main "$VERSION"

PRERELEASE_FLAG=""
[[ "$IS_RC" == true ]] && PRERELEASE_FLAG="--prerelease"
gh release create "$VERSION" --verify-tag --title "$VERSION" --notes-file "$NOTES_FILE" $PRERELEASE_FLAG

logSuccess "Released $VERSION"
