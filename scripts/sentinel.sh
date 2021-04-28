#!/bin/bash
cp /conf/sentinel.conf /data/sentinel.conf


echo " got scripts............"
echo -e "\nsentinel announce-ip $HOSTNAME.sentinel-svc.default.svc" >>/data/sentinel.conf
echo -e "\nSENTINEL resolve-hostnames yes" >>/data/sentinel.conf
echo -e "\nSENTINEL announce-hostnames yes" >>/data/sentinel.conf
exec redis-sentinel /data/sentinel.conf