---
name: wp-sync-deploy
description: Set up hirasso/wp-sync-deploy (database sync + rsync deploy for WordPress) in a project, or upgrade it from 3.x to 4.x. Use when the user wants to install, set up, configure or upgrade wp-sync-deploy, or adds `hirasso/wp-sync-deploy` to composer.json.
---

# wp-sync-deploy setup (4.x)

Source of truth for options: `vendor/hirasso/wp-sync-deploy/README.md`, `wp-sync-deploy.config.example.php` and `src/Config.php` (constructor signatures). Read them first; they may have changed.

## 1. Install

- Always a dev dependency: `composer require --dev hirasso/wp-sync-deploy` (pre-release: `:^4.0@rc`). Already in `require` → `composer remove --no-update` it first, then require with `--dev`.
- Local `wp` (WP-CLI), PHP ≥ 8.2 and GNU `rsync` (not macOS openrsync) must exist.

## 2. Setup

Run from the directory holding `composer.json` (config and tasks files are found by walking up from the package dir):

```bash
echo y | vendor/bin/wp-sync-deploy setup
```

Creates `wp-sync-deploy.config.php` and `wp-sync-deploy.tasks.php` (keeps existing ones).

## 3. Configure `wp-sync-deploy.config.php`

Returns a typed `Hirasso\WPSyncDeploy\Config`. Keep the example's docblock and imports; drop unused imports.

- `local`: `url` from `WP_HOME`/`WP_HOME_DEV` in `wp-config.php` (or `ddev describe`). `rootDir` = WP root, relative to the config file via `__DIR__` / `dirname(__DIR__, n)`, never a hardcoded absolute path.
- `paths`: `wpContent`/`wpCore`/`public` relative to `rootDir` (verify with `ls`); omit `public` if empty.
- `git`: `dir` = repo path relative to `rootDir` (omit if the repo is the root).
- `composer`: add `new Composer()` if the project deploys composer packages (`dir` = location of `composer.json` relative to `rootDir`, omit if it is the root). Never put `vendor` in `additional` then.
- Remotes: ask the user for SSH (`user@host`, port), absolute web root, PHP binary, and whether staging exists. No staging → omit `staging`. Omit arguments that equal the defaults.
- Secrets (http auth) → `getenv('…') ?: null`, never literal.
- Commit the file. Never gitignore it.
- Validate: `php -d display_errors=stderr vendor/hirasso/wp-sync-deploy/lib/config.php wp-sync-deploy.config.php` prints the resolved values.

## Upgrading from 3.x

- Map `.env.wp-sync-deploy` to the config file using the README's "Upgrading from 3.x" table; validate (above) and compare against the old values.
- `vendor` in `ADDITIONAL_DIRS` becomes `composer: new Composer()` (dev dependencies are no longer deployed).
- `git rm` `.env.wp-sync-deploy`; remove any `!.env.wp-sync-deploy` from `.gitignore`.
- `run` is gone, deploys are live by default: drop `run` from scripts; dry run is `--dry-run`.
- Update mentions in `AGENTS.md`.
- Custom `.deployignore` in the project: add `wp-sync-deploy.config.php`.

## 4. Composer scripts

One set per remote environment, pointing directly at it (add `staging:*` only if staging exists):

```json
"scripts": {
  "production:sync": "wp-sync-deploy sync production",
  "production:deploy": "wp-sync-deploy deploy production",
  "production:upload": "wp-sync-deploy upload production"
},
"config": { "process-timeout": 0 }
```

Extra args/options go after `--` (composer drops them otherwise): `composer production:deploy -- --dry-run`, `composer production:upload -- --paths="…"`.

## 5. Tasks file

Review `wp-sync-deploy.tasks.php` against the site (e.g. caching plugin present?). Keep it unless the user wants changes.

## 6. Preflight requirements (tell the user)

- Remote web root needs an empty `.allow-deployment` file.
- Local CLI and web PHP must match the remote PHP version (Herd: `herd isolate <version>` in the WP root; DDEV: `php_version` in `.ddev/config.yaml`). Mismatch → ask before switching.
- First deploy manually or via `upload`.

## 7. Running it

A dry run is safe to run: `composer production:deploy -- --dry-run`. If SSH isn't available to you, ask the user to run it. Never run a live deploy or a `push` sync without explicit request.

Report what's configured and what the user must still do. Commit only when asked.
