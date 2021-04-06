FROM debian:buster-slim
COPY redis.conf /tmp/config/redis.conf
COPY init-script /init-script

ENTRYPOINT ["/init-script/run.sh"]