FROM nginx:alpine-slim

LABEL org.opencontainers.image.title="Dexta Africa Maintenance Gateway" \
      org.opencontainers.image.description="Lightweight HTTP 503 maintenance container for zero-downtime controlled deployments"

RUN rm -rf /etc/nginx/conf.d/* /usr/share/nginx/html/*

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
