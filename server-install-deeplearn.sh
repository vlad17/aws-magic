#!/bin/bash

######################################################################
# logging, help, exit functions
######################################################################

usage='Usage: server-install-deeplearn.sh passhash gittoken keyname
  
passhash should be the sha1 of a password as created in
http://jupyter-notebook.readthedocs.io/en/latest/public_server.html
for logging into the jupyter notebook

gittoken should be a github personal access token with full repo and
public key control

keyname is the name of the public key that the script will register with
github.


Assuming we have an Nvidia GPU on Ubuntu 16.04 and a Tesla K80 GPU, installs:
 - TensorFlow from source (for python3)
 - emacs by distribution (with autocomplete in dev/)
 - cmake by distribution
 - Various python packages. Those included in anaconda3 and, in addition:
   tabulate six keras

This should all be run on the server (an AWS p2 or g3).

Additional configuration performed:
 - Add autocomplete to emacs
 - Add my dotfiles, from https://github.com/vlad17/misc
 - Jupyter and git configuration (ssh keys/passwords)
'

date=$(date "+%F-%T")

mkdir -p $HOME/install
log="$HOME/install/log-$date.txt"

# https://serverfault.com/questions/103501
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>$log 2>&1

function echolog {
    # http://www.commandlinefu.com/commands/view/6135/tee-to-a-file-descriptor
    echo "$@" | tee $(cat - >&3)
}

function cleanup {
    echolog
    echolog
    echolog "*****************************************************************"
    echolog "INSTALLATION PROBLEM DETECTED, ABORTING"
    echolog "Check installation log $log"
    echolog "*****************************************************************"
}
trap cleanup EXIT

function fail {
    echolog 
    echolog
    echolog "ERROR: $1"
    exit 1
}

function check {
    echolog
    echolog "---> check \$ $1"
    sh -c "$1" 2>&1 | tee $(cat - >&3)
    echolog
}

if [ "$#" -ne "3" ]; then
    echolog "$usage"
    trap '' EXIT
    exit 0
fi
passhash="$1"
gittoken="$2"
keyname="$3"

set -exuo pipefail
cd

######################################################################
# verify OS
######################################################################

echolog -n "verifying OS... "
distrib=$(lsb_release -a 2>/dev/null | grep "Distributor ID" | cut -f2 -d":")
distrib=$(echo $distrib) # remove surrounding whitespace
release=$(lsb_release -a 2>/dev/null | grep "Release" | cut -f2 -d":")
release=$(echo $release)

if [ "$distrib" != "Ubuntu" ] || [ "$release" != "16.04" ]; then
    fail "expected Ubuntu 16.04, got $distrib $release"
else
    echolog OK
fi

echolog -n "verifying nvidia... "
if ! (lspci | grep -i nvidia ); then
    fail "nvidia device not found"
fi
echolog OK

######################################################################
# build deps
######################################################################

echolog -n "updating build tools... "
sudo add-apt-repository ppa:graphics-drivers
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --force-yes
sudo apt-get --assume-yes install tmux build-essential gcc g++ make binutils
sudo apt-get --assume-yes install software-properties-common git
sudo apt-get --assume-yes install apt-transport-https ca-certificates curl
wget https://raw.githubusercontent.com/vlad17/misc/master/fresh-start/.tmux.conf -O .tmux.conf
echolog OK

echolog -n "nvidia drivers... "
sudo apt-get --assume-yes install nvidia-370
sudo apt-get --assume-yes install nvidia-modprobe
echolog OK

check "nvidia-modprobe"

######################################################################
# docker
######################################################################

echolog -n "installing docker... "
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
sudo apt-get update
sudo apt-get --assume-yes install docker-ce
sudo systemctl enable docker
if ! [ $(getent group docker) ]; then
    sudo groupadd docker
fi
sudo usermod -aG docker $USER
# https://superuser.com/questions/272061
oldgroup=$(id -g)
newgrp docker
newgrp $oldgroup
echolog OK

check "docker run hello-world"

echolog -n "nvidia-docker... "
wget -P /tmp https://github.com/NVIDIA/nvidia-docker/releases/download/v1.0.1/nvidia-docker_1.0.1-1_amd64.deb
sudo dpkg -i /tmp/nvidia-docker*.deb && rm /tmp/nvidia-docker*.deb
echolog OK

check "nvidia-docker run --rm nvidia/cuda nvidia-smi"

######################################################################
# git
######################################################################

echolog -n "adding public key as $keyname to git... "
mkdir -p ~/.ssh
if [ -f ~/.ssh/id_*.pub ]; then
    fail "ssh key already exists"
else
    cd ~/.ssh
    ssh-keygen -f ~/.ssh/id_rsa -t rsa -b 4096 -C "vladimir.feinberg@gmail.com" -N ''
    cd
fi
title="$keyname"
key=$( cat ~/.ssh/id_rsa.pub )
json=$( printf '{"title": "%s", "key": "%s"}' "$title" "$key" )
curl -u "vlad17:$gittoken" -d "$json" "https://api.github.com/user/keys"

echo '#!/bin/bash
image=$(nvidia-docker ps | grep -v "CONTAINER ID" | head -1 | cut -f1 -d" ")
if [ -z "$image" ]; then
   echo error: docker not live
   exit 1
fi
echo $image
' > current-image.sh
chmod +x current-image.sh

echo '#!/bin/bash

set -e
image=$($HOME/current-image.sh)
nvidia-docker cp $HOME/.ssh $image:/home/mluser
' > .git.sh
chmod +x .git.sh
echolog OK

######################################################################
# jupyter
######################################################################

echolog -n "setting up server jupyter... "
echo "c.NotebookApp.password = u'"$passhash"'
c.NotebookApp.ip = '*'
c.NotebookApp.open_browser = False" > .jupytercfgadd
echo '#!/bin/bash

set -e
image=$($HOME/current-image.sh)
nvidia-docker exec $image jupyter notebook --generate-config
nvidia-docker cp $HOME/.jupytercfgadd  $image:/home/mluser
nvidia-docker exec $image /bin/bash -c "cat .jupytercfgadd >> /home/mluser/.jupyter/jupyter_notebook_config.py"
' > .jupyter.sh
chmod +x .jupyter.sh
echolog OK

######################################################################
# prepared image
######################################################################

echolog -n "pull in prepared docker image... "
cd
echo '#!/bin/bash
echo "stopping:"
nvidia-docker stop $(docker ps -q)
echo "starting:"
nvidia-docker run --publish 8888:8888 --tty --interactive --detach --expose 8888-8988 --detach-keys="ctrl-@" vlad17/deep-learning:tf-gpu-ubuntu
$HOME/.git.sh
$HOME/.jupyter.sh
' > restart-container.sh
chmod +x restart-container.sh
./restart-container.sh
echolog OK

check "nvidia-docker exec $($HOME/current-image.sh) whoami"
check "nvidia-docker exec $($HOME/current-image.sh) python -c 'import tensorflow as tf;print(tf.Session().run(tf.constant(\"Hello, TensorFlow! \")))'"

######################################################################
# login greeting
######################################################################

echolog -n "updating login greeting... "
for i in $(find /etc/update-motd.d/ -type f -printf '%f\n' | egrep -v '00'); do
    sudo rm -f /etc/update-motd.d/$i
done
sudo ln -s  /usr/bin/nvidia-smi /etc/update-motd.d/15-nvidia-smi
echolog "OK"

######################################################################
# convenience scripts
######################################################################

echo '#!/bin/bash

set -e
image=$($HOME/current-image.sh)
nvidia-docker exec --detach-keys="ctrl-@" --user mluser --interactive --tty $image /bin/bash
' > docker-up.sh
chmod +x docker-up.sh

echolog "*****************************************************************"
echolog "ALL DONE"
echolog "*****************************************************************"

trap '' EXIT

