FROM dunglas/frankenphp

ARG NODE_VERSION=22

RUN apt-get update && apt-get install -y ca-certificates curl gnupg supervisor \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
	&& curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
	&& mkdir -p /var/log/supervisor

COPY php.ini "$PHP_INI_DIR/php.ini"

RUN install-php-extensions \
	pdo_mysql \
	gd \
	intl \
	zip \
	gettext \
    bcmath \
	pcntl \
	exif \
	redis

RUN mkdir -p /etc/supervisor

COPY supervisor /etc/supervisor

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]