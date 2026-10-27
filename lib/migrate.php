<?php

/**
 * Config generation and migrations for `wp-sync-deploy config init|migrate`
 *
 * Usage:
 * - `php lib/migrate.php config <config-file> [<.deployignore>]`: print a config file
 *   built from the 3.x variables in the environment (the sourced .env.wp-sync-deploy,
 *   or the answers from `config init`)
 * - `php lib/migrate.php tasks <tasks-file>`: use the run() helper in a tasks file
 */

require_once dirname(__DIR__) . '/src/Config.php';

use Hirasso\WPSyncDeploy\Ignore;

/** Read a variable from the sourced .env.wp-sync-deploy */
function env(string $name): string
{
    return trim((string) getenv($name));
}

/** Export a value as PHP code */
function export(string $value): string
{
    return var_export($value, true);
}

/** Express an absolute path relative to the config file's directory */
function relativeToConfig(string $path, string $configDir): string
{
    $path = rtrim($path, '/');
    $configDir = rtrim($configDir, '/');

    if ($path === $configDir) {
        return '__DIR__';
    }
    if (str_starts_with("$path/", "$configDir/")) {
        return "__DIR__ . " . export(substr($path, strlen($configDir)));
    }
    if (str_starts_with("$configDir/", "$path/")) {
        $levels = substr_count(substr($configDir, strlen($path)), '/');
        return "dirname(__DIR__, $levels)";
    }
    return export($path);
}

/** Render named arguments, one per line */
function args(array $args, string $indent): string
{
    $lines = [];
    foreach ($args as $name => $value) {
        $lines[] = "$indent$name: $value,";
    }
    return implode("\n", $lines);
}

/** Render a constructor call with named arguments */
function instance(string $class, array $args): string
{
    return $args ? "new $class(\n" . args($args, '        ') . "\n    )" : "new $class()";
}

/** Render a remote from the variables with the given prefix */
function remote(string $prefix, array &$uses, array &$notes): string
{
    $args = [
        'url' => export(env("{$prefix}PROTOCOL") . '://' . env("{$prefix}HOST")),
        'ssh' => export(env("{$prefix}SSH")),
        'rootDir' => export(rtrim(env("{$prefix}ROOT_DIR"), '/')),
    ];
    if (env("{$prefix}SSH_PORT") !== '' && env("{$prefix}SSH_PORT") !== '22') {
        $args['sshPort'] = (int) env("{$prefix}SSH_PORT");
    }
    if (env("{$prefix}PHP_BINARY") !== '' && env("{$prefix}PHP_BINARY") !== 'php') {
        $args['phpBinary'] = export(env("{$prefix}PHP_BINARY"));
    }
    if (env("{$prefix}DEPLOY_STRATEGY") === 'risky') {
        $args['deployStrategy'] = 'DeployStrategy::Risky';
        $uses[] = 'DeployStrategy';
    }
    if (env("{$prefix}HTTP_AUTH") !== '') {
        $args['httpAuth'] = "getenv('{$prefix}HTTP_AUTH') ?: null";
        $notes[] = "Set the environment variable {$prefix}HTTP_AUTH, the credentials aren't written to the config file";
    }
    return instance('Remote', $args);
}

/** Read the custom rules from a 3.x .deployignore file */
function deployignorePatterns(string $file): array
{
    if (!is_file($file)) {
        return [];
    }
    $patterns = [];
    foreach (file($file, FILE_IGNORE_NEW_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#')) {
            continue;
        }
        $pattern = preg_replace('/^-p? /', '', $line);
        if (!in_array($pattern, Ignore::DEFAULTS, true)) {
            $patterns[] = $pattern;
        }
    }
    return $patterns;
}

/** Print a config file built from the 3.x variables */
function migrateConfig(string $configFile, string $deployignore): void
{
    $configDir = dirname($configFile);
    $uses = ['Config', 'Local', 'Paths', 'Remote'];
    $notes = [];

    $local = [
        'url' => export(env('LOCAL_PROTOCOL') . '://' . env('LOCAL_HOST')),
        'rootDir' => relativeToConfig(env('LOCAL_ROOT_DIR'), $configDir),
    ];
    if (env('LOCAL_HTTP_AUTH') !== '') {
        $local['httpAuth'] = "getenv('LOCAL_HTTP_AUTH') ?: null";
        $notes[] = "Set the environment variable LOCAL_HTTP_AUTH, the credentials aren't written to the config file";
    }

    $additional = array_filter(preg_split('/\s+/', env('ADDITIONAL_DIRS')));
    $hasVendor = in_array('vendor', $additional, true);
    $additional = array_values(array_diff($additional, ['vendor']));

    $paths = [
        'wpContent' => export(env('WP_CONTENT_DIR')),
        'wpCore' => export(env('WP_CORE_DIR')),
    ];
    if (env('PUBLIC_DIR') !== '') {
        $paths['public'] = export(env('PUBLIC_DIR'));
    }
    if ($additional) {
        $paths['additional'] = '[' . implode(', ', array_map('export', $additional)) . ']';
    }

    $config = [
        'local' => instance('Local', $local),
        'paths' => instance('Paths', $paths),
    ];

    if (env('PROD_HOST') !== '') {
        $config['production'] = remote('PROD_', $uses, $notes);
    }

    if (env('STAG_HOST') !== '') {
        $config['staging'] = remote('STAG_', $uses, $notes);
    }

    $branch = env('PRODUCTION_BRANCH') ?: env('GIT_PRODUCTION_BRANCH');
    $git = [];
    if (env('GIT_DIR') !== '') {
        $git['dir'] = export(env('GIT_DIR'));
    }
    if ($branch !== '' && $branch !== 'master|main') {
        $git['productionBranch'] = export($branch);
    }
    // A repo at the root is detected without config
    if (getenv('GIT_DISABLED')) {
        $config['git'] = 'false';
    } elseif ($git) {
        $config['git'] = instance('Git', $git);
        $uses[] = 'Git';
    }

    if ($hasVendor) {
        $config['composer'] = 'new Composer()';
        $uses[] = 'Composer';
        $notes[] = 'vendor is now built and deployed without dev dependencies (composer: new Composer())';
    } elseif (getenv('COMPOSER_DIR') !== false) {
        $config['composer'] = instance('Composer', env('COMPOSER_DIR') !== '' ? ['dir' => export(env('COMPOSER_DIR'))] : []);
        $uses[] = 'Composer';
    }

    $patterns = deployignorePatterns($deployignore);
    if ($patterns) {
        $config['ignore'] = "new Ignore(patterns: [\n" . implode("\n", array_map(fn ($p) => '        ' . export($p) . ',', $patterns)) . "\n    ])";
        $uses[] = 'Ignore';
    }

    sort($uses);
    $body = args($config, "    ");
    $imports = implode("\n", array_map(fn ($use) => "use Hirasso\\WPSyncDeploy\\$use;", $uses));

    echo <<<PHP
    <?php

    /**
     * Configuration for wp-sync-deploy
     *
     * Commit this file. For secrets like http auth credentials, use environment variables.
     *
     * @see https://github.com/hirasso/wp-sync-deploy#configuration
     */

    $imports

    return new Config(
    {$body}
    );

    PHP;

    foreach ($notes as $note) {
        fwrite(STDERR, "$note\n");
    }
}

/** Use the run() helper for simple \WP_CLI::runcommand() calls in a tasks file */
function migrateTasks(string $file): void
{
    $code = file_get_contents($file);
    $migrated = preg_replace("/\\\\WP_CLI::runcommand\\(('[^']*')\\);/", 'run($1);', $code, -1, $count);

    if (!$count) {
        return;
    }

    if (!str_contains($migrated, 'function run(')) {
        $helper = <<<'PHP'

        /**
         * Run a WP-CLI command in this process. Inherits the PHP settings of wp-sync-deploy
         * (e.g. hidden deprecation notices) and is faster than launching a new process
         */
        function run(string $command)
        {
            \WP_CLI::runcommand($command, ['launch' => false]);
        }
        PHP;
        // Top level, right after the namespace or the opening tag
        $anchor = preg_match('/^namespace [^;]+;$/m', $migrated) ? '/^namespace [^;]+;$/m' : '/^<\?php$/m';
        $migrated = preg_replace($anchor, "$0\n" . $helper, $migrated, 1);
    }

    file_put_contents($file, $migrated);
    echo $count;
}

match ($argv[1] ?? '') {
    'config' => migrateConfig($argv[2], $argv[3] ?? ''),
    'tasks' => migrateTasks($argv[2]),
};
