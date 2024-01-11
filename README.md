# WordPress Sync & Deploy

A bash script that helps you

- sync your WordPress database from production or staging to your local dev environment
- deploy your local core, plugins and theme folders to production or staging

> [!NOTE]
> It's likely that this script won't work with your specific setup
> out of the box, but it should be a good starting point. For less technical
> users I recommend to use a plugin like [WP Migrate](https://deliciousbrains.com/wp-migrate-db-pro/) from Delicious Brains instead.

## Prerequesites

- [WP-CLI](https://wp-cli.org/) installed locally on your machine
- Not required but nice for some convenience: WP-CLI also installed on the remote machine
- A WordPress directory structure like this (adjustable through a `wp-sync-deploy.env` file):

```bash
.
├── wp-sync-deploy.env # your .env file, copied and adjusted from the .env.example file in this repo
├── content # your WordPress content folder (equivalent to the standard wp-content)
│  ├── plugins
│  ├── themes
│  ├── ...
├── core # your WordPress core folder (wp-admin, wp-includes, ...)
├── index.php # main WordPress entry file
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
```

Alternatively, you can install this script as submodule:

```bash
git submodule add git@github.com:hirasso/wp-sync-deploy.git
```
If you want to clone your main repo and already have wp-sync-deploy as a submodule, use this command:

```bash
git clone --recurse-submodules git@github.com:yourname/your-repo.git
```

Now, move the file `wp-sync-deploy.example.env` into your webroot, rename it to `wp-sync-deploy.env` and adjust all variables for your needs. VSCode can [syntax highlight](https://fredriccliver.medium.com/give-highlight-and-formatting-on-your-env-file-in-vscode-8e60934efce0) the env file for you.

## Remote server preparation

Since deploying can be a pretty destructive task, the script performs a few security checks before proceeding:

- It checks if all directories actually exist in both environments (locally and remotely)
- It checks if a hidden file `.allow-deployment` is present at the destination.
- It checks if the *web-facing* (NOT CLI) PHP versions match between your local and remote environments

So when you are starting, you will need to

- perform the first deployment manually
- Add an empty file `.allow-deployment` to your remote webroot
- Make sure that your local and remote server are set to use the same PHP version

## Usage

Run of the following scripts:

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

## Things to check after deployment:

- [ ] Were the rewrite rules updated? (If your remote server has WP-CLI installed, the script does this automatically)
- [ ] Was the cache flushed? (If you are using [WP Super Cache](https://wordpress.org/plugins/wp-super-cache/), the script does this automatically)
- [ ] Any other cached things to take care of? (transients, for example)

