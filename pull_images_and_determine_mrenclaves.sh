#!/bin/bash
set -e

# usage: get_mrenclave image [cmd docker_run_modifiers]
# return: mrenclave, if successful.
#
# e.g. get_mrenclave registry.scontain.com:5050/sconecuratedimages/apps:mariadb-10.4-alpine mysqld "-e SCONE_HEAP=2G"
#
function get_mrenclave {
    mre=$(docker run -it $3 --rm -e SCONE_HASH=1 $1 $2)
    ret=$(echo $mre | grep -o -e "[0-9a-f]\{64\}")
    if [ -z "$ret" ]; then
        echo "[ERROR] could not determine mrenclave of "$1 $2
        exit 1
    fi
    echo $ret
}

MEMCACHED_IMAGE=registry.scontain.com:5050/sconecuratedimages/experimental:memcached-1-alpine-scone5.6.1
CLIENT_IMAGE=registry.scontain.com:5050/sconecuratedimages/experimental:memcached-demoapp-alpine3.10-scone5.6.0

echo "Pulling the latest images. Make sure you have access to all of them!"

docker pull $MEMCACHED_IMAGE
docker pull $CLIENT_IMAGE

echo "Determining the MRENCLAVEs."

MEMCACHED_MRENCLAVE=$(get_mrenclave $MEMCACHED_IMAGE memcached "-e SCONE_HEAP=2G -e SCONE_MODE=hw --entrypoint=""")
CLIENT_MRENCLAVE=$(get_mrenclave $CLIENT_IMAGE python3 "")

cat > /tmp/mrenclaves.sh << EOF
export MEMCACHED_MRENCLAVE="$MEMCACHED_MRENCLAVE"
export CLIENT_MRENCLAVE="$CLIENT_MRENCLAVE"
EOF

sed 's/\r//g' /tmp/mrenclaves.sh > mrenclaves.sh

echo "OK."
