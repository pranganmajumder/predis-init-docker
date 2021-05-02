#!/bin/bash
cp /conf/sentinel.conf /data/sentinel.conf

echo -e "\nSENTINEL resolve-hostnames yes" >>/data/sentinel.conf


exec redis-sentinel /data/sentinel.conf