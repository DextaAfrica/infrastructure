# Mailcow Dockerized & Brevo Smart Relay Setup Guide

This guide explains how to install and manage **Mailcow Dockerized** on your Contabo production VPS (`207.180.253.39`), integrate it seamlessly with your existing `shared_traefik` proxy, configure DNS records on Cloudflare, and set up Brevo as a smart relay fallback for email marketing and transactional deliveries.

---

## 1. Automated Installation on Production Server

Run the automated installer on your server (`server@cloud-engine`):

```bash
# 1. From your infrastructure directory
cd ~/apps/dextaafrica
git pull origin develop

# 2. Run the Mailcow setup script
./scripts/setup-mailcow.sh

# 3. Pull Mailcow images and start services
cd ~/apps/mailcow
docker compose pull
docker compose up -d
```

> [!NOTE]
> The setup script automatically configures:
> - `HTTP_PORT=8080` and `HTTPS_PORT=8443` bound locally to `127.0.0.1` so there are **zero port 80/443 collisions** with `shared_traefik`.
> - Joins Mailcow's `nginx-mailcow` to the `traefik-public` Docker network with Traefik routing labels.
> - Automatically detects system RAM; if RAM is under 7GB, it disables ClamAV (`SKIP_CLAMD=y`) to maintain a lean memory footprint.

---

## 2. Accessing the Webmail & Admin UI

Once containers are started:
1. Navigate to: **`https://mail.dextaafrica.com`**
2. **Default Credentials**:
   - Username: `admin`
   - Password: `moohoo`
3. **IMMEDIATE ACTION**: Click on the user profile icon (top right) and change the default admin password.

---

## 3. Reverse DNS (rDNS / PTR) in Contabo Panel

Major mail providers (Google, Yahoo, Outlook) verify that the sending IP's reverse DNS matches the HELO hostname:

1. Log in to the [Contabo Customer Control Panel](https://my.contabo.com).
2. Go to **VPS Control** -> Select your VPS (`207.180.253.39`) -> **Reverse DNS Management**.
3. Set the PTR record for `207.180.253.39` to:
   ```
   mail.dextaafrica.com
   ```
4. Save changes.

---

## 4. Mailcow Domain & DKIM Setup

### Step A: Add Domain
1. In Mailcow UI, go to **Configuration -> Mail Setup -> Domains** -> click **Add domain**.
2. Domain: `dextaafrica.com`
3. Description: `Dexta Africa Enterprise Domain`
4. Click **Add domain and restart SOGo**.

### Step B: Generate DKIM Key
1. In Mailcow UI, go to **Configuration -> Routing -> DKIM**.
2. Under **Add DKIM Key**:
   - Domain: `dextaafrica.com`
   - Key size: `2048`
   - Selector: `mailcow`
3. Click **Add**.
4. Mailcow will generate a public key (starting with `v=DKIM1; k=rsa; p=...`).

### Step C: Add DKIM Record to Cloudflare
In your Cloudflare DNS table, add this new TXT record:
* **Type**: `TXT`
* **Name**: `mailcow._domainkey`
* **Content**: `<Paste the full public key from Mailcow>`
* **TTL**: `Auto` / `DNS only`

---

## 5. Configure Brevo as a Smart Relay Fallback in Mailcow

Mailcow includes a powerful feature called **Sender-Dependent Transport**, allowing you to route outbound emails through Brevo (e.g. for marketing or if Contabo blocks port 25):

1. In Mailcow UI, navigate to: **Configuration -> Routing -> Standard / Sender-Dependent Transport**.
2. Click **Add transport**:
   - **Host**: `smtp-relay.brevo.com`
   - **Port**: `587`
   - **Username**: `${BREVO_SMTP_USER}` (from your Brevo account)
   - **Password**: `${BREVO_SMTP_KEY}` (from your Brevo account)
3. Under **Sender-dependent transports**:
   - You can map specific addresses (e.g. `marketing@dextaafrica.com` or `@dextaafrica.com`) to use this Brevo relay.
   - When configured, Mailcow sends messages via Brevo over TLS on port 587, guaranteeing 99%+ deliverability while keeping all sent logs, tracking, and inboxes inside your self-hosted SOGo webmail!

---

## 6. Port 25 Outbound Note (Contabo)

If you wish to send emails directly from the VPS without routing through Brevo:
Contabo restricts outbound port 25 by default. Simply open a quick ticket to Contabo Support:
```text
Subject: Request to unblock outbound port 25 for mail.dextaafrica.com

Hello Support Team,
We have configured a self-hosted mail server (Mailcow) on our VPS (IP: 207.180.253.39) for our company domain dextaafrica.com.
We have valid SPF, DKIM, and DMARC records configured.
Could you please unblock outbound TCP port 25 on this instance?
Thank you.
```
*(While waiting for Contabo, the Brevo relay configured in Section 5 works immediately without needing port 25).*
