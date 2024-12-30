#!/bin/bash

set -e
#set -x

# set up data & secrets dir with the right ownerships in the default location
# to stop docker autocreating them with random owners.
# originally these were checked into the git repo, but that's pretty ugly, so doing it here instead.
mkdir -p data/{element-{web,call},livekit,mas,caddy/{conf,data,site},postgres,synapse}
mkdir -p secrets/{livekit,postgres,synapse}

# create blank secrets to avoid docker creating empty directories in the host
touch secrets/livekit/livekit_{api,secret}_key \
      secrets/postgres/postgres_password \
      secrets/synapse/signing.key

# grab an env if we don't have one already
if [[ ! -e .env  ]]; then
    cp .env-sample .env

    sed -ri.orig "s/^USER_ID=/USER_ID=$(id -u)/" .env
    sed -ri.orig "s/^GROUP_ID=/GROUP_ID=$(id -g)/" .env

    read -p "Enter base domain name (e.g. example.com): " DOMAIN
    sed -ri.orig "s/example.com/$DOMAIN/" .env

    # try to guess your livekit IP
    if [ -x "$(command -v getent)" ]; then
        NODE_IP=`getent hosts livekit.$DOMAIN | cut -d' ' -f1`
        if ! [ -z "$NODE_IP" ]; then
            sed -ri.orig "s/LIVEKIT_NODE_IP=127.0.0.1/LIVEKIT_NODE_IP=$NODE_IP/" .env
        fi
    fi

    # SSL setup
    cp data{-template,}/caddy/conf/Caddyfile
    read -p "Use letsencrypt instead of Caddy local_certs for SSL? [y/n] " use_local_certs
    if [[ "$use_local_certs" =~ ^[Yy]$ ]]; then
        sed -ri.orig "s/local_certs/# local_certs" data/caddy/conf/Caddyfile
    fi
    success=true
else
    echo ".env already exists; move it out of the way first to re-setup"
fi

if [ -n "$success" ]; then
    echo ".env and SSL configured"
    echo "Run now with podman-compose (or docker-compose):"
    echo "$ podman unshare chown -R 1000:1000 data/ secrets/ # (podman rootless only)"
    echo "$ podman-compose run --rm generate-synapse-secrets generate"
    echo "$ podman-compose run --rm generate-mas-secrets config generate -o /data/config.yaml.default"
    echo ""
    echo "Then you can run docker compose up"
fi
