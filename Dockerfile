FROM cloudflare/mesh:latest

RUN apk add --no-cache socat curl

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]