# WordPress Deploy & Sync

A bash script that helps you

- sync your WordPress database from production/staging
- deploy your local changes to production/staging

> [!NOTE]
> It's likely that this script won't work with your specific setup
> out of the box, but it should be a good starting point. For less technical
> users I recommend to use a plugin like [WP Migrate](https://deliciousbrains.com/wp-migrate-db-pro/) from Delicious Brains instead.

## Prerequesites

This script assumes a directory structure like this (adjustable through an `.env` file):

```bash
.
├── .env # your .env file, copied and adjusted from the .env.example file in this repo
├── content # your wp-content folder
│  ├── index.php
│  ├── languages
│  ├── plugins
│  ├── themes
├── core # your wp core folder
│  ├── index.php
│  ├── license.txt
│  ├── liesmich.html
│  ├── readme.html
│  ├── wp-activate.php
│  ├── wp-admin
│  ├── wp-blog-header.php
│  ├── wp-comments-post.php
│  ├── wp-config-sample.php
│  ├── wp-cron.php
│  ├── wp-includes
│  ├── wp-links-opml.php
│  ├── wp-load.php
│  ├── wp-login.php
│  ├── wp-mail.php
│  ├── wp-settings.php
│  ├── wp-signup.php
│  ├── wp-trackback.php
│  └── xmlrpc.php
├── index.php # main entry file
├── wp-config.php # your wp-config file
└── wp-sync-deploy # this repo
   └── wp-sync-deploy.sh
```

## Installation

```bash
# CD into your projects webroot
cd /path/to/your/webroot

# clone this repo
git clone git@github.com:hirasso/wp-sync-deploy.git

# make the script exectutable
chmod +x ./wp-sync-deploy/wp-sync-deploy.sh
#
```

## Remote server preparation

Since deploying can be a pretty destructive task, the script performs a few security checks before proceeding:

- It checks if all `$DEPLOY_DIRS` actually exist at both destinations (locally and remotely)
- It checks if a hidden file `.allow-deployment` is present at the destination.

So when you are starting, you will need to

- perform the first deployment manually (through ssh or FTP)
- Add an empty file `.allow-deployment` to your remote webroot

## Usage

1. Move the file `.env.example` into your webroot, rename it to `.env` and adjust all variables for your needs

2. Run the script:

```bash
# sync the database from your production server
./wp-sync-deploy/wp-sync-deploy.sh sync production

# sync the database from your staging server
./wp-sync-deploy/wp-sync-deploy.sh sync staging

# deploy your files to your production server (dry)
./wp-sync-deploy/wp-sync-deploy.sh deploy production

# deploy your files to your staging server (dry)
./wp-sync-deploy/wp-sync-deploy.sh deploy staging

# deploy your files to your production server (non-dry)
./wp-sync-deploy/wp-sync-deploy.sh deploy production run

# deploy your files to your staging server (non-dry)
./wp-sync-deploy/wp-sync-deploy.sh deploy staging run
```
