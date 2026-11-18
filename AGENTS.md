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

- `README.md` is for end users only. Implementation details go here

## Internals

- WP-CLI is cached locally at `~/.cache/wp-sync-deploy/wp-cli.phar` (re-downloaded when older than a week) and uploaded to `~/.wp-sync-deploy/` on the remote, outside of the web root, once per run
- `wpLocal` and `wpRemote` load `lib/wp-cli-setup.php` with `--require`: it hides PHP deprecation notices and swaps the WP-CLI logger, so WP-CLI logs like `logSuccess`/`logWarning`/`logError`
- the tasks file is uploaded to `~/.wp-sync-deploy/` for each run and deleted afterwards
- `new Composer()` builds `vendor` in a temp dir (`composer install --no-dev --optimize-autoloader`) and deploys that one
- `log` prints its newline *before* the message, WP-CLI *after*. Add a `logLine` where WP-CLI output directly follows a `log`

## Project structure

| Path | Purpose |
|------|---------|
| `bin/wp-sync-deploy` | Entry point, dispatches to the root scripts |
| `deploy.sh`, `sync.sh`, `upload.sh`, `config.sh` | Commands |
| `lib/bootstrap.sh` | Shared setup, loads config |
| `lib/functions.sh` | Shared functions |
| `lib/config.php` | Prints `wp-sync-deploy.config.php` as shell variables |
| `lib/migrate.php` | `config init\|migrate` |
| `lib/wp-cli-setup.php` | WP-CLI `--require` (logger, notices) |
| `src/Config.php` | Config options and defaults |
| `wp-sync-deploy.*.example.php` | Example config and tasks files |
| `scripts/release.sh` | `composer release` |
| `skills/wp-sync-deploy/` | Agent skill for setup/upgrade |
| `tests/e2e/` | End-to-end tests (Docker + bats) |
| `.github/workflows/e2e.yml` | Runs the e2e tests on every push |
| `tmp/` | Throwaway scripts (gitignored) |

## Tests

- `composer test` (`tests/e2e/run.sh [bats args]`) runs the bats tests in one Docker container that plays `local.test`, `staging.test` and `prod.test`, with SSH from user `dev` to `deploy` on localhost. Fixture project: `tests/e2e/fixture/`, setup: `tests/e2e/helpers.bash`
- the package is copied into the fixture's `packages/` per test file (config and tasks files are found by walking up from the package dir). Not `vendor/`: the composer tests manage it, and `checkMinimumSelfVersion` exits silently if `vendor/composer/installed.json` lacks the package
- in nono (no Docker, no SSH): push the branch and read the result with `gh run watch <id>` / `gh run view <id> --log-failed`. Take the run id for the pushed commit (`gh run list --commit <sha>`), not the latest run
- add tests for every user-facing behavior change. Before relying on a new test, prove it fails without the fix (throwaway branch, deleted afterwards)

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

## After making changes

- issues solved by the change: add `Fixes #<n>` to the commit message; never close them directly

## Issue tracker

Issues and PRDs live as GitHub issues; use `gh` (`gh issue list`, `gh issue view`, `gh issue create`). They close via `Fixes #<n>` in the commit message when pushed to `main`; never `gh issue close`.

Triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. `wontfix` issues are closed only on request.

## Releasing

- releases are created by the user with `composer release [patch|minor|major|rc]` (`scripts/release.sh`). Never run it yourself (interactive, publishes a release)
- no type: interactive menu with the computed versions. Options need `--`: `composer release -- major --minimum`, `--dry-run` releases nothing
- `rc`: next release candidate of the next major version (e.g. `4.0.0-rc.4`). `major` promotes existing RCs to stable
- only from `main`, clean working tree, `main` not behind `origin/main`, version newer than the latest stable tag
- release notes are generated from commit subjects since the previous tag (stable: previous stable tag) and opened in `$VISUAL`/`$EDITOR`. So keep commit subjects readable
- stable: prepends the notes to `CHANGELOG.md` and commits `Release x.y.z`. RCs only get a GitHub pre-release
- then tags, pushes `main` and the tag atomically and creates the GitHub release
- for important releases (e.g. preventing data loss), bump `.minimum-version` to the new version (`--minimum`, or answer the prompt). Otherwise leave it, so upgrades stay optional
