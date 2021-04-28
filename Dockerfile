
FROM debian:buster

COPY scripts /tmp/scripts
RUN chmod +x /tmp/scripts/peer-finder
RUN chmod +x /tmp/scripts/on-start.sh
RUN chmod +x /tmp/scripts/sentinel.sh

COPY conf /tmp/conf

COPY init_scripts /init_scripts
ENTRYPOINT ["/init_scripts/run.sh"]
# ENTRYPOINT ["sleep", "3600"]





