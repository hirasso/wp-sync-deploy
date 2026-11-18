<?php

/**
 * Print the URLs the smoke test requests: the home URL of every site and
 * the latest published post of each public post type (main site only).
 * Usage: `wp eval-file - < lib/smoke-urls.php`
 */

$sites = is_multisite() ? get_sites(['fields' => 'ids', 'number' => 0]) : [get_current_blog_id()];
foreach ($sites as $id) {
    is_multisite() && switch_to_blog($id);
    echo home_url('/') . PHP_EOL;
    is_multisite() && restore_current_blog();
}

foreach (get_post_types(['public' => true]) as $type) {
    if ($type === 'attachment') {
        continue;
    }
    $posts = get_posts([
        'post_type' => $type,
        'post_status' => 'publish',
        'numberposts' => 1,
        'fields' => 'ids',
        'suppress_filters' => true,
    ]);
    if ($posts) {
        echo get_permalink($posts[0]) . PHP_EOL;
    }
}
