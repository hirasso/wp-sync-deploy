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
├── wp-sync-deploy.env # your .env file, copied and adjusted from the wp-sync-deploy.example file in this repo
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

### Adjust the variables

Now, move the file `wp-sync-deploy.example.env` into your webroot, rename it to `wp-sync-deploy.env` and adjust all variables for your needs. VSCode can [syntax highlight](https://fredriccliver.medium.com/give-highlight-and-formatting-on-your-env-file-in-vscode-8e60934efce0) the env file for you.

> [!CAUTION]
> Make sure you add `wp-sync-deploy.env` to your `.gitignore` file!
> otherwise, it's likely that sensitive information makes it to your repo.

## Remote server preparation

Since deploying can be a pretty destructive task, the script performs a few security checks before proceeding:

- [x] Do all directories marked for deployment actually exist in both environments (locally and remotely)?
- [x] Does a hidden file `.allow-deployment` exist on the remote environment's web root?
- [x] Does the local _command-line_ PHP version match the one on the remote environment?
- [x] Does the local _web-facing_ PHP version match the one on the remote environment?

So when you are starting, you will need to

- Perform the first deployment manually
- Add an empty file `.allow-deployment` to your remote web root
- Make sure that your local and remote server are set to use the same PHP version
- Optional: Install WP-CLI on the remote server. This will unlock additional functionality in your script

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

- [ ] Do you have to update your rewrite rules? (The script attempts to do this automatically)
- [ ] - [ ] Do you need to delete transients on the remote server? (The script attempts to do this automatically)
- [ ] Was the cache flushed? (If you are using [WP Super Cache](https://wordpress.org/plugins/wp-super-cache/), the script attempts to do this automatically)

## WP-CLI on the remote server

To ensure compatibility with the widest range of hosting servers, this script installs WP-CLI automatically on the remote server. This also has the advantage that you can provide a custom
alias for the `php` binary to be used on the remote server (handy scenarios where staging and
production share the same server)
