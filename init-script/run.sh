#!/bin/bash

cp /tmp/config/* /data/predis-data
echo "......................$POD_NAME...................................."
if [[ "$POD_NAME" -ne "predis-sts-0" ]]; then
    echo -e '\nslaveof predis-svc1-master.default.svc 6379' >>/data/predis-data/redis.conf
fi
