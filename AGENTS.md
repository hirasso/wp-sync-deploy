This is [wp-sync-deploy](https://github.com/hirasso/wp-sync-deploy), a set of bash scripts to sync and deploy WordPress sites. Tested on OSX and Linux.

## Code style

- derive from the existing code
- keep comments as short as possible
- do not add comments if not really required
- only use languages I know. No python please

## Docs

- every user-facing change (config options, CLI flags, checks and prompts, upgrade steps) updates `README.md` **and** `skills/wp-sync-deploy/SKILL.md` in the same commit
- keep the skill lean: it describes the setup/upgrade procedure and points to `README.md` and `src/Config.php` for details. Don't duplicate option lists or defaults there
- `composer release` asks for confirmation if code changed since the last tag but README and skill didn't

## Before making changes

- if the change is big, always first propose what you are planning, even if not in plan mode

## Do not touch without explicit request

- `.env.wp-sync-deploy` files
- No commits without explicit request
- do not edit TODO files

# Branching

- every new claude session creates a new branch off main if there are code changes
- when the task is complete, merge back into main after confirmation
- always delete the merged branch afterwards, without asking

Currently I'm working only on the main branch locally, without PRs etc.

## Releasing

- releases are created by the user with `composer release [patch|minor|major|rc]` (`scripts/release.sh`). Never run it yourself (interactive, publishes a release)
- no type: interactive menu with the computed versions. Options need `--`: `composer release -- major --minimum`, `--dry-run` releases nothing
- `rc`: next release candidate of the next major version (e.g. `4.0.0-rc.4`). `major` promotes existing RCs to stable
- only from `main`, clean working tree, `main` not behind `origin/main`, version newer than the latest stable tag
- release notes are generated from commit subjects since the previous tag (stable: previous stable tag) and opened in `$VISUAL`/`$EDITOR`. So keep commit subjects readable
- stable: prepends the notes to `CHANGELOG.md` and commits `Release x.y.z`. RCs only get a GitHub pre-release
- then tags, pushes `main` and the tag atomically and creates the GitHub release
- for important releases (e.g. preventing data loss), bump `.minimum-version` to the new version (`--minimum`, or answer the prompt). Otherwise leave it, so upgrades stay optional
