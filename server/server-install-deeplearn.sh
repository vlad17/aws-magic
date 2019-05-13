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

Installs various stuff on the server:
 - if GPU present, nvidia drivers
 - (nvidia-)docker
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
    bash -c "$1" 2>&1 | tee $(cat - >&3)
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

if [ "$distrib" != "Ubuntu" ] ; then
    fail "expected Ubuntu, got $distrib $release"
else
    echolog OK
fi

echolog -n "verifying nvidia... "
HAS_GPU="true"
if ! (lspci | grep -i nvidia ); then
    HAS_GPU="false"
fi
echolog OK
echolog "HAS_GPU = $HAS_GPU"

######################################################################
# checking ami
######################################################################

echolog -n "checking ami... "

check "whoami"
check "nvcc --version"
check "source activate pytorch_p36 && python -c 'import torch; print(torch.backends.cudnn.version(), torch.backends.cudnn.enabled)'"
check "emacs --version"

echolog OK

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
echolog OK

######################################################################
# jupyter
######################################################################

echolog -n "setting up server jupyter... "

check "test -f .jupyter/jupyter_notebook_config.py "

echo "c.NotebookApp.password = u'"$passhash"'
c.NotebookApp.ip = '*'
c.NotebookApp.open_browser = False" >> .jupyter/jupyter_notebook_config.py

echolog OK

######################################################################
# dotfiles
######################################################################

echolog -n "cloning dotfiles repo... "
test -d misc || GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone git@github.com:vlad17/misc.git
echolog OK

echolog -n "installing dotfiles..."
misc/fresh-start/emacs-install.sh
misc/fresh-start/config.sh
sudo apt-get --assume-yes --no-install-recommends install tmux cmake build-essential htop
echolog OK

######################################################################
# login greeting
######################################################################

echolog -n "updating login greeting... "
for i in $(find /etc/update-motd.d/ -type f -printf '%f\n' | egrep -v '00'); do
    sudo rm -f /etc/update-motd.d/$i
done
if [ "$HAS_GPU" = true ] ; then
    sudo ln -s  /usr/bin/nvidia-smi /etc/update-motd.d/15-nvidia-smi
fi
echolog "OK"

echolog
echolog "*****************************************************************"
echolog "server-install-deeplearn.sh: ALL DONE! (rebooting)"
echolog "*****************************************************************"
echolog

trap '' EXIT
