# WordPress Sync & Deploy

Sync and deploy your WordPress website between environments 🔀

- sync your WordPress database from production or staging to your local dev environment
- deploy your local core, plugins, mu-plugins and theme to production or staging
- run common tasks through wp-cli on the remote server to ensure your deploy works as expected
- tested on OSX and Linux systems

> [!NOTE]
>  For less technical users I recommend to use a plugin instead. For database migrations, I'd recommend [WP Migrate](https://deliciousbrains.com/wp-migrate-db-pro/). For deployment, I'd recommend good old (S)FTP.

## Prerequesites

- A writable SSH home directory on the **remote server**. wp-sync-deploy brings its own [WP-CLI](https://wp-cli.org/): the phar is cached locally at `~/.cache/wp-sync-deploy/wp-cli.phar` (updated weekly) and uploaded to `~/.wp-sync-deploy/wp-cli.phar` on the remote server, outside of the web root. Both run with PHP deprecation notices hidden.
- PHP >= 8.2 on your **local machine**
- A WordPress directory structure similar to this (adjustable through a [`wp-sync-deploy.config.php`](#configuration) file):

```shell
.
├── content # your WordPress content folder (equivalent to the standard wp-content)
│  ├── plugins
│  ├── themes
│  ├── ...
├── core # your WordPress core folder (wp-admin, wp-includes, ...)
├── index.php # main WordPress entry file
└── wp-config.php # your wp-config file
```

> [!TIP]
> While it's easy to setup the custom directory structure yourself, I'd recommend to use a framework
> like [Bedrock](https://roots.io/bedrock/), [WPStarter](https://github.com/wecodemore/wpstarter) or
> [wordplate](https://github.com/vinkla/wordplate). All of these provide amazing convencience features for
> modern WordPress development.

## Installation

```shell
composer require --dev hirasso/wp-sync-deploy
```

All commands are then available through a single binary:

```shell
vendor/bin/wp-sync-deploy <config|sync|deploy|upload> [args]
```

Optionally, add script aliases to your project's `composer.json`:

```json
"scripts": {
  "sync": "wp-sync-deploy sync",
  "deploy": "wp-sync-deploy deploy",
  "upload": "wp-sync-deploy upload"
},
"config": {
  "process-timeout": 0
}
```

…so that you can run `composer deploy production`. The `process-timeout` prevents composer from aborting long-running syncs and deploys.

> [!WARNING]
> Composer silently drops options like `--config` or `--paths` that are passed to script aliases. Separate them with `--`:
>
> ```shell
> composer deploy -- production --config=my-custom.config.php
> ```

### Setup

Run this command:

```shell
vendor/bin/wp-sync-deploy config init
```

(`vendor/bin/wp-sync-deploy setup` still works as an alias.) It detects your local WordPress setup (URL, root, core, content and public dirs, git repo, composer) through WP-CLI, asks for your remote servers with the detected values as defaults, writes the config and validates it.

With `-n` (`--no-interaction`, also used automatically without a terminal), it writes the detected local values and placeholders for the remote server without asking.

You should now have these two files in your working directory:

### `wp-sync-deploy.config.php`

This file holds all information about your environments (local, staging, production). See [Configuration](#configuration).

### `wp-sync-deploy.tasks.php`

This file is being used to run [automated tasks](https://github.com/hirasso/wp-sync-deploy?tab=readme-ov-file#run-automated-tasks-after-each-deploy--sync-) after deployment. You can adjust this file as you wish or delete it if you don't want it to be executed.

### Validate

After adjusting your config, check it:

```shell
vendor/bin/wp-sync-deploy config validate              # all environments
vendor/bin/wp-sync-deploy config validate production   # one environment
vendor/bin/wp-sync-deploy config validate --local      # skip the remote checks
```

This prints the resolved config and checks your local paths, git repo and rsync. For each remote, it checks the SSH connection, the remote root, `.allow-deployment` (deploy strategy `conservative`) and the command line PHP version, and uploads WP-CLI. It also compares each configured URL with the home URL in WordPress.

## Remote server preparation

wp-sync-deploy performs a few security checks before proceeding with a deploy:

- [x] Do all directories marked for deployment exist locally? Do the WordPress core, plugins and themes directories exist remotely? (other directories like `mu-plugins` are created if missing)
- [x] Does a hidden file `.allow-deployment` exist in the remote environment's root dir (`rootDir`)?
- [x] Does the local _command-line_ PHP version match the one on the remote environment?
- [x] Does the local _web-facing_ PHP version match the one on the remote environment?

So when you are starting, you will need to

- Perform the first deployment manually (or via the [upload](#simple-upload) command)
- Add an empty file `.allow-deployment` to your remote root dir (`rootDir`)
- Make sure that your local and remote server are set to use the same PHP version

## Usage

### Synchronise the database between environments

```shell
# sync the database from your production server
vendor/bin/wp-sync-deploy sync production

# sync the database from your staging server
vendor/bin/wp-sync-deploy sync staging

# push your local database to your staging server (asks you to type `push` to confirm)
vendor/bin/wp-sync-deploy sync staging push

# Backup the remote database and store it locally
vendor/bin/wp-sync-deploy sync <production|staging> backup
```

> [!NOTE]
> Syncing your local database is only possible to the staging server by default.
> If you are sure you know what you are doing, you can also enable syncing to
> the production server.

### Deploy your local files to remote environments

```shell
# preview the deploy to your production server (dry run)
vendor/bin/wp-sync-deploy deploy production --dry-run

# deploy your files to your production server
vendor/bin/wp-sync-deploy deploy production

# deploy your files to your staging server
vendor/bin/wp-sync-deploy deploy staging

# deploy without the confirmation prompt
vendor/bin/wp-sync-deploy deploy production --yes
```

> [!WARNING]
> Since 4.0.0, deploys are live by default. Use `--dry-run` for a preview.

A `--dry-run` never asks for confirmation. Instead, it lists everything a live deploy will ask about at the end.

### Composer dependencies

With `composer: new Composer()` in your config, wp-sync-deploy builds your `vendor` directory **without dev dependencies** in a temporary directory (`composer install --no-dev --optimize-autoloader`) and deploys that one. Your local `vendor` directory stays untouched. Don't add `vendor` to `additional` in this case.

If your `composer.json` is not in the root dir (e.g. inside your theme), pass its location: `new Composer(dir: 'content/themes/my-theme')`.

wp-sync-deploy asks for confirmation if a deployed `vendor` directory contains dev dependencies, and suggests the matching `new Composer()` config.
Before deploying, wp-sync-deploy asks for confirmation if the remote WordPress version is newer than the local one (e.g. after a security update applied on the server). The same goes for plugins and themes that are newer at the remote or missing locally (e.g. after an update or install via wp-admin), as the deploy would downgrade or remove them.

### Simple Upload

To make sure you are uploading to the correct directory, the remote directory needs to
contain a file `.allow-deployment`

```shell
# Upload files to the remote root
vendor/bin/wp-sync-deploy upload <environment> --paths

# For example:
vendor/bin/wp-sync-deploy upload staging --paths=".env wp-cli.yml config public vendor"
```

## Run automated tasks after each deploy / sync ✨

wp-sync-deploy will **automatically run tasks on the target server** when you sync or deploy. Modify the `wp-sync-deploy.tasks.php` file created by the [setup command](#setup), to customize which tasks should be executed. The file is uploaded to `~/.wp-sync-deploy/` on the remote server for each run (outside of the web root) and deleted afterwards.

Default tasks defined in the file are:

- Optionally delete all transients
- Optionally delete your static cache
- When deploying: Optionally update the rewrite rules

## Configuration

wp-sync-deploy is configured through a `wp-sync-deploy.config.php` file returning a typed `Hirasso\WPSyncDeploy\Config` object. Your IDE will autocomplete and document all options. Have a look at the [example file](wp-sync-deploy.config.example.php).

The file is meant to be **committed**. For secrets like HTTP auth credentials, use environment variables exported in your shell:

```php
httpAuth: getenv('STAGING_HTTP_AUTH') ?: null,
```

> [!IMPORTANT]
> Since 4.0.0, `.env.wp-sync-deploy` is not supported anymore. See [Upgrading from 3.x](#upgrading-from-3x).

### Custom config file

By default, wp-sync-deploy looks for the closest `wp-sync-deploy.config.php` file. You can override this with the `--config` option:

```shell
vendor/bin/wp-sync-deploy sync production --config=my-custom.config.php
vendor/bin/wp-sync-deploy deploy production --config=my-custom.config.php
vendor/bin/wp-sync-deploy upload staging --paths="..." --config=my-custom.config.php
```

> [!NOTE]
> `--config` must come after the required positional arguments.

## Ignored files

wp-sync-deploy ignores common dev files during a deploy (`node_modules`, dotfiles, `package.json`, `*.sql`, ...). See `Ignore::DEFAULTS` in [src/Config.php](src/Config.php) for the full list.

Add your own rules in your config:

```php
$theme = 'content/themes/my-theme';

return new Config(
    // ...
    ignore: new Ignore(
        patterns: ["$theme/assets-src", "$theme/build.mjs", "$theme/*.md"], // added to the defaults
        gitattributes: true, // respect export-ignore (default)
        defaults: true,      // use the built-in list (default)
    ),
);
```

Patterns are relative to your root dir and unanchored. `*` doesn't cross `/`, so `$theme/*.md` only matches Markdown files in the theme root.

Files marked as `export-ignore` in `.gitattributes` files inside your themes and plugins are not deployed either. That's handy for themes and plugins you also distribute as an archive (zip, `git archive`, wp.org), where "not in the zip" and "not deployed" mean the same. Otherwise, prefer `patterns`, so all deploy rules live in one place.

```gitattributes
/tests export-ignore
*.md export-ignore
```

Ignored files are never deleted on the remote, with one exception: when you remove a folder locally, its remote copy is deleted together with any files matched by the defaults or `export-ignore` (e.g. a leftover `.htaccess` or `node_modules`). Files matched by your own `patterns` are never touched, so they keep such a folder alive. Don't add catch-alls like `.*` there. Folders that can't be deleted are listed at the end of each deploy.

## Upgrading from 3.x

4.0.0 contains breaking changes. Most of them are migrated automatically:

```shell
vendor/bin/wp-sync-deploy config init
```

It finds your `.env.wp-sync-deploy` and asks for your setup with its values as defaults (the local URL comes from WordPress), so you can fill in what's new, e.g. `composer: new Composer()`. With `-n`, it uses the old values without asking. It writes `wp-sync-deploy.config.php` next to the old file (including custom `.deployignore` rules), removes the old files (`git rm` if tracked, otherwise renamed to `.bak`), uses the `run()` helper in your tasks file, lists what's left to do and runs [`config validate`](#validate).

- **Deploys are live by default.** The `run` argument has been removed. Use `--dry-run` for a preview
- **`.env.wp-sync-deploy` has been replaced by `wp-sync-deploy.config.php`.** `config init` converts it, see the table below for the mapping
- **PHP >= 8.2** is required on your local machine
- **`vendor` is deployed without dev dependencies** if you add `composer: new Composer()` and remove `vendor` from `additional`
- **`.deployignore` has been replaced** by [`ignore: new Ignore()`](#ignored-files). Its `-p` rules (e.g. `package.json`, `composer.json`, `*.config.js`, `README.md`) never worked before and are now applied

| `.env.wp-sync-deploy`                           | `wp-sync-deploy.config.php`         |
| ----------------------------------------------- | ----------------------------------- |
| `LOCAL_PROTOCOL` + `LOCAL_HOST`                 | `local: new Local(url: …)`          |
| `LOCAL_HTTP_AUTH`                               | `local: new Local(httpAuth: …)`     |
| `LOCAL_ROOT_DIR`                                | `local: new Local(rootDir: …)`      |
| `PUBLIC_DIR`                                    | `paths: new Paths(public: …)`       |
| `WP_CONTENT_DIR`                                | `paths: new Paths(wpContent: …)`    |
| `WP_CORE_DIR`                                   | `paths: new Paths(wpCore: …)`       |
| `ADDITIONAL_DIRS`                               | `paths: new Paths(additional: […])` |
| `vendor` in `ADDITIONAL_DIRS`                  | `composer: new Composer()`          |
| `GIT_DIR`                                       | `git: new Git(dir: …)`              |
| `PRODUCTION_BRANCH`                             | `git: new Git(productionBranch: …)` |
| `PROD_PROTOCOL` + `PROD_HOST`                   | `production: new Remote(url: …)`    |
| `PROD_SSH`, `PROD_SSH_PORT`                     | `ssh: …`, `sshPort: …`              |
| `PROD_ROOT_DIR`                                 | `rootDir: …`                        |
| `PROD_PHP_BINARY`                               | `phpBinary: …`                      |
| `PROD_HTTP_AUTH`                                | `httpAuth: …`                       |
| `PROD_DEPLOY_STRATEGY`                          | `deployStrategy: DeployStrategy::…` |
| `STAG_*`                                        | `staging: new Remote(…)`            |

In your `wp-sync-deploy.tasks.php`, run commands with `\WP_CLI::runcommand('…', ['launch' => false])` (see the `run()` helper in the [example file](wp-sync-deploy.tasks.example.php)). Otherwise, PHP 8.5 deprecation notices from WP-CLI show up for each command.

If you have a custom `.deployignore`, move your rules to `ignore: new Ignore(patterns: [...])` (see [Ignored files](#ignored-files)) and delete the file.

## AI agents

This repo ships an [agent skill](skills/wp-sync-deploy/SKILL.md) that sets up or upgrades wp-sync-deploy in your project:

```shell
npx skills add hirasso/wp-sync-deploy
```

Optionally, let Claude Code suggest the upgrade when you open a project using an older major version, with a `SessionStart` hook in `~/.claude/settings.json`:

```json
"hooks": {
  "SessionStart": [
    {
      "matcher": "startup",
      "hooks": [
        { "type": "command", "command": "bash ~/.claude/skills/wp-sync-deploy/scripts/detect.sh 2>/dev/null || true", "timeout": 10 }
      ]
    }
  ]
}
```

Adjust the path if the skill is installed elsewhere. Requires `jq` and `curl`.

## Other notes

Set `NO_COLOR=1` to disable colored output. Colors are also off when the output isn't a terminal.

Before each run, wp-sync-deploy checks if an important update is available and asks for confirmation before proceeding with an outdated version.
