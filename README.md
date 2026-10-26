# WordPress Sync & Deploy

Sync and deploy your WordPress website between environments 🔀

- sync your WordPress database from production or staging to your local dev environment
- deploy your local core, plugins, mu-plugins and theme to production or staging
- run common tasks through wp-cli on the remote server to ensure your deploy works as expected
- tested on OSX and Linux systems

> [!NOTE]
>  For less technical users I recommend to use a plugin instead. For database migrations, I'd recommend [WP Migrate](https://deliciousbrains.com/wp-migrate-db-pro/). For deployment, I'd recommend good old (S)FTP.

## Prerequesites

- [WP-CLI](https://wp-cli.org/) installed on your **local machine**. On the remote server, wp-sync-deploy takes care of installing WP-CLI automatically.
- PHP >= 8.1 on your **local machine**
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
vendor/bin/wp-sync-deploy <setup|sync|deploy|upload> [args]
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
vendor/bin/wp-sync-deploy setup
```

This will move the required configuration files to your current working directory and remove the `.example` part. You should now have these two files in your working directory:

### `wp-sync-deploy.config.php`

This file holds all information about your environments (local, staging, production). See [Configuration](#configuration).

### `wp-sync-deploy.tasks.php`

This file is being used to run [automated tasks](https://github.com/hirasso/wp-sync-deploy?tab=readme-ov-file#run-automated-tasks-after-each-deploy--sync-) after deployment. You can adjust this file as you wish or delete it if you don't want it to be executed.

## Remote server preparation

wp-sync-deploy performs a few security checks before proceeding with a deploy:

- [x] Do all directories marked for deployment actually exist in both environments (locally and remotely)?
- [x] Does a hidden file `.allow-deployment` exist on the remote environment's web root?
- [x] Does the local _command-line_ PHP version match the one on the remote environment?
- [x] Does the local _web-facing_ PHP version match the one on the remote environment?

So when you are starting, you will need to

- Perform the first deployment manually (or via the [upload](#simple-upload) command)
- Add an empty file `.allow-deployment` to your remote web root
- Make sure that your local and remote server are set to use the same PHP version

## Usage

### Synchronise the database between environments

```shell
# sync the database from your production server
vendor/bin/wp-sync-deploy sync production

# sync the database from your staging server
vendor/bin/wp-sync-deploy sync staging

# push your local database to your staging server
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

wp-sync-deploy will **automatically run tasks on the target server** when you sync or deploy. Modify the `wp-sync-deploy.tasks.php` file created by the [setup command](#setup), to customize which tasks should be executed.

Default tasks defined in the file are:

- Optionally delete all transients
- Optionally delete your static cache
- When deploying: Optionally update the rewrite rules

## Configuration

wp-sync-deploy is configured through a `wp-sync-deploy.config.php` file returning a typed `WPSyncDeploy\Config` object. Your IDE will autocomplete and document all options. Have a look at the [example file](wp-sync-deploy.config.example.php).

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

## Upgrading from 3.x

4.0.0 contains breaking changes:

- **Deploys are live by default.** The `run` argument has been removed. Use `--dry-run` for a preview
- **`.env.wp-sync-deploy` has been replaced by `wp-sync-deploy.config.php`.** Run the [setup command](#setup), move your settings over and delete the old file
- **PHP >= 8.1** is required on your local machine

| `.env.wp-sync-deploy`                           | `wp-sync-deploy.config.php`         |
| ----------------------------------------------- | ----------------------------------- |
| `LOCAL_PROTOCOL` + `LOCAL_HOST`                 | `local: new Local(url: …)`          |
| `LOCAL_HTTP_AUTH`                               | `local: new Local(httpAuth: …)`     |
| `LOCAL_ROOT_DIR`                                | `local: new Local(rootDir: …)`      |
| `PUBLIC_DIR`                                    | `paths: new Paths(public: …)`       |
| `WP_CONTENT_DIR`                                | `paths: new Paths(wpContent: …)`    |
| `WP_CORE_DIR`                                   | `paths: new Paths(wpCore: …)`       |
| `ADDITIONAL_DIRS`                               | `paths: new Paths(additional: […])` |
| `GIT_DIR`                                       | `git: new Git(dir: …)`              |
| `PRODUCTION_BRANCH`                             | `git: new Git(productionBranch: …)` |
| `PROD_PROTOCOL` + `PROD_HOST`                   | `production: new Remote(url: …)`    |
| `PROD_SSH`, `PROD_SSH_PORT`                     | `ssh: …`, `sshPort: …`              |
| `PROD_ROOT_DIR`                                 | `rootDir: …`                        |
| `PROD_PHP_BINARY`                               | `phpBinary: …`                      |
| `PROD_HTTP_AUTH`                                | `httpAuth: …`                       |
| `PROD_DEPLOY_STRATEGY`                          | `deployStrategy: DeployStrategy::…` |
| `STAG_*`                                        | `staging: new Remote(…)`            |

If you have a custom `.deployignore`, add `wp-sync-deploy.config.php` to it.

## AI agents

This repo ships an [agent skill](skills/wp-sync-deploy/SKILL.md) that sets up or upgrades wp-sync-deploy in your project:

```shell
npx skills add hirasso/wp-sync-deploy
```

## Other notes

wp-sync-deploy has a default list of files and directories that will be ignored during a deploy. If you wish to customize this list, copy the default [.deployignore](https://github.com/hirasso/wp-sync-deploy/blob/main/.deployignore) to your project root and adjust it there. It will then be used instead of the default one.

Before each run, wp-sync-deploy checks if an important update is available and asks for confirmation before proceeding with an outdated version.
