<?php

namespace Hirasso\WPSyncDeploy;

use InvalidArgumentException;

/**
 * The wp-sync-deploy configuration
 * @see https://github.com/hirasso/wp-sync-deploy#configuration
 */
final readonly class Config
{
    /**
     * @param Local $local The local environment
     * @param Paths $paths Directories, relative to the root dir (same in all environments)
     * @param Remote $production The production environment
     * @param Remote|null $staging The staging environment (optional)
     * @param Git|false|null $git Git checks before deploying to production. Default: on if the root dir is in a git repo, `false` disables them
     * @param Composer|null $composer Deploy the composer vendor dir without dev dependencies (optional)
     * @param Ignore $ignore Files and directories that won't be deployed
     */
    public function __construct(
        public Local $local,
        public Paths $paths,
        public Remote $production,
        public ?Remote $staging = null,
        public Git|false|null $git = null,
        public ?Composer $composer = null,
        public Ignore $ignore = new Ignore(),
    ) {}

    /** Export as shell variables, to be eval'd by bash */
    public function toShell(): string
    {
        $vars = [
            'LOCAL_HOST' => $this->local->host(),
            'LOCAL_PROTOCOL' => $this->local->protocol(),
            'LOCAL_HTTP_AUTH' => $this->local->httpAuth ?? '',
            'LOCAL_ROOT_DIR' => $this->local->rootDir,
            'PUBLIC_DIR' => $this->paths->public,
            'WP_CONTENT_DIR' => $this->paths->wpContent,
            'WP_CORE_DIR' => $this->paths->wpCore,
            ...$this->remoteVars('PROD_', $this->production),
            'IGNORE_RULES' => implode("\n", $this->ignore->rules()),
            'IGNORE_GITATTRIBUTES' => $this->ignore->gitattributes ? '1' : '',
        ];

        if ($this->staging) {
            $vars = [...$vars, ...$this->remoteVars('STAG_', $this->staging)];
        }

        if ($this->paths->additional) {
            $vars['ADDITIONAL_DIRS'] = implode(' ', $this->paths->additional);
        }

        $git = $this->git ?? ($this->isInGitRepo() ? new Git() : false);
        $vars['GIT_CHECKS'] = match (true) {
            $this->git instanceof Git => 'configured',
            $this->git === false => 'disabled',
            $git instanceof Git => 'detected',
            default => 'no-repo',
        };
        if ($git) {
            $vars['GIT_DIR'] = $git->dir;
            $vars['PRODUCTION_BRANCH'] = $git->productionBranch;
        }

        if ($this->composer) {
            $vars['COMPOSER_DIR'] = $this->composer->dir;
        }

        $lines = [];
        foreach ($vars as $name => $value) {
            $lines[] = "$name=" . escapeshellarg((string) $value);
        }
        return implode(PHP_EOL, $lines) . PHP_EOL;
    }

    private function isInGitRepo(): bool
    {
        for ($dir = $this->local->rootDir; $dir !== dirname($dir); $dir = dirname($dir)) {
            if (file_exists("$dir/.git")) {
                return true;
            }
        }
        return false;
    }

    /** @return array<string, string|int> */
    private function remoteVars(string $prefix, Remote $remote): array
    {
        return [
            "{$prefix}HOST" => $remote->host(),
            "{$prefix}PROTOCOL" => $remote->protocol(),
            "{$prefix}HTTP_AUTH" => $remote->httpAuth ?? '',
            "{$prefix}ROOT_DIR" => $remote->rootDir,
            "{$prefix}SSH" => $remote->ssh,
            "{$prefix}SSH_PORT" => $remote->sshPort,
            "{$prefix}PHP_BINARY" => $remote->phpBinary,
            "{$prefix}DEPLOY_STRATEGY" => $remote->deployStrategy->value,
        ];
    }
}

/**
 * The local environment
 */
final readonly class Local
{
    use HasUrl;

    /**
     * @param string $url The local URL, e.g. 'https://example.test'
     * @param string $rootDir Absolute path to the project root, usually __DIR__
     * @param string|null $httpAuth HTTP authentication, e.g. 'username:password' (optional)
     */
    public function __construct(
        public string $url,
        public string $rootDir,
        public ?string $httpAuth = null,
    ) {
        $this->validateUrl($url);
        validateAbsolutePath($rootDir, 'rootDir');
    }
}

/**
 * A remote environment (production or staging)
 */
final readonly class Remote
{
    use HasUrl;

    /**
     * @param string $url The remote URL, e.g. 'https://example.com'
     * @param string $ssh The SSH connection, e.g. 'username@example.com'
     * @param string $rootDir Absolute path to the project root on the remote server
     * @param int $sshPort The SSH port
     * @param string $phpBinary The command line PHP binary on the remote server
     * @param DeployStrategy $deployStrategy Conservative runs all preflight checks, risky skips most of them
     * @param string|null $httpAuth HTTP authentication, e.g. 'username:password' (optional)
     */
    public function __construct(
        public string $url,
        public string $ssh,
        public string $rootDir,
        public int $sshPort = 22,
        public string $phpBinary = 'php',
        public DeployStrategy $deployStrategy = DeployStrategy::Conservative,
        public ?string $httpAuth = null,
    ) {
        $this->validateUrl($url);
        validateAbsolutePath($rootDir, 'rootDir');
        validateNotEmpty($ssh, 'ssh');
    }
}

/**
 * Directories, relative to the root dir
 */
final readonly class Paths
{
    /**
     * @param string $wpContent The WordPress content directory, e.g. 'web/app'
     * @param string $wpCore The WordPress core directory, e.g. 'web/wp'
     * @param string $public The public web root, e.g. 'web' (optional)
     * @param string[] $additional Additional directories to deploy, e.g. ['vendor', 'config'] (optional)
     */
    public function __construct(
        public string $wpContent,
        public string $wpCore,
        public string $public = '',
        public array $additional = [],
    ) {
        validateNotEmpty($wpContent, 'wpContent');
        validateNotEmpty($wpCore, 'wpCore');
    }
}

/**
 * Check the git branch and uncommitted/unpushed changes before deploying to production
 */
final readonly class Git
{
    /**
     * @param string $dir The git repo, relative to the root dir
     * @param string $productionBranch Regex of branch(es) allowed to deploy to production
     */
    public function __construct(
        public string $dir = '',
        public string $productionBranch = 'master|main',
    ) {}
}

/**
 * Files and directories that won't be deployed
 */
final readonly class Ignore
{
    /**
     * Built-in patterns. Applied as perishable rules (`-p`), so they never keep
     * a remote folder alive that was removed locally
     */
    public const DEFAULTS = [
        // wp-sync-deploy isn't built to deal with the default WordPress folder structure
        'wp-content',
        // Dotfiles, env files
        '.*',
        '*.env',
        // Package managers
        'node_modules',
        'package.json',
        'package-lock.json',
        'pnpm-*.yaml',
        'composer.json',
        'composer.lock',
        // Build configs
        '*.config.js',
        '*.config.mjs',
        '*.config.ts',
        '*.config.mts',
        'tsconfig.json',
        // Files from this tool
        'wp-sync-deploy',
        'wp-sync-deploy.config.php',
        'wp-sync-deploy.tasks.php',
        // Logs, DB dumps, docs, todos
        '*.log',
        '*.sql',
        'README.md',
        'readme.md',
        'TODO',
        '*.todo',
    ];

    /**
     * @param string[] $patterns Additional rsync exclude patterns, e.g. ['*.zip', 'content/themes/my-theme/build.mjs']
     * @param bool $gitattributes Respect `export-ignore` in .gitattributes files inside the deploy paths
     * @param bool $defaults Use the built-in rules (Ignore::DEFAULTS)
     */
    public function __construct(
        public array $patterns = [],
        public bool $gitattributes = true,
        public bool $defaults = true,
    ) {}

    /** @return string[] */
    public function rules(): array
    {
        $defaults = $this->defaults ? array_map(fn ($pattern) => "-p $pattern", self::DEFAULTS) : [];

        // Plain patterns become exclude rules, which also protect remote folders from being removed
        $patterns = array_map(fn ($rule) => preg_match('/^[-+][a-z]* /', $rule) ? $rule : "- $rule", $this->patterns);

        return [...$defaults, ...$patterns];
    }
}

/**
 * Deploy the composer vendor dir without dev dependencies
 */
final readonly class Composer
{
    /**
     * @param string $dir The directory containing composer.json, relative to the root dir
     */
    public function __construct(
        public string $dir = '',
    ) {}
}

enum DeployStrategy: string
{
    /** Run all preflight checks and ask for confirmation */
    case Conservative = 'conservative';
    /** Skip most preflight checks */
    case Risky = 'risky';
}

trait HasUrl
{
    /** The host including port and path, e.g. 'example.test:8443' */
    public function host(): string
    {
        return rtrim(explode('://', $this->url, 2)[1], '/');
    }

    public function protocol(): string
    {
        return explode('://', $this->url, 2)[0];
    }

    private function validateUrl(string $url): void
    {
        if (!preg_match('#^https?://[^/]+#', $url)) {
            throw new InvalidArgumentException("Invalid url: '$url'");
        }
    }
}

function validateAbsolutePath(string $path, string $name): void
{
    if (!str_starts_with($path, '/')) {
        throw new InvalidArgumentException("$name must be an absolute path: '$path'");
    }
}

function validateNotEmpty(string $value, string $name): void
{
    if (trim($value) === '') {
        throw new InvalidArgumentException("$name must not be empty");
    }
}
