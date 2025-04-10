#!/bin/bash

set -x

if [ -n "$RANDOM_SEED" ]; then
    RANDOM=$RANDOM_SEED
fi
HOSTNAME=$(hostname)
CURRENT_NAME=$(docker inspect -f '{{.Name}}' $HOSTNAME | sed 's/\///')
PREFIX=$(echo "$CURRENT_NAME" | sed 's/-chaos-maker.*//')

CONTAINERS=$(docker ps --format '{{.Names}}' | grep -E "^$PREFIX.*nats-chaos-node")
CONTAINER_ARRAY=($CONTAINERS)
NCONTAINERS=${#CONTAINER_ARRAY[@]}
if [ "$NCONTAINERS" -eq 0 ]; then
    echo "No containers to mess with, exiting"
    exit 1
fi

NBRANCHES=5
while true; do
    RANDOM_NUMBER=$RANDOM

    CONTAINER_INDEX=$((RANDOM_NUMBER % NCONTAINERS))
    SELECTED_CONTAINER=${CONTAINER_ARRAY[$CONTAINER_INDEX]}

    BRANCH=$((RANDOM_NUMBER % NBRANCHES))

    echo "Random is $RANDOM_NUMBER, Branch selected: $BRANCH"
    
    case $BRANCH in
        0)
            docker restart "$SELECTED_CONTAINER"
            ;;
        1)
            docker stop "$SELECTED_CONTAINER"
            sleep 2
            sleep $((RANDOM_NUMBER % 20))
            docker start "$SELECTED_CONTAINER"
            ;;
        2)
            docker kill "$SELECTED_CONTAINER"
            sleep 2
            sleep $((RANDOM_NUMBER % 20))
            docker start "$SELECTED_CONTAINER"
            # sleep 2
            ;;
        3)
            docker exec $SELECTED_CONTAINER tc qdisc del dev eth0 root
            docker exec $SELECTED_CONTAINER tc qdisc add dev eth0 root netem delay 500ms loss 95%
            sleep 2
            sleep $((RANDOM_NUMBER % 20))
            docker exec $SELECTED_CONTAINER tc qdisc del dev eth0 root
            docker exec $SELECTED_CONTAINER tc qdisc add dev eth0 root netem delay 50ms loss 10%
            ;;
        4)
            docker exec $SELECTED_CONTAINER nats-server --signal ldm=1
            ;;
        *)
            echo "Unexpected branch: $BRANCH"
            ;;
    esac

    sleep 40
done