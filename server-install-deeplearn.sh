#!/bin/bash
# Run ./deeplearn-server-setup.sh for usage info

######################################################################
# logging, help, exit functions
######################################################################

usage='Usage: deeplearn-server-setup.sh passhash gittoken keyname
  
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
    echolog "check \$ $1"
    "$1" | tee $(cat - >&3)
}

if [ "$#" -ne "3" ]; then
    echolog "$usage"
    exit 0
fi
passhash="$1"
gittoken="$2"
keyname="$3"

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

######################################################################
# update build tools
######################################################################

echolog -n "updating build tools... "
sudo apt-get update
sudo apt-get --assume-yes upgrade
sudo apt-get --assume-yes install tmux build-essential gcc g++ make binutils
sudo apt-get --assume-yes install software-properties-common git
echolog OK

######################################################################
# nvidia
######################################################################

echolog -n "nvidia cuda... "
if ! (lscudpci | grep -i nvidia ); then
    fail "nvidia device not found"
fi
cd $HOME/install
wget "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_8.0.61-1_amd64.deb" -O cuda-repo-ubuntu1604_8.0.61-1_amd64.deb
sudo dpkg -i cuda-repo-ubuntu1604_8.0.61-1_amd64.deb
sudo apt-get update
sudo apt-get --assume-yes install cuda
sudo modprobe nvidia
export PATH="/usr/local/cuda-8.0/bin:$PATH"
echolog "OK"

check "nvcc --version"
check "nvidia-smi"

echolog -n "cuDNN... "
wget "https://github.com/vlad17/aws-magic/blob/e1bcd69775f10ef6cc30335e4d803775f305c56b/cudnn-8.0-linux-x64-v5.1.tgz?raw=true" -O cudnn-8.0-linux-x64-v5.1.tgz
tar zxf cudnn-8.0-linux-x64-v5.1.tgz
cd cuda
sudo cp lib64/* /usr/local/cuda/lib64/
sudo cp include/* /usr/local/cuda/include/
echolog OK

######################################################################
# tensorflow
######################################################################

echolog "tf deps... "
sudo apt-get --assume-yes install libcupti-dev
sudo apt-get --assume-yes install openjdk-8-jdk
echo "deb [arch=amd64] http://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list
curl https://bazel.build/bazel-release.pub.gpg | sudo apt-key add -
sudo apt-get update
sudo apt-get --assume-yes install bazel
sudo apt-get --assume-yes install python3-numpy python3-dev python3-pip python3-wheel
echolog OK

echolog -n "tensorflow... "
cd
mkdir -p dev
cd dev
git clone https://github.com/tensorflow/tensorflow
cd tensorflow
git checkout r1.2
# Per https://developer.nvidia.com/cuda-gpus
# p2 uses Tesla K80, which is 3.7 compute capability
# g3 uses Tesla M60, which is 5.2
# Compile TensorFlow with both
gpus="3.7,5.2" # TODO Move
printf "\n\ny\n\n\n\n\n\ny\n\n\ny\n\n\n\n\n\n\n${gpus}\n" | ./configure
bazel build --config=opt --config=cuda //tensorflow/tools/pip_package:build_pip_package 
bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg
tfwhl=$(ls -d /tmp/tensorflow_pkg/tensorflow*.whl)
echolog OK

######################################################################
# python
######################################################################

echolog "anaconda... "
cd $HOME/install
anacondaURL="https://repo.continuum.io/archive/Anaconda3-4.4.0-Linux-x86_64.sh"
wget "$anacondaURL" -O Anaconda3-4.4.0-Linux-x86_64.sh
chmod +x Anaconda3-4.4.0-Linux-x86_64.sh
./Anaconda3-4.4.0-Linux-x86_64.sh -f -b -p $HOME/anaconda3
export PATH="$HOME/anaconda3/bin:$PATH"

# below necessary?
pip install $tfwhl
conda update libgcc
check "python -c 'import tensorflow as tf;print(tf.Session().run(tf.constant(\"Hello, TensorFlow!\")))'"

pip install tabulate six keras
echolog OK

######################################################################
# emacs and dotfiles
######################################################################

echolog "emacs and dotfiles... "
sudo apt-get --assume-yes install emacs
sudo add-apt-repository ppa:george-edison55/cmake-3.x -y
sudo apt-get update
sudo apt-get --assume-yes install cmake python-dev
cd ~/dev/
git clone https://github.com/vlad17/misc.git
cd misc/fresh-start
./emacs-install.sh

./config.sh

echo "export PATH=\"\$HOME/anaconda3/bin:\$PATH\"" >> $HOME/.bashrc
echo "export PATH=\"/usr/local/cuda-8.0/bin:\$PATH\"" >> $HOME/.bashrc
source $HOME/.bashrc

######################################################################
# git
######################################################################

echolog "adding public key as $keyname to git... "
title="$keyname"
key=$( cat ~/.ssh/id_rsa.pub )
json=$( printf '{"title": "%s", "key": "%s"}' "$title" "$key" )
curl -u "vlad17:$gittoken" -d "$json" "https://api.github.com/user/keys"
echolog OK

######################################################################
# git
######################################################################

echolog "setting up server jupyter... "
cd
jupyter notebook --generate-config
echo "c.NotebookApp.password = u'"$passhash"'
c.NotebookApp.ip = '*'
c.NotebookApp.open_browser = False" >> $HOME/.jupyter/jupyter_notebook_config.py
echolog OK
echolog "   pass hash: $passhash"


