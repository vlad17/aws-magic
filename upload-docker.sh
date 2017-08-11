#!/bin/bash

set -e
set -v

nvidia-docker login
image=$(nvidia-docker build --quiet .)
pushname="vlad17/deep-learning:tf-gpu-ubuntu"
nvidia-docker tag $image $pushname
docker push $pushname

