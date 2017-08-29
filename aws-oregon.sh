#!/bin/bash
#
# Offer some default options for an Ubuntu instance, interactively.

if [ "$#" -gt 3 ] || [ "$1" = "--help" ]; then
    echo "Usage: aws-oregon.sh [name] [instancetype] [ami]"
    echo "Thin wrapper with defaults around setup-instance.sh"
    echo "See description in aws-magic/README.md"
    exit 1
fi

region=$(aws configure get region)
if [ $region != "us-west-2" ]; then
    echo "us-west-2 (oregon) region only"
    exit 1
fi

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
    read -p "choose instance type [$dfl]: " instancetype
    instancetype=${instancetype:-$dfl}
fi

if [ "$#" -gt 2 ]; then
    ami="$3"
else
    dfl="ami-8803e0f0"
    read -p "choose ami [$dfl, Ubuntu 16.04 HVM]: " ami
    ami=${ami:-$dfl}
fi

$(dirname $(readlink -f "$0"))/setup-instance.sh "$ami" "$instancetype" "$name"
