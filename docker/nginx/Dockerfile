FROM nginx:1.27-alpine

LABEL org.opencontainers.image.title="Dexta Africa Edge Reverse Proxy" \
      org.opencontainers.image.description="Hardened production Nginx reverse proxy with dynamic SSL and maintenance mode support"

# Install curl and openssl for healthcheck probes and certificate generation
RUN apk add --no-cache curl openssl bash

# Create necessary directories
RUN mkdir -p /etc/nginx/templates \
             /etc/nginx/ssl \
             /etc/nginx/maintenance \
             /usr/share/nginx/html \
             /var/www/certbot \
             /var/log/nginx

# Copy global configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy dynamic templates
COPY templates/ /etc/nginx/templates/

# Copy branded error and maintenance pages
COPY html/ /usr/share/nginx/html/

EXPOSE 80 443

HEALTHCHECK --interval=20s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://127.0.0.1/healthz || exit 1

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]
