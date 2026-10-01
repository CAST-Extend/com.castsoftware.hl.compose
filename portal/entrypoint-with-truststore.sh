#!/bin/bash
# Wraps the highlightportal image's own ENTRYPOINT (/bin/bash /run.sh) to make the JVM trust
# the nginx gateway's cert (mounted read-only at /certs/fullchain.pem - see docker-compose.yml).
#
# HL_KEYCLOAK_DISABLE_SSL_VALIDATION is not enough on its own: confirmed that the Keycloak
# admin-client's token-grant call (KeycloakAdminServiceImpl -> TokenManager.grantToken, used
# e.g. by createUser) still performs full PKIX validation regardless of that flag, so HTTPS
# calls to HL_KEYCLOAK_ADMIN_URL fail with "unable to find valid certification path" even with
# it set to true. Actually trusting the cert fixes that call (and any other outbound HTTPS this
# container makes to the gateway) properly instead of disabling validation.
#
# $JAVA_HOME/lib/security/cacerts isn't writable by the image's non-root user (uid 5000), so we
# copy it to a scratch location first rather than modifying it in place.
set -euo pipefail

JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
TRUSTSTORE=/tmp/truststore.jks

cp "${JAVA_HOME}/lib/security/cacerts" "${TRUSTSTORE}"

if [ -f /certs/fullchain.pem ]; then
  keytool -importcert -noprompt -trustcacerts \
    -alias nginx-gateway \
    -file /certs/fullchain.pem \
    -keystore "${TRUSTSTORE}" \
    -storepass changeit
else
  echo "WARNING: /certs/fullchain.pem not found - HTTPS calls to the nginx gateway will fail PKIX validation" >&2
fi

export JAVA_OPTS="-Djavax.net.ssl.trustStore=${TRUSTSTORE} -Djavax.net.ssl.trustStorePassword=changeit ${JAVA_OPTS:-}"

exec /bin/bash /run.sh "$@"
