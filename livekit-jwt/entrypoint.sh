#!/bin/bash

# launch lk-jwt-service with secrets from disk

export LK_JWT_PORT=8080
export LIVEKIT_URL=wss://${LIVEKIT_FQDN}:${CADDY_HTTPS_PORT}
export LIVEKIT_KEY=$(</run/secrets/livekit_api_key)
export LIVEKIT_SECRET=$(</run/secrets/livekit_secret_key)

exec /lk-jwt-service
