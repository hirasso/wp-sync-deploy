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
- `composer`: add `new Composer()` if the deployed code loads composer packages (root `vendor`, or a theme/plugin requiring its own `vendor/autoload.php`). `dir` = location of `composer.json` relative to `rootDir` (omit if it is the root). The vendor dir is then built and deployed without dev dependencies. Never put `vendor` in `additional` then. Deploys warn about other deployed vendor dirs containing dev packages.
- Remotes: ask the user for SSH (`user@host`, port), absolute web root, PHP binary, and whether staging exists. No staging → omit `staging`. Omit arguments that equal the defaults.
- `ignore`: omit unless the project needs extra rules. Dev files inside a theme/plugin are better marked `export-ignore` in its `.gitattributes`.
- Secrets (http auth) → `getenv('…') ?: null`, never literal.
- Commit the file. Never gitignore it.
- Validate: `php -d display_errors=stderr vendor/hirasso/wp-sync-deploy/lib/config.php wp-sync-deploy.config.php` prints the resolved values.

## Upgrading from 3.x

- Map `.env.wp-sync-deploy` to the config file using the README's "Upgrading from 3.x" table; validate (above) and compare against the old values.
- `vendor` in `ADDITIONAL_DIRS` becomes `composer: new Composer()` (dev dependencies are no longer deployed).
- `git rm` `.env.wp-sync-deploy`; remove any `!.env.wp-sync-deploy` from `.gitignore`.
- `run` is gone, deploys are live by default: drop `run` from scripts; dry run is `--dry-run`. Replace old per-env composer scripts with step 4.
- Project has its own `.deployignore` → move rules that aren't in `Ignore::DEFAULTS` to `ignore: new Ignore(patterns: [...])`, then `git rm` the file.
- Update mentions in `AGENTS.md`.

## 4. Scripts

Generic composer scripts, environment passed as argument:

```json
"scripts": {
  "deploy": "wp-sync-deploy deploy",
  "sync": "wp-sync-deploy sync"
},
"config": { "process-timeout": 0 }
```

Per-environment entry points in `package.json`, building assets before deploying (add `staging:*` only if staging exists; use the project's package manager and build script):

```json
"production:deploy": "npm run build && composer deploy -- production",
"production:db:pull": "composer sync -- production"
```

Always `composer <script> -- <args>`: without `--`, composer silently drops options like `--dry-run` (→ a live deploy). With it, appended options pass through: `npm run production:deploy -- --dry-run`. No package.json (no build) → call composer directly: `composer deploy -- production --dry-run`.

## 5. Tasks file

Review `wp-sync-deploy.tasks.php` against the site (e.g. caching plugin present?). Keep it unless the user wants changes.

## 6. Preflight requirements (tell the user)

- Remote web root needs an empty `.allow-deployment` file.
- Local CLI and web PHP must match the remote PHP version (Herd: `herd isolate <version>` sets only the web version; the CLI check uses plain `php`, so also `herd use <version>` or confirm the mismatch prompt; DDEV: `php_version` in `.ddev/config.yaml`). Mismatch → ask before switching.
- First deploy manually or via `upload`.

## 7. Running it

A dry run is safe to run (`npm run production:deploy -- --dry-run`). If SSH isn't available to you, ask the user to run it. Never run a live deploy or a `push` sync without explicit request.

Report what's configured and what the user must still do. Commit only when asked.
