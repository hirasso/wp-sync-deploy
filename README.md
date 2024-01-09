# WordPress Deploy & Sync

A bash script that helps you

- sync your WordPress database from production/staging
- deploy your local changes to production/staging

> **Info** It's likely that this script won't work with your specific setup
out of the box, but it should be a good starting point.

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
