#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Postfix Mail Relay Entrypoint (Brevo / Sendinblue Integration)
# ==============================================================================
set -euo pipefail

BREVO_HOST="${BREVO_SMTP_HOST:-smtp-relay.brevo.com}"
BREVO_PORT="${BREVO_SMTP_PORT:-587}"
BREVO_USER="${BREVO_SMTP_USER:-}"
BREVO_KEY="${BREVO_SMTP_KEY:-}"
MAIL_DOMAIN="${MAIL_DOMAIN:-dextaafrica.com}"

echo "==> Configuring Dexta Africa Postfix Mail Relay..."

if [ -z "$BREVO_USER" ] || [ -z "$BREVO_KEY" ]; then
    echo "[WARNING] BREVO_SMTP_USER or BREVO_SMTP_KEY is not configured!"
    echo "          Emails will be accepted locally but outbound delivery will pause in queue."
fi

# Configure SASL Password Mapping for Brevo
cat <<EOF > /etc/postfix/sasl_passwd
[${BREVO_HOST}]:${BREVO_PORT} ${BREVO_USER}:${BREVO_KEY}
EOF

chmod 600 /etc/postfix/sasl_passwd
postmap lmdb:/etc/postfix/sasl_passwd
rm -f /etc/postfix/sasl_passwd # remove cleartext file after hashing

# Configure Postfix parameters in main.cf
postconf -e "maillog_file = /dev/stdout"
postconf -e "myhostname = mail.${MAIL_DOMAIN}"
postconf -e "mydomain = ${MAIL_DOMAIN}"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mydestination = localhost.\$mydomain, localhost"

# Relay through Brevo SMTP
postconf -e "relayhost = [${BREVO_HOST}]:${BREVO_PORT}"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = lmdb:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_sasl_tls_security_options = noanonymous"
postconf -e "smtp_sasl_mechanism_filter = plain, login"

# Enforce TLS encryption for all outbound mail
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
postconf -e "smtp_tls_note_starttls_offer = yes"

# Trust internal Docker network subnets
postconf -e "mynetworks = 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, ${POSTFIX_ALLOWED_NETWORKS:-}"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination"

# Size limits and queue durability (20MB max message size)
postconf -e "message_size_limit = 20971520"
postconf -e "mailbox_size_limit = 0"
postconf -e "smtpd_banner = \$myhostname ESMTP Dexta Africa Postfix Gateway"

# Ensure submission port 587 is active in master.cf
if ! grep -q "^submission" /etc/postfix/master.cf; then
    cat <<EOF >> /etc/postfix/master.cf
submission inet n       -       n       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=may
  -o smtpd_sasl_auth_enable=no
  -o smtpd_recipient_restrictions=permit_mynetworks,reject
EOF
fi

# Fix permissions on spool directory
chown -R postfix:postfix /var/spool/postfix

echo "==> Postfix Mail Gateway initialized successfully. Relaying via ${BREVO_HOST}:${BREVO_PORT}..."
exec postfix start-fg
