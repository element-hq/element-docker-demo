#!/bin/bash

set -e

# set up data & secrets dir with the right ownerships in the default location
# to stop docker autocreating them with random owners.
# originally these were checked into the git repo, but that's pretty ugly, so doing it here instead.
mkdir -p data/{element-{web,call},livekit,mas,caddy/{data,site},postgres/{synapse,mas},synapse}
mkdir -p secrets/{livekit,postgres,synapse}
mkdir -p data/caddy/data/caddy/pki/authorities/local/ # for caddy local cert

# create blank secrets to avoid docker creating empty directories in the host
touch secrets/livekit/livekit_{api,secret}_key \
      secrets/synapse/signing.key

# grab an env if we don't have one already
if [[ ! -e .env  ]]; then
    cp .env-sample .env

    read -p "Enter base domain name (e.g. example.com): " DOMAIN
    sed -ri "s/example.local/$DOMAIN/g" .env

    # try to guess your livekit IP
    if [ -x "$(command -v getent)" ]; then
        NODE_IP=$(getent hosts livekit.$DOMAIN | cut -d' ' -f1)
        if [ -n "$NODE_IP" ]; then
            sed -ri.orig "s/LIVEKIT_NODE_IP=127.0.0.1/LIVEKIT_NODE_IP=$NODE_IP/" .env
        fi
    fi

    # SSL setup
    cp data{-template,}/caddy/conf/Caddyfile
    read -p "Use letsencrypt instead of Caddy local_certs for SSL? [y/n] " use_local_certs
    if [[ "$use_local_certs" =~ ^[Yy]$ ]]; then
        sed -ri "s/local_certs/# local_certs" data/caddy/conf/Caddyfile
        # when caddy doesn't setup a local root, then create empty file to avoid mapping non-existant file
        touch data/caddy/data/caddy/pki/authorities/local/root.crt

        read -p "Use letsencrypt instead of Caddy local_certs for SSL? [security@$DOMAIN]" mail
        if [[ -n $mail ]]; then
            sed -ri "s/LETS_ENCRYPT_EMAIL=.*/LETS_ENCRYPT_EMAIL=$mail"
        fi
    fi

    read -p "Use podman-compose instead of docker compose? [y/n]" use_podman
    if [[ "$use_podman" =~ ^[Yy]$ ]]; then
        # 65534 should be system user nobody in most container images
        USER_ID=65534
        GROUP_ID=65534
        # podman rootless maps local user id to root
        # nobody avoids to use postgres role root (default mapping) when using unix sockets
        sed -ri.orig "s/^USER_ID=/USER_ID=$USER_ID/" .env
        sed -ri.orig "s/^GROUP_ID=/GROUP_ID=$GROUP_ID/" .env
        podman unshare chown -R $USER_ID:$GROUP_ID data/ secrets/

        podman-compose run --rm generate-synapse-secrets generate
        podman-compose run --rm generate-mas-secrets config generate -o /data/config.yaml.default
        LAUNCH_MSG="Launch with: podman-compose up"
    else
        sed -ri "s/^USER_ID=/USER_ID=$(id -u)/" .env
        sed -ri "s/^GROUP_ID=/GROUP_ID=$(id -g)/" .env

        docker compose run --rm generate-synapse-secrets generate
        docker compose run --rm generate-mas-secrets config generate -o /data/config.yaml.default
        LAUNCH_MSG="Launch with: docker compose up"
    fi

    echo ".env and SSL configured"
    echo ""
    echo "$LAUNCH_MSG"
else
    echo ".env already exists; move it out of the way first to re-setup"
fi
