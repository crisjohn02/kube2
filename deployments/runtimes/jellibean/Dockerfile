FROM dunglas/frankenphp

RUN apt-get update && apt-get install -y ca-certificates curl \
	&& curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

COPY php.ini "$PHP_INI_DIR/php.ini"

RUN install-php-extensions \
	pdo_mysql \
	gd \
	intl \
	zip \
	gettext \
    bcmath \
	pcntl \
	exif