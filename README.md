# WordPress Deploy & Sync

A bash script for

- syncing your WordPress database from production
- deploying your local changes to production

## Prerequesites

This script assumes a directory structure like this (adjustable through an `.env` file):

```bash
.
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
