#!/bin/bash
#
# Offer some default options for an Ubuntu instance

if [ "$#" -gt 2 ] || [ "$1" = "--help" ]; then
    echo "Usage: oregon-ubuntu.sh [name] [instancetype]"
    exit 1
fi

region=$(aws configure get region)
if [ $region != "us-west-2" ]; then
    echo "us-west-2 (oregon) region only"
    exit 1
fi
ami="ami-8803e0f0"

if [ "$#" -gt 0 ]; then
    name="$1"
else
    i=0
    while [ -d "$HOME/aws-instances/s$i" ] ; do
        let i++
    done
    dfl="s$i"
    read -p "choose server name [$dfl]: " name
    name=${name:-$dfl}
fi

if [ -d "$name" ]; then
    echo "error: directory ~/aws-instances/$name already exists"
    exit 1
fi

if [ "$#" -gt 1 ]; then
    instancetype="$2"
else
    dfl="g3.8xlarge"
    read -p "choose server name [$dfl]: " instancetype
    instancetype=${instancetype:-$dfl}
fi
echo $instancetype $name
$(dirname $(readlink -f "$0"))/setup-instance.sh "$ami" "$instancetype" "$name"
