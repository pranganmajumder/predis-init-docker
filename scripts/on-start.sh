#!/bin/bash


echo "-----------run.sh variable-------------------$@-----------------------"
cp /config/redis.conf /data/redis.conf
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

my_hostname=$(hostname)
echo "Bootstrapping RedisDB replica set member: $my_hostname"
echo  "Reading standard input..."

# Peer finder -----------
while read -ra line; do
    tmp=$(echo -n ${line[0]} | sed -e "s/.svc.cluster.local//g")
    if [[ "$HOST_ADDRESS_TYPE" == "IPv6" ]]; then
        tmp="[$tmp]"
    fi
    peers=("${peers[@]}" "$tmp")
done
echo "Trying to start group with peers'${peers[*]}'"

for ip in "${peers[@]}"
do
  echo "ip is ------------ $ip -------- "
done

sleep 6
sentinel_info_command="redis-cli -h sentinel-svc.default.svc -p 26379 SENTINEL get-master-addr-by-name mymaster"
REDIS_SENTINEL_INFO=($($sentinel_info_command))
REDIS_MASTER_HOST=${REDIS_SENTINEL_INFO[0]}
REDIS_MASTER_PORT_NUMBER=${REDIS_SENTINEL_INFO[1]}

echo "--------maser host --$REDIS_MASTER_HOST-------------"
echo "--------master port --$REDIS_MASTER_PORT_NUMBER------"
echo "-----------------------------------------"
echo " --------len   - ${#REDIS_SENTINEL_INFO[@]} ---- "


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
        for (( i=0; i<$replica_of_sentinel; i++ ))
            do
                RESET_SENTINEL=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel reset mymaster)
            done
        echo "before wait  -------------- "
        wait $pid
    else
        echo "Got invalid IP from sentinel, check how many master is right now in peer list"
        echo "again start peer finder -------------------------------"
        my_hostname=$(hostname)
        echo "Bootstrapping RedisDB replica set member: $my_hostname"
        echo  "Reading standard input..."
        while read -ra line; do
            tmp=$(echo -n ${line[0]} | sed -e "s/.svc.cluster.local//g")
            if [[ "$HOST_ADDRESS_TYPE" == "IPv6" ]]; then
                tmp="[$tmp]"
            fi
            peers=("${peers[@]}" "$tmp")
        done
        echo "Trying to start group with peers'${peers[*]}'"

        for ip in "${peers[@]}"
        do
            echo "ip is ------------ $ip -------- "
        done


        echo "check how many master are in the list"
        flag=0
        cnt_master=0
        for ip in "${peers[@]}"
        do
            ROLE=$(redis-cli -h $ip -p 6379 info replication | grep ^role)
            echo "jhamela hocche --------------- "
            if [[ $ROLE == "role:master" ]]; then
              (( cnt_master++ ))
            fi
        done

        echo "total master ================= $cnt_master ================ "
        if [[ $cnt_master == "0" ]]; then
            sleep 6

            echo "cnt_master = 0 ------------------------- peer finder ------------------------ "
            my_hostname=$(hostname)
            echo "Bootstrapping RedisDB replica set member: $my_hostname"
            echo  "Reading standard input..."
            while read -ra line; do
                tmp=$(echo -n ${line[0]} | sed -e "s/.svc.cluster.local//g")
                if [[ "$HOST_ADDRESS_TYPE" == "IPv6" ]]; then
                    tmp="[$tmp]"
                fi
                peers=("${peers[@]}" "$tmp")
            done

            echo "Trying to start group with peers'${peers[*]}'"
            for ip in "${peers[@]}"
            do
                echo "ip is ------------ $ip -------- "
            done

            echo "again go to sentinel & fetch new master IP & check again if new master IP in peer list or not-----------"

            sentinel_info_command_2="redis-cli -h sentinel-svc.default.svc -p 26379 SENTINEL get-master-addr-by-name mymaster"
            REDIS_SENTINEL_INFO_2=($($sentinel_info_command))
            REDIS_MASTER_HOST_2=${REDIS_SENTINEL_INFO[0]}
            echo "new master_Host_2 --------------  $REDIS_MASTER_HOST_2 -------------- "

            echo "checking  if the REDIS_MASTER_HOST_2 is in peer list or not"
            flag=0
            for ip in "${peers[@]}"
            do
                if [[ $REDIS_MASTER_HOST_2 == $ip ]]; then
                    flag=1
                    echo "------------------REDIS master host :  $REDIS_MASTER_HOST_2 ------------ ip = $ip "
                fi
            done

            if [[ $flag == "1" ]]; then
                echo "flag ========== 1 ========= "
                echo -e "\nslaveof $REDIS_MASTER_HOST_2 6379" >> /data/redis.conf
                exec redis-server /data/redis.conf
            else
                echo "make 0th pod master & the rest of it as the slave of master 0th , this is the final configuration"
                echo "Remove master from every sentinel --------------------- "
                for (( i=0; i<$replica_of_sentinel; i++ ))
                do
                    REMOVE_MASTER=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 SENTINEL REMOVE mymaster)
                done

                echo "add other sentinel configuration with all other sentinel---------------------------"
                for (( i=0; i<$replica_of_sentinel; i++ ))
                do
                    ADD_MASTER=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 SENTINEL MONITOR mymaster predis-sts-0.predis-svc.default.svc 6379 2)
                    ADD_FAILOVER_TIME_OUT=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel set mymaster failover-timeout $timeout)
                    ADD_DOWN_AFTER_MILLISECONDS=$(redis-cli -h sentinel-sts-$i.sentinel-svc.default.svc -p 26379 sentinel set mymaster down-after-milliseconds $down)
                done

                # add replicaof predis-sts-0 with previous pod , (not restarted new pod, cz it'll not add with restarted pod as the server isn't running)
                for ip in "${peers[@]}"
                do
                    echo "dhukchi loop a ================ "
                    ROLE=$(redis-cli -h $ip -p 6379 info replication | grep ^role)
                    MASTER_HOST=$(redis-cli -h $ip -p 6379 info replication | grep ^master_host)
                    EXPECTED_MASTER_HOST="master_host:predis-sts-0.predis-svc.default.svc"

                    echo "role--------------$ROLE---------------- "
                    echo "master_host-------- $MASTER_HOST--------------- "
                    # zodi slave pod hoy & 0th pod ar replica na hoy
                    if [[ $ROLE == "role:slave" && $MASTER_HOST -ne $EXPECTED_MASTER_HOST ]]; then
                      echo " hey mama ------ "
                      replicaof=$(redis-cli -h $ip -p 6379 replicaof predis-sts-0.predis-svc.default.svc 6379)
                    fi
                done

                if [[ $(hostname) == "predis-sts-0" ]]; then
                    echo "make predis-sts-0 as the master -----"
                    exec redis-server /data/redis.conf
                else
                    echo "connected as slave------------------------- "
                    echo -e "\nreplicaof predis-sts-0.predis-svc.default.svc 6379" >> /data/redis.conf
                    exec redis-server /data/redis.conf
                fi
            fi
        else
            echo "asche akhane --------------------- "
            echo -e "\nslaveof $REDIS_MASTER_HOST 6379" >> /data/redis.conf
            exec redis-server /data/redis.conf
        fi
    fi
fi
