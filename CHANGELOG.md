# Changelog

## 4.3.0 - 2026-10-27

- Enable `.git` checks by default, warn about missing `composer:`

## 4.2.1 - 2026-10-27

- Only check the project's own vendor dirs for dev packages

## 4.2.0 - 2026-10-27

- Add `config init`, a setup wizard that detects your local WordPress setup and migrates 3.x setups
(`.env.wp-sync-deploy`, `.deployignore`, tasks file). It only asks for values you didn't set yourself
- Add `config validate` to check your config locally and on all remotes (`--local` skips the remote checks)
- Make the log output more coherent: green `✔` for successes, `⚠️ ` for warnings, `🚨` for errors, also for WP-CLI output
- Clean up the database sync output
- Require typing `push` to confirm `sync staging push`
- Fix `--config` being read as the sync mode in `sync`
- Hide PHP deprecation notices from WP-CLI
- Always deactivate maintenance mode, even if a sync fails or is canceled

## 4.1.0 - 2026-10-27

- Upload the tasks file to ~/.wp-sync-deploy and delete it after each run
- Upload WP-CLI from a local cache to ~/.wp-sync-deploy, share one SSH connection

## 4.0.0 - 2026-10-26

- Run task commands in-process to avoid PHP deprecation notices from WP-CLI child processes
- Add heading for the vendor deploy, indent version check details
- Fix line breaks before rsync output when stdout and stderr are read separately
- Delete locally removed folders despite default ignores, list leftovers, respect `NO_COLOR`, fix missing
line break before rsync output
- Suggest upgrading outdated projects via a `SessionStart` hook, document 2.x upgrade
- Prefer ignore patterns over `export-ignore` for deploy-only rules
- Fix documented `.allow-deployment` location (remote root dir)
- Never prompt on dry runs, summarize what a live deploy will ask instead
- Ask for confirmation when deploying composer dev dependencies
- Replace `.deployignore` with `ignore: new Ignore()`, respect `export-ignore` in `.gitattributes`
- Replace bare domains in multisite network tables on sync
- Also ask for confirmation when deploying unpushed commits to production
- Sync agent skill: generic scripts, `package.json` entry points, Herd PHP note, composer in themes
- Don't deploy the local `vendor` dir through other paths
- Create optional deploy paths on the remote instead of aborting
- Pass `--url` to remote WP-CLI calls
- Ask for confirmation when deploying uncommitted changes to production
- Run version checks before the success message, hide PHP deprecations from remote WP-CLI
- Deploy composer `vendor` dir without dev dependencies
- Use `Hirasso\WPSyncDeploy` namespace, require PHP >= 8.2
- Ship `wp-sync-deploy` agent skill
- Exclude `wp-sync-deploy.config.php` from deploys
- Add upgrade guide for 4.0.0
- Replace `.env.wp-sync-deploy` with typed `wp-sync-deploy.config.php`
- Replace deploy `run` argument with `--dry-run` flag, deploy live by default
