# syntax=docker/dockerfile:1
FROM composer:2.10
RUN apk add --no-cache icu-dev \
 && docker-php-ext-install -j$(nproc) intl \
 && docker-php-ext-enable intl
