FROM devasdf/phpswoole:8.4-node

WORKDIR /app

COPY . .


RUN composer install

RUN npm ci && npm run build

RUN rm -rf node_modules

CMD ["php", "artisan", "octane:start", "--host=0.0.0.0", "--port=9000", "--workers=1", "--server=swoole", "--max-requests=100"]
