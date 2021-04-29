#!/bin/bash

cp /conf/redis.conf /data/redis.conf
echo -e "\nreplica-announce-ip $HOSTNAME.predis-svc.default.svc" >>/data/redis.conf
replica_of_sentinel=$REPLICA_OF_SENTINEL
down=5000
timeout=5000

flag=1
not_exists_dns_entry() {
   myip=$(hostname -i)
   echo " my ip $myip"
   if [[ -z "$(getent ahosts "$HEADLESS_SERVICE" | grep "^${myip}" )" ]]; then
       echo "$HEADLESS_SERVICE does not contain the IP of this pod: ${myip}"
       flag=1
   else
      echo "$HEADLESS_SERVICE has my IP: ${myip}"
      flag=0
   fi
}


HEADLESS_SERVICE="predis-svc.default.svc"
while [[ flag -ne 0 ]]
do
  echo "getting ----- "
  echo "flag =  $flag "
  not_exists_dns_entry
  sleep 1
done
echo "..........$HOSTNAME------------"



sleep 6
sentinel_info_command="redis-cli -h sentinel-svc.default.svc -p 26379 SENTINEL get-master-addr-by-name mymaster"
REDIS_SENTINEL_INFO=($($sentinel_info_command))
REDIS_MASTER_HOST=${REDIS_SENTINEL_INFO[0]}
REDIS_MASTER_PORT_NUMBER=${REDIS_SENTINEL_INFO[1]}

echo "--------maser host --$REDIS_MASTER_HOST-------------------master port --$REDIS_MASTER_PORT_NUMBER----- ------len- ${#REDIS_SENTINEL_INFO[@]} ----"



if [[ ${#REDIS_SENTINEL_INFO[@]} == 0 ]]; then
    if [[ $HOSTNAME == "predis-sts-0" ]]; then
        echo "add other sentinel configuration with all other sentinel---------------------------"
        for (( i=0; i<$replica_of_sentinel; i++ ))
        do
            ADD_MASTER=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 SENTINEL MONITOR mymaster predis-sts-0.predis-svc.default.svc 6379 2)
            ADD_FAILOVER_TIME_OUT=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel set mymaster failover-timeout $timeout)
            ADD_DOWN_AFTER_MILLISECONDS=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel set mymaster down-after-milliseconds $down)
        done
        exec redis-server /data/redis.conf
    else
        echo -e "\nreplicaof predis-sts-0.predis-svc.default.svc 6379" >>/data/redis.conf
        exec redis-server /data/redis.conf
    fi
else
    ping_command="timeout 2 redis-cli -h $REDIS_MASTER_HOST -p 6379 ping"
    PONG=($($ping_command))
    echo "------ pn = $PONG  ------ "
    if [[ $PONG == "PONG" ]]; then
        echo "---- paichi pong   for $HOSTNAME ------- "
        echo -e "\nreplicaof $REDIS_MASTER_HOST $REDIS_MASTER_PORT_NUMBER" >> /data/redis.conf

        echo "reseting sentinel  -------------- "
        for (( i=0; i<$replica_of_sentinel; i++ ))
        do
              RESET_SENTINEL=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel reset mymaster)
        done

        exec redis-server /data/redis.conf

    else
        echo "make 0th pod master & the rest of it as the slave of master 0th , this is the final configuration"
        echo "Remove master from every sentinel --------------------- "

        if [[ $(hostname) == "predis-sts-0" ]]; then
            for (( i=0; i<$replica_of_sentinel; i++ ))
            do
                REMOVE_MASTER=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 SENTINEL REMOVE mymaster)
            done
        fi

        if [[ $(hostname) == "predis-sts-0" ]]; then
            echo "add other sentinel configuration with all other sentinel---------------------------"
            for (( i=0; i<$replica_of_sentinel; i++ ))
            do
                ADD_MASTER=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 SENTINEL MONITOR mymaster predis-sts-0.predis-svc.default.svc 6379 2)
                ADD_FAILOVER_TIME_OUT=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel set mymaster failover-timeout $timeout)
                ADD_DOWN_AFTER_MILLISECONDS=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel set mymaster down-after-milliseconds $down)
            done
        fi

        if [[ $(hostname) == "predis-sts-0" ]]; then
            echo "make predis-sts-0 as the master -----"
            exec redis-server /data/redis.conf
        else
            echo "connected as slave------------------------- "
            echo -e "\nreplicaof predis-sts-0.predis-svc.default.svc 6379" >> /data/redis.conf
            exec redis-server /data/redis.conf
       fi
    fi
fi
