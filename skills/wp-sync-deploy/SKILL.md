---
name: wp-sync-deploy
description: Set up hirasso/wp-sync-deploy (database sync + rsync deploy for WordPress) in a project, or upgrade it from 2.x/3.x to 4.x. Use when the user wants to install, set up, configure or upgrade wp-sync-deploy, adds `hirasso/wp-sync-deploy` to composer.json, or a SessionStart hook reports an outdated version.
---

# wp-sync-deploy setup (4.x)

Source of truth for options: `vendor/hirasso/wp-sync-deploy/README.md`, `wp-sync-deploy.config.example.php` and `src/Config.php` (constructor signatures). Read them first; they may have changed.

## DDEV projects

If the project has a `.ddev/` folder, wp-sync-deploy always runs inside the web container, never on the host (the host has no database access, so WordPress values like the home URL can't be read):

- Prefix every command in this skill and in the user's instructions: `ddev composer …`, `ddev exec vendor/bin/wp-sync-deploy …`, `ddev exec pnpm production:deploy -- --dry-run`. SSH agent: `ddev auth ssh` (once per DDEV start).
- `local.url`: `getenv('DDEV_PRIMARY_URL') ?: throw new \RuntimeException('Run wp-sync-deploy inside DDEV')`, never a hardcoded URL.
- Secrets: the host shell env doesn't reach the container. Put them in `.ddev/.env.web` (loaded into the web container, `ddev restart` after changes) and check it's gitignored (`git check-ignore .ddev/.env.web`).

## 1. Install

- Always a dev dependency: `composer require --dev hirasso/wp-sync-deploy` (pre-release: `:^4.0@rc`). Already in `require` → `composer remove --no-update` it first, then require with `--dev`.
- Local PHP ≥ 8.2 and GNU `rsync` (not macOS openrsync) must exist. The remote SSH home dir must be writable. wp-sync-deploy brings its own WP-CLI, locally and remotely.

## 2. Setup

Run from the directory holding `composer.json` (config and tasks files are found by walking up from the package dir):

```bash
vendor/bin/wp-sync-deploy config init -n
```

Creates `wp-sync-deploy.tasks.php` and `wp-sync-deploy.config.php` with the local values detected from WordPress and placeholders for `production` (keeps existing files). Without `-n`, it asks interactively, so it's better suited for the user.

## 3. Configure `wp-sync-deploy.config.php`

Returns a typed `Hirasso\WPSyncDeploy\Config`. Keep the example's docblock and imports; drop unused imports.

- `local`: `url` from `WP_HOME`/`WP_HOME_DEV` in `wp-config.php` (DDEV: see [DDEV projects](#ddev-projects)). `rootDir` = WP root, relative to the config file via `__DIR__` / `dirname(__DIR__, n)`, never a hardcoded absolute path.
- `paths`: `wpContent`/`wpCore`/`public` relative to `rootDir` (verify with `ls`); omit `public` if empty.
- `git`: the checks are on by default if `rootDir` is in a git repo. Add `new Git()` only for a repo below `rootDir` (`dir`, e.g. the theme) or another production branch. `git: false` disables them: only on the user's request.
- `composer`: add `new Composer()` if the deployed code loads composer packages (root `vendor`, or a theme/plugin requiring its own `vendor/autoload.php`). `dir` = location of `composer.json` relative to `rootDir` (omit if it is the root). The vendor dir is then built and deployed without dev dependencies. Never put `vendor` in `additional` then. Deploys ask for confirmation if the vendor dir in the root or git repo contains dev packages (third-party plugin vendors aren't checked). `config validate` warns about runtime packages without `composer:`.
- Remotes: ask the user for SSH (`user@host`, port), absolute web root, PHP binary, and which remotes exist. Both `production` and `staging` are optional, at least one is required: omit the missing one (also a migrated `example.com` placeholder). Omit arguments that equal the defaults.
- `ignore`: extra deploy ignores go into `ignore: new Ignore(patterns: [...])`: explicit, one place for everything deploy-related. `export-ignore` in `.gitattributes` changes deploys silently as a side effect of an archive setting; use it only for themes/plugins that are also distributed as an archive (zip, `git archive`, wp.org), where "not in the zip" and "not deployed" mean the same.
  - Patterns are relative to `rootDir` and unanchored; `*` doesn't cross `/`, so `content/themes/x/*.md` only matches the theme root. Unlike the defaults, they keep locally removed folders alive on the remote, so no catch-alls like `.*`.
  - Repeated paths: define e.g. `$theme = 'content/themes/my-theme';` above `return new Config(...)` and reuse it in `git`, `composer` and the patterns.
  - Typical candidates in build-tool projects: source dirs (`assets-src`), build scripts (`build.mjs`, not covered by the `*.config.mjs` default), vendored tarballs, agent/dev docs (`AGENTS.md`, `CONTEXT.md`).
  - Check the `IGNORE_RULES` in the validation output (below).
- Secrets (http auth) → `getenv('…') ?: null`, never literal. Tell the user where to set the variable (shell, or `.ddev/.env.web` for DDEV) and write it there only after asking.
- Commit the file. Never gitignore it.
- Validate: `vendor/bin/wp-sync-deploy config validate` prints the resolved config and checks local paths and each remote (SSH, root, PHP, WP-CLI, URLs). Without SSH access: `--local`.

## Upgrading from 2.x

2.x was cloned into the project (`wp-sync-deploy/` folder, sometimes a git submodule) instead of installed via composer:

- Submodule (listed in `.gitmodules`) → `git submodule deinit -f wp-sync-deploy && git rm -f wp-sync-deploy`. Otherwise delete the folder and its `.gitignore` entry.
- Replace calls like `./wp-sync-deploy/deploy.sh` in scripts and docs with step 4.
- Then install (step 1) and continue with "Upgrading from 3.x".

## Upgrading from 3.x

- Run `vendor/bin/wp-sync-deploy config init -n`: creates the config from `.env.wp-sync-deploy` (local URL from WordPress) and `.deployignore`, removes both, applies the `run()` helper to simple tasks calls and lists what's left. Then run `config validate`.
- Several env files (e.g. `.env.wp-sync-deploy.<site>`, used via `--config=`): don't convert by hand, let the migrator do it per file. Copy one to `.env.wp-sync-deploy`, run `config init -n`, rename the result to `wp-sync-deploy.config.<site>.php` (init keeps an existing `wp-sync-deploy.config.php`), repeat, then `git rm` the originals and point the scripts' `--config=` at the new files.
- Then review the generated config against step 3 (e.g. ignore candidates, `composer`). Fix what validate reports (e.g. a wrong `local` protocol).
- Remove any `!.env.wp-sync-deploy` from `.gitignore`.
- `run` is gone, deploys are live by default: drop `run` from scripts; dry run is `--dry-run`. Replace old per-env composer scripts with step 4.
- Existing tasks file: check step 5 for calls `migrate` didn't convert.
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

Existing tasks file (on every setup or upgrade): if it calls `\WP_CLI::runcommand()` without `'launch' => false`, copy the `run()` helper from `vendor/hirasso/wp-sync-deploy/wp-sync-deploy.tasks.example.php` into it and replace those calls with `run('…')`. Calls that use the return value or other options: add `'launch' => false` to their options instead. Reason: WP-CLI child processes ignore wp-sync-deploy's PHP settings and print PHP 8.5 deprecation notices.

## 6. Preflight requirements (tell the user)

- The remote `rootDir` needs an empty `.allow-deployment` file.
- WordPress core, plugins and themes must already exist remotely; other deployed folders are created.
- Local CLI and web PHP must match the remote PHP version (Herd: `herd isolate <version>` sets only the web version; the CLI check uses plain `php`, so also `herd use <version>` or confirm the mismatch prompt; DDEV: `php_version` in `.ddev/config.yaml`). Mismatch → ask before switching.
- First deploy manually or via `upload`.
- A live deploy asks for confirmation on: a non-production branch, uncommitted or unpushed changes, a newer WordPress/plugin/theme on the remote, composer dev packages. `--dry-run` never asks and lists these at the end, so run it first.

## 7. Running it

A dry run is safe to run (`npm run production:deploy -- --dry-run`). If SSH isn't available to you, ask the user to run it. Never run a live deploy or a `push` sync (asks to type `push`) without explicit request.

Report what's configured and what the user must still do. Commit only when asked.

## Upgrade hint

`scripts/detect.sh` is a SessionStart hook that reports projects using an older major version. If the user declines the upgrade, run `bash <skill dir>/scripts/detect.sh snooze` in the project (quiet for 30 days).
