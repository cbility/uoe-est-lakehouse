#!/bin/sh
set -e

CONFIG_FILE="/config/garage.toml"

log() { echo "[garage-config] $1"; }

log "Generating ${CONFIG_FILE} from environment..."

: "${GARAGE_RPC_SECRET:?GARAGE_RPC_SECRET must be set}"
: "${GARAGE_ADMIN_TOKEN:?GARAGE_ADMIN_TOKEN must be set}"
: "${S3_REGION:?S3_REGION must be set}"

mkdir -p "$(dirname "${CONFIG_FILE}")"

cat > "${CONFIG_FILE}" <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "sqlite"

replication_factor = 1

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "${GARAGE_RPC_SECRET}"

[s3_api]
s3_region = "${S3_REGION}"
api_bind_addr = "[::]:3900"

[admin]
api_bind_addr = "[::]:3903"
admin_token = "${GARAGE_ADMIN_TOKEN}"
EOF

log "Config written to ${CONFIG_FILE}"
