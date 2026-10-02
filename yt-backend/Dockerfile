FROM php:8.2-apache

# Install dependencies, ffmpeg, python3, nodejs (needed for yt-dlp JS player decryption)
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    ffmpeg \
    curl \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install yt-dlp binary
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

# Enable Apache mod_rewrite & allow .htaccess
RUN a2enmod rewrite \
    && sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf


# Copy backend files
COPY . /var/www/html/

# Create downloads folder with write permissions
RUN mkdir -p /var/www/html/downloads && chmod 777 /var/www/html/downloads

# Create startup script to bind Apache to dynamic $PORT provided by Render and update yt-dlp
RUN echo '#!/bin/sh' > /start.sh \
    && echo 'PORT="${PORT:-80}"' >> /start.sh \
    && echo 'sed -i "s/Listen 80/Listen $PORT/g" /etc/apache2/ports.conf' >> /start.sh \
    && echo 'sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PORT>/g" /etc/apache2/sites-available/000-default.conf' >> /start.sh \
    && echo '# Always update yt-dlp to latest on startup' >> /start.sh \
    && echo 'curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && chmod a+rx /usr/local/bin/yt-dlp || true' >> /start.sh \
    && echo 'exec apache2-foreground' >> /start.sh \
    && chmod +x /start.sh

EXPOSE 80
CMD ["/start.sh"]
