# WordPress Sync & Deploy

A bash script that helps you

- sync your WordPress database from production or staging to your local dev environment
- deploy your local core, plugins, mu-plugins and theme to production or staging
- run common tasks through wp-cli on the remote server to ensure your deploy works as expected
- tested on OSX and Linux systems

> [!NOTE]
>  For less technical users I recommend to use a plugin instead. For database migrations, I'd recommend [WP Migrate](https://deliciousbrains.com/wp-migrate-db-pro/). For deployment, I'd recommend good old (S)FTP.

## Prerequesites

- [WP-CLI](https://wp-cli.org/) installed on your **local machine**. On the remote server, wp-sync-deploy takes care of installing WP-CLI automatically.
- A WordPress directory structure similar to this (adjustable through a `.env.wp-sync-deploy` file):

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
# CD into your project's root folder
cd /path/to/your/root

# Clone this repo
git clone git@github.com:hirasso/wp-sync-deploy.git

# Make sure the scripts are exectutable
chmod +x ./wp-sync-deploy/*.sh
```

Alternatively, you can install this script as submodule:

```shell
git submodule add git@github.com:hirasso/wp-sync-deploy.git
```

If you want to clone your main repo and already have wp-sync-deploy as a submodule, use this command:

```shell
git clone --recurse-submodules git@github.com:yourname/your-repo.git
```

### Setup

Run this script:

```shell
./wp-sync-deploy/setup.sh
```

This will move the required configuration files to your current working directory and remove the `.example` part. You should now have these two files in your working directory:

### `.env.wp-sync-deploy`

This file holds all information about your various environments (local, staging, production). Make sure you **add `.env.wp-sync-deploy` to your `.gitignore` file**! Otherwise, it's possible that sensitive information makes it into your repo.

VSCode can [syntax highlight](https://fredriccliver.medium.com/give-highlight-and-formatting-on-your-env-file-in-vscode-8e60934efce0) the env file for you.

### `wp-sync-deploy.tasks.php`

This file is being used to run [automated tasks](https://github.com/hirasso/wp-sync-deploy?tab=readme-ov-file#run-automated-tasks-after-each-deploy--sync-) after deployment. You can adjust this file as you wish or delete it if you don't want it to be executed.

## Remote server preparation

wp-sync-deploy performs a few security checks before proceeding with a deploy:

- [x] Do all directories marked for deployment actually exist in both environments (locally and remotely)?
- [x] Does a hidden file `.allow-deployment` exist on the remote environment's web root?
- [x] Does the local _command-line_ PHP version match the one on the remote environment?
- [x] Does the local _web-facing_ PHP version match the one on the remote environment?

So when you are starting, you will need to

- Perform the first deployment manually
- Add an empty file `.allow-deployment` to your remote web root
- Make sure that your local and remote server are set to use the same PHP version

## Usage

### Synchronise the database between environments

```shell
# sync the database from your production server
./wp-sync-deploy/sync.sh production

# sync the database from your staging server
./wp-sync-deploy/sync.sh staging

# push your local database to your staging server
./wp-sync-deploy/sync.sh staging push

# Backup the remote database and store it locally
./wp-sync-deploy/sync.sh <production|staging> backup
```

> [!NOTE]
> Syncing your local database is only possible to the staging server by default.
> If you are sure you know what you are doing, you can also enable syncing to
> the production server.

### Deploy your local files to remote environments

```shell
# deploy your files to your production server (dry)
./wp-sync-deploy/deploy.sh production

# deploy your files to your staging server (dry)
./wp-sync-deploy/deploy.sh staging

# deploy your files to your production server (non-dry)
./wp-sync-deploy/deploy.sh production run

# deploy your files to your staging server (non-dry)
./wp-sync-deploy/deploy.sh staging run
```

## Run automated tasks after each deploy / sync ✨

wp-sync-deploy will **automatically run tasks on the target server** when you sync or deploy. Modify the `wp-sync-deploy.tasks.php` file created by the [setup script](#setup), to customize which tasks should be executed.

Default tasks defined in the file are:

- Optionally delete all transients
- Optionally delete your static cache
- When deploying: Optionally update the rewrite rules

## Other notes

wp-sync-deploy has a default list of files and directories that will be ignored during a deploy. If you wish to customize this list, you can do so by modifying the file [.deployignore](https://github.com/hirasso/wp-sync-deploy/blob/main/.deployignore).