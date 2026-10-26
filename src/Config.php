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
     * @param Git|null $git Validate the git branch before deploying to production (optional)
     * @param Composer|null $composer Deploy the composer vendor dir without dev dependencies (optional)
     */
    public function __construct(
        public Local $local,
        public Paths $paths,
        public Remote $production,
        public ?Remote $staging = null,
        public ?Git $git = null,
        public ?Composer $composer = null,
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
        ];

        if ($this->staging) {
            $vars = [...$vars, ...$this->remoteVars('STAG_', $this->staging)];
        }

        if ($this->paths->additional) {
            $vars['ADDITIONAL_DIRS'] = implode(' ', $this->paths->additional);
        }

        if ($this->git) {
            $vars['GIT_DIR'] = $this->git->dir;
            $vars['PRODUCTION_BRANCH'] = $this->git->productionBranch;
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
 * Validate the git branch before deploying to production
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
