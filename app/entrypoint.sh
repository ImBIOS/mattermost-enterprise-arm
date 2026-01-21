#!/bin/sh

# ============================================
# TELEMETRY COLLECTION (Opt-out: DISABLE_TELEMETRY=1)
# ============================================
collect_telemetry() {
    if [ "${DISABLE_TELEMETRY:-0}" = "1" ]; then
        return 0
    fi

    # Generate anonymous instance ID (rotates on container restart)
    INSTANCE_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 32)

    # Collect environment info (no PII/secrets)
    TELEMETRY_DATA=$(cat <<EOF
{
    "instance_id": "${INSTANCE_ID}",
    "image_version": "${MM_VERSION:-unknown}",
    "architecture": "$(uname -m)",
    "os": "$(uname -s)",
    "container_runtime": "$(cat /proc/1/cgroup 2>/dev/null | head -1 | cut -d: -f3 | cut -d/ -f1 || echo 'unknown')",
    "startup_time_ms": $(($(date +%s%N)/1000000 - ${START_TIME:-$(date +%s%N)/1000000})),
    "db_type": "postgres",
    "telemetry_version": "1.0"
}
EOF
)

    # Send to telemetry endpoint (configurable via TELEMETRY_ENDPOINT)
    TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT:-https://telemetry.imbios.dev/collect}"

    # Fire-and-forget POST (won't block startup)
    curl -s -X POST "${TELEMETRY_ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d "${TELEMETRY_DATA}" \
        --connect-timeout 5 \
        --max-time 10 \
        >/dev/null 2>&1 &

    echo "[telemetry] Data collected (disabled: set DISABLE_TELEMETRY=1 to opt-out)"
}

# Record startup time
START_TIME=$(($(date +%s%N)/1000000))

# Function to generate a random salt
generate_salt() {
  tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 48 | head -n 1
}

# Read environment variables or set default values
DB_HOST=${DB_HOST:-db}
DB_PORT_NUMBER=${DB_PORT_NUMBER:-5432}
# see https://www.postgresql.org/docs/current/libpq-ssl.html
# for usage when database connection requires encryption
# filenames should be escaped if they contain spaces
#  i.e. $(printf %s ${MY_ENV_VAR:-''}  | jq -s -R -r @uri)
# the location of the CA file can be set using environment var PGSSLROOTCERT
# the location of the CRL file can be set using PGSSLCRL
# The URL syntax for connection string does not support the parameters
# sslrootcert and sslcrl reliably, so use these PostgreSQL-specified variables
# to set names if using a location other than default
DB_USE_SSL=${DB_USE_SSL:-disable}
MM_DBNAME=${MM_DBNAME:-mattermost}
MM_CONFIG=${MM_CONFIG:-/mattermost/config/config.json}

_1=$(echo "$1" | awk '{ s=substr($0, 0, 1); print s; }')
if [ "$_1" = '-' ]; then
  set -- mattermost "$@"
fi

if [ "$1" = 'mattermost' ]; then
  # Check CLI args for a -config option
  for ARG in "$@"; do
    case "$ARG" in
    -config=*) MM_CONFIG=${ARG#*=} ;;
    esac
  done

  if [ ! -f "$MM_CONFIG" ]; then
    # If there is no configuration file, create it with some default values
    echo "No configuration file $MM_CONFIG"
    echo "Creating a new one"
    # Copy default configuration file
    cp config.json.save "$MM_CONFIG"
    # Substitute some parameters with jq
    jq '.ServiceSettings.ListenAddress = ":8000"' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.LogSettings.EnableConsole = true' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.LogSettings.ConsoleLevel = "ERROR"' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.FileSettings.Directory = "/mattermost/data/"' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.FileSettings.EnablePublicLink = true' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq ".FileSettings.PublicLinkSalt = \"$(generate_salt)\"" "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.EmailSettings.SendEmailNotifications = false' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.EmailSettings.FeedbackEmail = ""' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.EmailSettings.SMTPServer = ""' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.EmailSettings.SMTPPort = ""' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq ".EmailSettings.InviteSalt = \"$(generate_salt)\"" "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq ".EmailSettings.PasswordResetSalt = \"$(generate_salt)\"" "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.RateLimitSettings.Enable = true' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.SqlSettings.DriverName = "postgres"' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq ".SqlSettings.AtRestEncryptKey = \"$(generate_salt)\"" "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
    jq '.PluginSettings.Directory = "/mattermost/plugins/"' "$MM_CONFIG" >"$MM_CONFIG.tmp" && mv "$MM_CONFIG.tmp" "$MM_CONFIG"
  else
    echo "Using existing config file $MM_CONFIG"
  fi

  # Configure database access
  if [ -z "$MM_SQLSETTINGS_DATASOURCE" ] && [ -n "$MM_USERNAME" ] && [ -n "$MM_PASSWORD" ]; then
    echo "Configure database connection..."
    # URLEncode the password, allowing for special characters
    ENCODED_PASSWORD=$(printf %s "$MM_PASSWORD" | jq -s -R -r @uri)
    export MM_SQLSETTINGS_DATASOURCE="postgres://$MM_USERNAME:$ENCODED_PASSWORD@$DB_HOST:$DB_PORT_NUMBER/$MM_DBNAME?sslmode=$DB_USE_SSL&connect_timeout=10"
    echo "OK"
  else
    echo "Using existing database connection"
  fi

  # Wait another second for the database to be properly started.
  # Necessary to avoid "panic: Failed to open sql connection pq: the database system is starting up"
  sleep 1

  echo "Starting mattermost"
fi

# Send telemetry (async, won't delay startup)
collect_telemetry

exec "$@"
