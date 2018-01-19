#!/bin/bash
#
# Convenience script for updating the dockerfile

set -e
set -v

docker login
image=$(nvidia-docker build --quiet .)
pushname="vlad17/deep-learning:tf-cpu-ubuntu"
docker tag $image $pushname
docker push $pushname

