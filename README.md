# Highlight 6 - Docker Compose deployment

Runs the full Highlight 6 stack (postgres, keycloak, cvedb, highlightportal) with Docker Compose.

## Layout

```
docker-deployment/
├── docker-compose.yml
├── .env.sample                        # copy to .env and fill in secrets
├── nginx/
│   ├── default.conf.template          # TLS gateway config - "/" -> highlightportal, "/auth" -> keycloak
│   ├── generate-self-signed-cert.sh   # one-time cert setup - see "TLS / nginx gateway" below
│   └── certs/                         # fullchain.pem + privkey.pem land here, generated or your own (gitignored)
├── postgres/
│   ├── postgresql.conf.sample
│   └── init-db.sh           # creates the highlight and keycloak databases/schemas
├── cvedb/
│   └── cvedb.properties     # contains DB/SMTP passwords and the NIST API key - update before deploying
└── portal/
    ├── properties.hl-docker            # contains the admin password and Highlight license keys - update before deploying
    └── entrypoint-with-truststore.sh   # wraps the image's entrypoint to trust nginx's cert - see "TLS / nginx gateway"
```

## TLS / nginx gateway

The stack is fronted by a single `nginx` service that terminates TLS and is the only externally
published entrypoint (ports 80/443) - it routes `/` to `highlightportal` and `/auth` to
`keycloak`, mirroring `hl-helmchart`'s `templates/ingress.yaml`. `keycloak`, `highlightportal`,
`cvedb` and `postgres` no longer publish their own host ports; `cvedb` and `postgres` are never
proxied either, matching the helm chart keeping them ClusterIP-only - they're reachable only from
other containers over the internal docker network.

Before the first `docker compose up -d`, `nginx/certs/` needs a cert for `PUBLIC_HOST` - either
generate a self-signed one, or bring your own.

**Option A - self-signed (default, fine for internal/lab use):**

```bash
cd nginx
./generate-self-signed-cert.sh
```

Do this again if `PUBLIC_HOST` ever changes. Browsers will show a trust warning for this cert -
that's expected.

**Option B - use an existing/real certificate (no browser warning):**

Skip the script and instead place your own cert/key at:

- `nginx/certs/fullchain.pem` - the leaf certificate for `PUBLIC_HOST`, followed by any
  intermediate certificates your CA gave you, concatenated in that order, all in PEM format. Do
  **not** include the private key in this file.
- `nginx/certs/privkey.pem` - the matching private key, PEM format, unencrypted (no passphrase -
  nginx won't prompt for one).

Both file names must match exactly - `nginx/default.conf.template`'s `ssl_certificate`/
`ssl_certificate_key` directives point at these two paths. This works for a cert from a public
CA (Let's Encrypt, DigiCert, etc.) or an internal/corporate CA - either way, no other config
changes are needed as long as the cert covers `PUBLIC_HOST` (as a CN or a SAN entry) and hasn't
expired.

---

`HL_KEYCLOAK_ADMIN_URL` in `portal/properties.hl-docker` is used by highlightportal for backend
admin-API calls to Keycloak, not just browser links - now that it's `https://`, those calls need
to trust whatever cert nginx presents. The `highlightportal` service's entrypoint is wrapped by
`portal/entrypoint-with-truststore.sh`, which imports `nginx/certs/fullchain.pem` into the JVM's
trust store before launching, so this works automatically regardless of which option above you
used - no properties file changes needed. (`HL_KEYCLOAK_DISABLE_SSL_VALIDATION` is *not* a
substitute for this - confirmed it doesn't cover every HTTPS call the portal makes to Keycloak;
keep it `false`.) If you replace the cert (self-signed or real), `docker compose up -d
--force-recreate highlightportal nginx` to pick up the new one.

> **Secrets/license notice:** `.env`, `cvedb/cvedb.properties` and `portal/properties.hl-docker` all
> contain sensitive values (passwords, API keys, license information). Treat them as secrets, keep
> real copies out of source control, and make sure each one is filled in with real values *before*
> the first deployment - see "Setup" below.

## Prerequisites

- Docker Engine + Docker Compose v2 (`docker compose`, not the legacy standalone `docker-compose`)
- Pull access to `jartero/hlkeycloak:1.0.6`, `jartero/cvedb:6.0.1` and
  `jartero/highlightportal:6.0.1`

## Setup

1. Copy the env template and fill in real secrets:
   ```bash
   cp .env.sample .env
   ```
   Edit `.env`: set `PUBLIC_HOST` to your reachable hostname/IP (or leave `localhost` if you're
   browsing from the same machine), and replace every `CHANGEME-*` value
   (`KC_BOOTSTRAP_ADMIN_PASSWORD`, `KC_PERMANENT_ADMIN_PASSWORD`, `KC_HL_CLIENT_SECRET`,
   `KC_HL_ADMIN_SECRET`, `KC_HL_WEBHOOK_SECRET`, `SMTP_PASSWORD`). The SMTP settings
   (`SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`, `SMTP_FROM_DISPLAY_NAME`, `SMTP_USER`).

   **If the real `SMTP_PASSWORD` contains special characters, it needs escaping twice over** (see
   `.env.sample` for the full explanation):
   - a literal `$` must be written as `$$` - docker compose interpolates `$VAR`/`${VAR}` inside
     `.env` values too, and silently blanks out anything that looks like an unset variable
     reference (e.g. `$e9` -> empty, with a "variable is not set" warning, no hard failure).
   - a literal `\` must be written as `\\` - this is Keycloak's `SMTP_PASSWORD` only, and works
     around a confirmed bug in `hlkeycloak`'s `entrypoint.sh` (1.0.3, still present in 1.0.6), which injects the password
     into a JSON realm-import template via `envsubst` with no JSON-escaping. An unescaped `\`
     produces invalid JSON and crashes Keycloak on startup (`Unrecognized character escape`).

2. **Update the other two files that also carry secrets/license data before first deploying -
   they are not driven by `.env` and must be edited by hand:**

   - `cvedb/cvedb.properties` - replace `datasource.password` (Postgres password for the `cvedb`
     schema), `spring.mail.password` (SMTP password for CVE mail notifications) and `nist.apiKey`
     (NIST NVD API key used to pull CVE data) with real values.
   - `portal/properties.hl-docker` - replace `HL_ADMIN_PWD` with a strong password (must satisfy
     the Keycloak realm's password policy: 1 digit, 14+ chars, 1 uppercase, 1 lowercase, 1 special
     character), `HL_SCA_SAM_SECRET`, and fill in the `HL_LICENCE_0` .. `HL_LICENCE_11` values from
     your Highlight license file.

3. **If this stack needs to be reachable remotely (not just from `localhost` on the same
   machine), you must update the hostname/IP in every one of these places - they don't share a
   single source of truth, and Keycloak will reject logins with `Invalid parameter: redirect_uri`
   if any one of them disagrees with the others:**

   - `.env` - set `PUBLIC_HOST` to the real hostname/IP other machines will use to reach this host
     (e.g. `PUBLIC_HOST=kubtest1`). This drives Keycloak's `KC_HOSTNAME`/`APP_BASE_URL` (which in
     turn control what redirect URI gets registered on the `highlight-portal` Keycloak client)
     and the nginx gateway's `server_name`.
   - `portal/properties.hl-docker` - replace every `https://localhost/...` with the *same*
     hostname you put in `PUBLIC_HOST` (both are browser-facing, so both go through the nginx
     gateway on 443 - no port suffix):
     - `HL_ROOT_URL=https://<PUBLIC_HOST>/`
     - `HL_KEYCLOAK_ADMIN_URL=https://<PUBLIC_HOST>/auth`

     Leave `HL_CVE_API_URL`/`HL_CVE_LOCAL_URL` as `http://cvedb:8082` - that's an internal
     docker-network address, not browser-facing, and doesn't change with `PUBLIC_HOST`.

     This file is a static bind-mount, not `.env`-driven, so it has to be edited by hand and kept
     in sync manually - see the comment at the top of its "Hostname" section.
   - Regenerate the TLS cert for the new hostname - see "TLS / nginx gateway" above.

   Do this **before** the first `docker compose up -d`.

4. Start everything:
   ```bash
   docker compose up -d
   ```

5. Watch Keycloak come up (first boot takes ~30-60s - realm import + admin bootstrap):
   ```bash
   docker compose logs -f keycloak
   ```

6. Browse to `https://<PUBLIC_HOST>` (accept the self-signed cert warning if you used
   `generate-self-signed-cert.sh`).

## Ports

| Service | Published port | Container port |
|---|---|---|
| nginx (TLS gateway) | 80, 443 | 80, 443 |
| postgres | 2280 | 5432 |

`highlightportal`, `keycloak` and `cvedb` no longer publish host ports - see "TLS / nginx
gateway" above.

## Notes

- See the secrets/license notice under "Layout" - `.env`, `cvedb/cvedb.properties` and
  `portal/properties.hl-docker` all need real values filled in before deploying.
- To fully reset everything including data: `docker compose down -v` (the `-v` removes the named
  volumes - omit it to keep your data across restarts).
- Keycloak's `keycloak-data` volume persists its one-time "already initialized" sentinel
  (`/opt/keycloak/data/init/.initialized`) across `docker compose down`/`up` cycles. Without it,
  every container recreation would re-run first-run init against an already-bootstrapped database and
  fail forever.