FROM nginx:1.27-alpine

COPY html/ /usr/share/nginx/html/

RUN echo 'server { \
    listen 80; \
    server_name _; \
    root /usr/share/nginx/html; \
    \
    location /api/health { \
        access_log off; \
        return 503 "{\"status\":\"maintenance\"}"; \
        add_header Content-Type application/json; \
    } \
    \
    location / { \
        try_files /maintenance.html =503; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
