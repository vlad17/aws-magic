#!/bin/bash

######################################################################
# logging, help, exit functions
######################################################################

usage='Usage: server-install-dev.sh gittoken git-key-name
  
gittoken should be a github personal access token with full repo and
public key control


Installs various stuff on the server:
 - Emacs, docker, kubernetes, helm
 - git config with token
 - Add my dotfiles, from https://github.com/vlad17/misc
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
    bash -c "$1" 2>&1 | tee $(cat - >&3)
    echolog
}

if [ "$#" -ne "2" ]; then
    echolog "$usage"
    trap '' EXIT
    exit 0
fi
gittoken="$1"
keyname="$2"

set -exuo pipefail
cd

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
sudo apt-get --assume-yes --no-install-recommends install docker-ce
sudo systemctl enable docker
if ! [ $(getent group docker) ]; then
    sudo groupadd docker
fi
sudo gpasswd -a $USER docker
echolog OK

check "sudo docker run hello-world"

######################################################################
# emacs
######################################################################

echolog -n "adding emacs on host... "
sudo apt-get --assume-yes --no-install-recommends install emacs
echolog OK

######################################################################
# git
######################################################################

echolog -n "adding public key as $keyname to git... "
mkdir -p ~/.ssh
if ! [ -f ~/.ssh/id_*.pub ]; then
    cd ~/.ssh
    ssh-keygen -f ~/.ssh/id_rsa -t rsa -b 4096 -C "vladimir.feinberg@gmail.com" -N ''
    cd
fi
title="$keyname"
key=$( cat ~/.ssh/id_rsa.pub )
json=$( printf '{"title": "%s", "key": "%s"}' "$title" "$key" )
curl -u "vlad17:$gittoken" -d "$json" "https://api.github.com/user/keys"
echolog OK

######################################################################
# dotfiles repo
######################################################################

echolog -n "cloning dotfiles repo... "
test -d misc || GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone git@github.com:vlad17/misc.git
echolog OK

echolog -n "installing dotfiles..."
misc/fresh-start/emacs-install.sh
misc/fresh-start/config.sh
sudo apt-get --assume-yes --no-install-recommends install tmux cmake build-essential python-dev
misc/conda-install.sh
echolog OK

export PATH="$HOME/dev/anaconda3/bin:$PATH"
check "which python"
check "which conda"

######################################################################
# kubernetes and aws
######################################################################

if [ -f ~/pre-kubernetes.sh ] ; then
    source ~/pre-kubernetes.sh
fi

######################################################################
# kubernetes and aws
######################################################################

echolog -n "kubernetes... "

pip install awscli
mkdir -p ~/bin
wget -qq https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/linux/amd64/aws-iam-authenticator -O ~/bin/aws-iam-authenticator
chmod +x ~/bin/aws-iam-authenticator
export PATH="$HOME/bin:$PATH"
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
helm init
sudo apt-get update && sudo apt-get install -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo touch /etc/apt/sources.list.d/kubernetes.list 
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
sudo apt install --assume-yes openvpn
GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone https://github.com/ahmetb/kubectx.git
mkdir -p ~/bin
mv kubectx/kube* ~/bin
echolog OK

check "kubectl get pods --all-namespaces"

######################################################################
# cleanup
######################################################################

echolog
echolog "*****************************************************************"
echolog "$0: ALL DONE! (rebooting)"
echolog "*****************************************************************"
echolog

trap '' EXIT

sudo reboot

