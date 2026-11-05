FROM ghcr.io/anomalyco/opencode:1.19.5

RUN apk add --no-cache util-linux-misc tini

COPY mask-entrypoint.sh /usr/local/bin/mask-entrypoint.sh

RUN chmod +x /usr/local/bin/mask-entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/mask-entrypoint.sh"]
