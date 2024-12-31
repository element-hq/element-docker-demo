#!/bin/bash

set -e

# grab an env if we don't have one already
if [[ ! -e .env  ]]; then
    read -p "Enter base domain name [matrix.local]: " DOMAIN

    # set up data & secrets dir with the right ownerships in the default location
    # to stop docker autocreating them with random owners.
    # originally these were checked into the git repo, but that's pretty ugly, so doing it here instead.
    mkdir -p data/{element-{web,call},livekit,mas,caddy/{data,site},postgres/{synapse,mas},synapse}
    mkdir -p secrets/{livekit,postgres,synapse}
    # mkdir -p data/caddy/data/caddy/pki/authorities/local/ # for caddy local cert TODO

    # create blank secrets to avoid docker creating empty directories in the host
    touch secrets/livekit/livekit_{api,secret}_key \
        secrets/postgres/postgres_password \
        secrets/synapse/signing.key

    # when caddy doesn't setup a local root, then create empty file to avoid mapping non-existant file
    # touch data/caddy/data/caddy/pki/authorities/local/root.crt TODO


    cp .env-sample .env
    sed -ri "s/example.local/${DOMAIN:=matrix.local}/g" .env

    # try to guess your livekit IP
    if [ -x "$(command -v getent)" ]; then
        NODE_IP=$(getent hosts livekit.$DOMAIN | cut -d' ' -f1)
        if [ -n "$NODE_IP" ]; then
            sed -ri.orig "s/LIVEKIT_NODE_IP=127.0.0.1/LIVEKIT_NODE_IP=$NODE_IP/" .env
        fi
    fi

    # SSL setup
    read -p "letsencrypt email (unsed for *.local domains) [security@$DOMAIN]: " mail
    sed -ri "s/LETS_ENCRYPT_EMAIL=.*/LETS_ENCRYPT_EMAIL=${mail:-security@${DOMAIN}}/" .env

    read -p "Use podman-compose instead of docker compose? [y/n]: " use_podman
    if [[ "$use_podman" =~ ^[Yy]$ ]]; then
        # 65534 should be system user nobody in most container images
        USER_ID=65534
        GROUP_ID=65534
        POSTGRES_USER=nobody
        # podman rootless maps local user id to root
        # nobody avoids to use postgres role root (default mapping) when using unix sockets
        sed -ri.orig "s/^USER_ID=/USER_ID=$USER_ID/" .env
        sed -ri.orig "s/^GROUP_ID=/GROUP_ID=$GROUP_ID/" .env
        sed -ri "s/^POSTGRES_USER=/POSTGRES_USER=$POSTGRES_USER/" .env
        podman unshare chown -R $USER_ID:$GROUP_ID data/ secrets/

        podman-compose --profile init run --rm generate-synapse-secrets generate
        podman-compose --profile init run --rm generate-mas-secrets config generate -o /data/config.yaml.default
        podman-compose --profile init run --rm init
        LAUNCH_MSG="Launch with: podman-compose up"
        LAUNCH_MSG="Launch with: docker compose up\nRegister user: podman-compose exec mas mas-cli -c /data/config.yaml manage register-user"

        echo "USE_PODMAN=1" >> .env
    else
        sed -ri "s/^USER_ID=/USER_ID=$(id -u)/" .env
        sed -ri "s/^GROUP_ID=/GROUP_ID=$(id -g)/" .env
        sed -ri "s/^POSTGRES_USER=/POSTGRES_USER=postgres/" .env

        docker compose --profile init run --rm generate-synapse-secrets generate
        docker compose --profile init run --rm generate-mas-secrets config generate -o /data/config.yaml.default
        docker compose --profile init run --rm init
        LAUNCH_MSG="Launch with: docker compose up\nRegister user: docker compose exec mas mas-cli -c /data/config.yaml manage register-user"
    fi

    echo ".env and SSL configured"
    echo "You may want to add to your /etc/hosts: 127.0.0.1 $(source .env; echo $DOMAINS)"
    echo ""
    echo "$LAUNCH_MSG"
else
    echo ".env already exists."
    read -p "To reset first the entire setup and loose all data type DELETE [abort]: " do_delete
    if [[ "$do_delete" =~ ^DELETE$ ]]; then
        set +e
        if [[ -n $(source .env; echo $USE_PODMAN) ]]; then
            podman unshare rm -r data/ secrets/
            podman-compose down -v
        else
            rm -r data/ secrets/
            docker compose down -v
        fi
        rm .env
        ./$0 # recursive call of setup.sh
    fi
fi
