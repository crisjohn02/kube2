FROM phpswoole/swoole:5.1.5-php8.3

ARG NODE_VERSION=22


RUN apt-get update && apt-get install -y ca-certificates curl gnupg libicu-dev libzip-dev libfreetype-dev libjpeg62-turbo-dev libpng-dev  \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY php.ini "/usr/local/etc/php/php.ini"

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd intl zip gettext bcmath pcntl exif