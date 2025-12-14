# Nginx + Certbot deployment

## Layout
- `infra/docker-compose.yml`: stack definition (kafka, telemetry, vehicle proxy, nginx, certbot).
- `infra/nginx/`: nginx config (TLS passthrough for fleet telemetry, termination for vehicle proxy, ACME webroot on :80).
- `infra/certbot/`: deploy hook to reload/restart services after renewals.
- `infra/telemetry/config.json.example`: sample config pointing TLS to `/etc/letsencrypt/live/fleet-telemetry.ticketskipper.com`.
- `infra/vehicle-proxy/`: place `fleet-key.pem` used by tesla-http-proxy.
- Volumes:
  - `letsencrypt` -> `/etc/letsencrypt` (shared by nginx, certbot, telemetry, vehicle proxy).
  - `certbot-www` -> `/var/www/certbot` (ACME HTTP-01 webroot).

## Prereqs
- DNS A/AAAA records for:
  - `fleet-telemetry.ticketskipper.com`
  - `vehicle-proxy.ticketskipper.com`
- Populate `infra/telemetry/config.json` (copy from `.example`) and keep TLS paths pointing at `/etc/letsencrypt/live/fleet-telemetry.ticketskipper.com/{fullchain.pem,privkey.pem}`.
- Place the vehicle proxy key at `infra/vehicle-proxy/fleet-key.pem` (matching the registered public key).
- Create `infra/kafka-to-supabase/.env` with:
  - `SUPABASE_URL`
  - `SUPABASE_TABLE`
  - `SUPABASE_SERVICE_ROLE_KEY`
- Export an email for ACME: `export CERTBOT_EMAIL=<you@example.com>`.

## Bootstrap
```bash
cd infra
# First issue certificates (HTTP-01 via nginx webroot)
docker compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d fleet-telemetry.ticketskipper.com \
  -d vehicle-proxy.ticketskipper.com \
  --agree-tos --email "${CERTBOT_EMAIL}"

# Bring up the stack
docker compose up -d
```

## Renewal flow
- The `certbot` service runs `certbot renew` every 12h with deploy hook `certbot/hooks/reload-nginx.sh`.
- Hook signals `nginx` (HUP) and restarts `telemetry` + `tesla_http_proxy` so renewed certs are loaded.
- `nginx` also watches `/etc/letsencrypt/live/*` with `inotifywait` and reloads on change.

## Routing behavior
- Port 443 (stream) uses SNI:
  - `fleet-telemetry.ticketskipper.com` → passthrough TLS to `telemetry:443` (mTLS preserved).
  - `vehicle-proxy.ticketskipper.com` → forwarded to internal nginx `:8443` where TLS terminates then proxied to `tesla_http_proxy:4443`.
- Port 80 serves ACME challenges for both domains and redirects other requests to HTTPS.

## Verification
- Vehicle proxy: `curl -I https://vehicle-proxy.ticketskipper.com`.
- Telemetry passthrough: `openssl s_client -connect fleet-telemetry.ticketskipper.com:443 -servername fleet-telemetry.ticketskipper.com`.
- Cert freshness: `docker compose logs certbot` and check renewed notBefore/notAfter with `openssl x509 -in /etc/letsencrypt/live/vehicle-proxy.ticketskipper.com/fullchain.pem -noout -dates` (inside nginx container).

## Notes
- Certbot requires access to `/var/run/docker.sock` to signal/restart containers after renewal.
- If you change the project name, update `COMPOSE_PROJECT_NAME` or adjust `reload-nginx.sh` container names.
- Ensure firewalls expose 80/443 to the internet for ACME.

