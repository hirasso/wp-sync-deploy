#!/usr/bin/env bash
set -e

echo "127.0.0.1 local.test staging.test prod.test" >>/etc/hosts

service mariadb start
mariadb -e "CREATE USER IF NOT EXISTS 'wp'@'%' IDENTIFIED BY 'wp'; GRANT ALL ON *.* TO 'wp'@'%'; FLUSH PRIVILEGES;"
printf '[client]\nuser=wp\npassword=wp\nhost=127.0.0.1\n' | tee /home/dev/.my.cnf /home/deploy/.my.cnf >/dev/null
chown dev: /home/dev/.my.cnf && chown deploy: /home/deploy/.my.cnf

service "$(basename /etc/init.d/php*-fpm)" start
service nginx start
service ssh start

# Fresh, so wp-sync-deploy doesn't download it again (see cacheWpCli)
install -D -o dev -g dev /usr/local/bin/wp /home/dev/.cache/wp-sync-deploy/wp-cli.phar

touch /tmp/ready
exec sleep infinity
