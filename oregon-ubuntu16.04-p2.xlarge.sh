#!/bin/bash
#
# Configure a p2.xlarge instance with the default deep learning AMI

if [ "$#" -ne 1 ]; then
    echo "Usage: oregon-ubuntu16.04-p2.xlarge.sh name"
    exit 1
fi

# get the correct ami
region=$(aws configure get region)
if [ $region != "us-west-2" ]; then
    echo "us-west-2 (oregon) region only"
    exit 1
fi

ami="ami-835b4efa"
instanceType="p2.xlarge"

$(dirname $(readlink -f "$0"))/setup-instance.sh "$ami" "$instanceType" "$1"
