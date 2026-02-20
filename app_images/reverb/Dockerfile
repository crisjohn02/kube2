FROM devasdf/phpswoole:8.4

WORKDIR /app

COPY . .

RUN composer install


CMD ["php", "artisan", "reverb:start", "--host=0.0.0.0", "--port=8080" , "--debug"]
