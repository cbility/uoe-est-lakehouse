#!/bin/sh
# Adapted from https://github.com/sendrec/sendrec/blob/main/SELF-HOSTING.md
set -e
S3_BUCKET="${S3_BUCKET}"
S3_REGION="${S3_REGION}"
STORAGE_CAPACITY_GB="${HOST_STORAGE_CAPACITY_GB:-100}"
GARAGE_KEYS_FILE="${GARAGE_KEYS_FILE:-/run/garage-keys/env}"
GARAGE_CONFIG="/config/garage.toml"

# Wrapper so every garage CLI call uses the generated config
garage() { command garage -c "${GARAGE_CONFIG}" "$@"; }

log() { echo "[garage-init] $1"; }

log "Waiting for Garage to become ready..."
until garage status > /dev/null 2>&1; do sleep 1; done
log "Garage is ready"

NODE_ID=$(garage status 2>/dev/null | grep -oE '[a-f0-9]{16}' | head -1)
log "Detected node ID: ${NODE_ID}"

log "Assigning layout for node ${NODE_ID} (zone dc1, capacity ${STORAGE_CAPACITY_GB}G)..."
if garage layout assign -z dc1 -c "${STORAGE_CAPACITY_GB}G" "${NODE_ID}" 2>&1; then
  log "Layout assigned"
else
  log "Layout assign skipped (may already be set)"
fi

log "Applying layout version 1..."
if garage layout apply --version 1 2>&1; then
  log "Layout applied"
else
  log "Layout apply skipped (may already be applied)"
fi

log "Checking if key 'ducklake-key' already exists..."
if garage key info ducklake-key > /dev/null 2>&1; then
  log "Key already exists, fetching info..."
  KEY_INFO=$(garage key info ducklake-key --show-secret 2>&1)
else
  log "Creating S3 key 'ducklake-key'..."
  KEY_INFO=$(garage key create ducklake-key --show-secret 2>&1)
  log "Key created successfully"
fi

KEY_ID=$(echo "${KEY_INFO}" | grep -oE 'GK[a-f0-9]{24}' | head -1)
SECRET=$(echo "${KEY_INFO}" | grep "Secret key" | sed 's/.*: *//')

if [ -n "${KEY_ID}" ] && [ -n "${SECRET}" ]; then
  log "Extracted key ID: ${KEY_ID}"
  mkdir -p "$(dirname "${GARAGE_KEYS_FILE}")"
  printf 'S3_ACCESS_KEY=%s\nS3_SECRET_KEY=%s\n' "${KEY_ID}" "${SECRET}" > "${GARAGE_KEYS_FILE}"
  log "Credentials written to ${GARAGE_KEYS_FILE}"
  log "  S3_ACCESS_KEY=${KEY_ID}"
  log "  S3_SECRET_KEY=${SECRET}"
else
  log "ERROR: Could not extract key credentials from key info output"
  exit 1
fi

log "Creating bucket '${S3_BUCKET}'..."
if garage bucket create "${S3_BUCKET}" 2>&1; then
  log "Bucket '${S3_BUCKET}' created"
else
  log "Bucket '${S3_BUCKET}' already exists, skipping"
fi

log "Granting key ${KEY_ID} read/write/owner access to bucket '${S3_BUCKET}'..."
if garage bucket allow --read --write --owner "${S3_BUCKET}" --key "${KEY_ID}" 2>&1; then
  log "Bucket permissions set"
else
  log "Bucket permissions skipped (may already be set)"
fi

log "Garage initialisation complete"