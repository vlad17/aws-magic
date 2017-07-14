#!/bin/bash
#
# This is assuming we're in p2.xlarge with base Ubuntu 16.04

set -e
cd /tmp

# verify os
distrib=$(lsb_release -a 2>/dev/null | grep "Distributor ID" | cut -f2 -d":")
distrib=$(echo $distrib) # remove surrounding whitespace
release=$(lsb_release -a 2>/dev/null | grep "Release" | cut -f2 -d":")
release=$(echo $release)

if [ "$distrib" != "Ubuntu" ] || [ "$release" != "16.04" ]; then
    echo "expected Ubuntu 16.04, got $distrib $release"
    echo "***** aborting *****"
    exit 1
fi

# anaconda
anacondaURL="https://repo.continuum.io/archive/Anaconda3-4.4.0-Linux-x86_64.sh"
anacondaTrueMD5="50f19b935dae7361978a04d9c7c355cd"
wget "$anacondaURL" -O Anaconda3-4.4.0-Linux-x86_64.sh
chmod +x Anaconda3-4.4.0-Linux-x86_64.sh
./Anaconda3-4.4.0-Linux-x86_64.sh -f -b -p $HOME/anaconda3
echo "export PATH=\"\$HOME/anaconda3/bin:\$PATH\"" >> $HOME/.bashrc

# ensure system is updated and has basic build tools
sudo apt-get update
sudo apt-get --assume-yes upgrade
sudo apt-get --assume-yes install tmux build-essential gcc g++ make binutils
sudo apt-get --assume-yes install software-properties-common

# nvidia drivers, cuda
if ! (lspci | grep -i nvidia ); then
    echo "nvidia device not found"
    echo "***** aborting *****"
    exit 1
fi
wget "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_8.0.61-1_amd64.deb" -O cuda-repo-ubuntu1604_8.0.61-1_amd64.deb
sudo dpkg -i cuda-repo-ubuntu1604_8.0.61-1_amd64.deb
sudo apt-get update
sudo apt-get --assume-yes install cuda
sudo modprobe nvidia
echo "export PATH=\"/usr/local/cuda-8.0/bin:\$PATH\"" >> $HOME/.bashrc
source $HOME/.bashrc
nvcc --version
nvidia-smi

# cuDNN

wget "https://drive.google.com/uc?export=download&confirm=ui_s&id=0B-_3sa1fcBCsSThHNXNON092c2c" -O cudnn-8.0-linux-x64-v5.1.tgz
tar zxf cudnn-8.0-linux-x64-v5.1.tgz
