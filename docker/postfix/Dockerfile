FROM alpine:3.20

LABEL org.opencontainers.image.title="Dexta Africa Postfix Mail Relay" \
      org.opencontainers.image.description="Hardened Postfix SMTP relay service authenticating through Brevo (Sendinblue)"

RUN apk add --no-cache \
    postfix \
    cyrus-sasl \
    cyrus-sasl-login \
    ca-certificates \
    bash \
    tzdata

RUN mkdir -p /var/spool/postfix /var/log /etc/postfix

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 587 25

HEALTHCHECK --interval=20s --timeout=5s --start-period=10s --retries=3 \
  CMD postfix status || exit 1

ENTRYPOINT ["/entrypoint.sh"]
