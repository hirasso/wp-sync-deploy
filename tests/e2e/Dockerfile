# One container plays all three environments: local.test, staging.test and prod.test,
# with SSH from user `dev` (local) to user `deploy` (remotes) on localhost
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bats ca-certificates curl git less mariadb-client mariadb-server nginx openssh-client openssh-server \
    php-cli php-curl php-fpm php-mbstring php-mysql php-xml php-zip procps rsync sudo \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i "s|^listen = .*|listen = /run/php/php-fpm.sock|" /etc/php/*/fpm/pool.d/www.conf

RUN curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp \
    && wp core download --allow-root --skip-content --path=/opt/wp-core

RUN useradd -m -s /bin/bash dev && useradd -m -s /bin/bash deploy \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev \
    && su dev -c "ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_ed25519" \
    && printf 'Host localhost\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  LogLevel ERROR\n' >/home/dev/.ssh/config \
    && install -d -m 700 -o deploy -g deploy /home/deploy/.ssh \
    && install -m 600 -o deploy -g deploy /home/dev/.ssh/id_ed25519.pub /home/deploy/.ssh/authorized_keys \
    && git config --system user.email e2e@example.com && git config --system user.name e2e \
    && git config --system init.defaultBranch main

COPY docker/nginx.conf /etc/nginx/sites-enabled/default
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
