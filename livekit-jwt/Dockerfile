# evil hack to pull in bash so we can run an entrypoint.sh
# FIXME: it's a bit wasteful; the alternative would be to modify lk-jwt-service to pick up secrets from disk
# Another alternative would be to factor out secret generation from compose.yml and create an .env up front

FROM ghcr.io/element-hq/lk-jwt-service:latest-ci AS builder
FROM alpine:latest
RUN apk update && apk add bash
COPY --from=builder /lk-jwt-service /
