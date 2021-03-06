#!/bin/bash

cp /conf/redis.conf /data/redis.conf
echo -e "\nreplica-announce-ip $HOSTNAME.predis-svc.default.svc" >>/data/redis.conf
replica_of_sentinel=$REPLICA_OF_SENTINEL
down=5000
timeout=5000

function findMasterPortFromSentinelReplicaList() {
  found_invalid_master_port=0
  local found=0

  for line in $REPLICAS_INFO_FROM_SENTINEL; do
    if [[ "$line" == "master-port" ]]; then
      echo "master-port"
      found=1
      continue
    fi

    if [[ "$found" == "1" ]]; then
      echo "line = $line"
      found=0
      if [[ "$line" == "0" ]]; then
        found_invalid_master_port=1
        echo "found invalid master port"
        break
      fi
    fi

  done
  echo "terminating find_master_hosts function   \n\n\n "

}

function removeMasterGroupFromAllSentinel() {
  echo "remove master_group from all sentinel"
  for ((i = 0; i < $replica_of_sentinel; i++)); do
    REMOVE_MASTER=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 SENTINEL REMOVE mymaster)
  done
}

function addConfigurationWithAllSentinel() {
  echo "add other sentinel configuration with all other sentinel---------------------------"
  for ((i = 0; i < $replica_of_sentinel; i++)); do
    ADD_MASTER=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 SENTINEL MONITOR mymaster "$1".predis-svc.default.svc 6379 2)
    ADD_FAILOVER_TIME_OUT=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel set mymaster failover-timeout $timeout)
    ADD_DOWN_AFTER_MILLISECONDS=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel set mymaster down-after-milliseconds $down)
  done
}

function resetAllSentinel() {
  echo "resenting sentinel "
  for ((i = 0; i < $replica_of_sentinel; i++)); do
    RESET_SENTINEL=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel reset mymaster)
  done
}

function getMasterHost() {
  sentinel_info_command="redis-cli -h sentinel-svc.default.svc -p 26379 SENTINEL get-master-addr-by-name mymaster"
  REDIS_SENTINEL_INFO=($($sentinel_info_command))
  REDIS_MASTER_HOST=${REDIS_SENTINEL_INFO[0]}
  REDIS_MASTER_PORT_NUMBER=${REDIS_SENTINEL_INFO[1]}
  echo "--------maser host --$REDIS_MASTER_HOST-------------------master port --$REDIS_MASTER_PORT_NUMBER----- ------len- ${#REDIS_SENTINEL_INFO[@]} ----"
}


function waitForGettingReadySentinel() {
    echo " wait for getting ready sentinel"
    for (( i = 0; i < 60; i++ ));
    do
      REPLICAS_INFO_FROM_SENTINEL=$(redis-cli -h sentinel-svc.default.svc -p 26379 sentinel replicas mymaster)
      echo " len of REPLICAS_INFO_FROM_SENTINEL  = ${#REPLICAS_INFO_FROM_SENTINEL}"
      if [[ "${#REPLICAS_INFO_FROM_SENTINEL}" == 0 ]]; then
        sleep 1
        continue
      fi
      findMasterPortFromSentinelReplicaList $REPLICAS_INFO_FROM_SENTINEL
      if [[ "$found_invalid_master_port" == "0" ]]; then
        echo "found_invalid_master_port ===== 0 "
        break
      fi
      echo "found_invalid_master_port ==== 1 "
      sleep 1
    done

    if [[ "${#REPLICAS_INFO_FROM_SENTINEL}" == 0 ]]; then
        echo "replica list is empty even after remaining 60s in loop, now again remove & add"
        removeMasterGroupFromAllSentinel
        addConfigurationWithAllSentinel "predis-sts-0"
    fi
}

flag=1
not_exists_dns_entry() {
  echo  "not exitst dns entry ------------- "
  myip=$(hostname -i)
  echo " my ip $myip"
  if [[ -z "$(getent ahosts "$HEADLESS_SERVICE" | grep "^${myip}")" ]]; then
    echo "$HEADLESS_SERVICE does not contain the IP of this pod: ${myip}"
    flag=1
  else
    echo "$HEADLESS_SERVICE has my IP: ${myip}"
    flag=0
  fi
}

HEADLESS_SERVICE="predis-svc.default.svc"
while [[ flag -ne 0 ]]; do
  echo "flag =  $flag "
  not_exists_dns_entry
  sleep 1
done
echo "..........$HOSTNAME------------"











echo "Beginning ------------------------------------------------------------------ ------------------ "

sleep 6
getMasterHost


if [[ ${#REDIS_SENTINEL_INFO[@]} == 0 ]]; then
  if [[ $HOSTNAME == "predis-sts-0" ]]; then
    removeMasterGroupFromAllSentinel
    addConfigurationWithAllSentinel "predis-sts-0"
    exec redis-server /data/redis.conf
  else
    echo -e "\nreplicaof predis-sts-0.predis-svc.default.svc 6379" >>/data/redis.conf
    exec redis-server /data/redis.conf
  fi
else
  ping_command="timeout 2 redis-cli -h $REDIS_MASTER_HOST -p 6379 ping"
  PONG=($($ping_command))
  echo "------ pn = $PONG  ------ ---- "
  if [[ $PONG == "PONG" ]]; then
    echo "---- paichi pong   for $HOSTNAME ------- "
    echo -e "\nreplicaof $REDIS_MASTER_HOST $REDIS_MASTER_PORT_NUMBER" >>/data/redis.conf

    exec redis-server /data/redis.conf &
    pid=$!
    echo "After exec  -------------- "
    for i in {90..0}; do
      out=$(redis-cli -h $(hostname) -p 6379 ping)
      echo "Trying to ping: Step='$i', Got='$out'"
      if [[ "$out" == "PONG" ]]; then
        break
      fi
      echo -n .
      sleep 1
    done

    resetAllSentinel
    waitForGettingReadySentinel
    wait $pid

  else
    echo "make 0th pod master & the rest of it as the slave of master 0th , this is the final configuration"

    if [[ $(hostname) == "predis-sts-0" ]]; then
      removeMasterGroupFromAllSentinel
      addConfigurationWithAllSentinel "predis-sts-0"

      echo "make predis-sts-0 as the master -----"
      exec redis-server /data/redis.conf
    else
      echo "connected as slave------------------------- "
      echo -e "\nreplicaof predis-sts-0.predis-svc.default.svc 6379" >>/data/redis.conf
      exec redis-server /data/redis.conf
    fi
  fi
fi
