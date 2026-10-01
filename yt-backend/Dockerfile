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

# Enable Apache mod_rewrite
RUN a2enmod rewrite

# Update Apache port to support Render/Koyeb dynamic PORT environment variable (default 80)
RUN sed -i 's/80/${PORT:-80}/g' /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf

# Copy backend files
COPY . /var/www/html/

# Create downloads folder with write permissions
RUN mkdir -p /var/www/html/downloads && chmod 777 /var/www/html/downloads

EXPOSE 80
CMD ["apache2-foreground"]
