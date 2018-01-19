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
HAS_GPU="true"
DOCKER_IMAGE="vlad17/deep-learning:tf-gpu-ubuntu"
if ! (lspci | grep -i nvidia ); then
    HAS_GPU="false"
    DOCKER_IMAGE="vlad17/deep-learning:tf-cpu-ubuntu"
fi
echolog OK
echolog "HAS_GPU = $HAS_GPU"

######################################################################
# build deps
######################################################################

echolog -n "updating build tools... "
sudo apt-get update
# below line isn't necessary, apparently, but that might not hold forever
# sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --force-yes
sudo apt-get --assume-yes --no-install-recommends install \
     tmux software-properties-common git \
     apt-transport-https ca-certificates curl build-essential htop dkms
wget --no-verbose https://raw.githubusercontent.com/vlad17/misc/master/fresh-start/.tmux.conf -O .tmux.conf
echolog OK

if [ "$HAS_GPU" = true ] ; then
  echolog -n "nvidia drivers... "
  # per https://github.com/openai/gym/issues/247 we need to manually install with no OpenGL
  # if we didn't need to mess with nvidia flags the following would be the least hacky solution
  # for installing the most recent drivers
  # sudo apt-key adv --fetch-keys "http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub"
  # sudo sh -c 'echo "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64 /" > /etc/apt/sources.list.d/cuda.list'
  # sudo apt-get --assume-yes --no-install-recommends install cuda-drivers
  cd install
  driver_http="http://us.download.nvidia.com/XFree86/Linux-x86_64/384.98/NVIDIA-Linux-x86_64-384.98.run"
  wget --no-verbose $driver_http -O nvidia.run
  sudo /bin/bash nvidia.run --no-opengl-files --silent --dkms
  cuda_http="https://developer.nvidia.com/compute/cuda/9.0/Prod/local_installers/cuda_9.0.176_384.81_linux-run"
  wget --no-verbose  $cuda_http -O cuda-run
  sudo /bin/bash cuda-run --override --no-opengl-libs --silent
  cd
  echolog OK

  check "nvidia-modprobe"
  check "cat /proc/driver/nvidia/version"
fi

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

if [ "$HAS_GPU" = true ] ; then
  echolog -n "nvidia-docker... "
  wget --no-verbose  -P /tmp "https://github.com/NVIDIA/nvidia-docker/releases/download/v1.0.1/nvidia-docker_1.0.1-1_amd64.deb"
  sudo dpkg -i /tmp/nvidia-docker*.deb && rm /tmp/nvidia-docker*.deb
  echolog OK

  check "sudo nvidia-docker run --rm nvidia/cuda nvidia-smi"
fi

DOCKER="docker"
if [ "$HAS_GPU" = true ] ; then
    DOCKER="nvidia-docker"
fi


######################################################################
# prepared image
######################################################################

echolog -n "pull in prepared docker image, launch it... "
cd

echo '#!/bin/bash
tostop=$('"$DOCKER"' ps -q)
if [ -n "$tostop" ]; then
  echo "stopping:"
  sudo '"$DOCKER"' stop $(docker ps -q)
fi
echo "starting:"
sudo '"$DOCKER"' run --restart=unless-stopped --shm-size=100GB --mount source=docker-home,destination=/home/mluser,type=volume --publish 8888:8888 --publish 6006:6006 --tty --interactive --detach --detach-keys="ctrl-@" '"$DOCKER_IMAGE"'
' > restart-container.sh
chmod +x restart-container.sh
./restart-container.sh

echo '#!/bin/bash
image=$(sudo '"$DOCKER"' ps | grep -v "CONTAINER ID" | head -1 | cut -f1 -d" ")
if [ -z "$image" ]; then
   echo error: docker not live
   exit 1
fi
echo $image
' > current-image.sh
chmod +x current-image.sh
image=$(./current-image.sh)

echolog OK

check "sudo $DOCKER exec $($HOME/current-image.sh) whoami"
check "sudo $DOCKER exec $($HOME/current-image.sh) python -c 'import tensorflow as tf;print(tf.Session().run(tf.constant(\"Hello, TensorFlow! \")))'"
# three layers of quote-nesting, bear with me...
check "sudo $DOCKER exec $($HOME/current-image.sh)"' /bin/bash -c "xvfb-run -a -s \"-screen 0 1400x900x24 +extension RANDR\" -- python -c '"'"'
import gym
from gym import wrappers
env = gym.make(\"CartPole-v0\")
env = wrappers.Monitor(env, \"/tmp/cartpole-experiment-1\")
for i_episode in range(20):
    observation = env.reset()
    for t in range(100):
        env.render()
        action = env.action_space.sample()
        observation, reward, done, info = env.step(action)
        if done:
            print(\"Episode finished after {} timesteps\".format(t+1))
            break
'"'\""

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
sudo $DOCKER cp $HOME/.ssh $image:/home/mluser
echolog OK

######################################################################
# jupyter
######################################################################

echolog -n "setting up server jupyter... "
echo "c.NotebookApp.password = u'"$passhash"'
c.NotebookApp.ip = '*'
c.NotebookApp.open_browser = False" > .jupytercfgadd

sudo $DOCKER cp $HOME/.jupytercfgadd $image:/home/mluser
sudo $DOCKER exec $image /bin/bash -c "cat /home/mluser/.jupytercfgadd >> /home/mluser/.jupyter/jupyter_notebook_config.py"

echolog OK

######################################################################
# mujoco
######################################################################

if [ -f $HOME/mjkey.txt ]; then
    echolog -n "setting up mujoco... "
    sudo $DOCKER cp $HOME/mjkey.txt $image:/home/mluser
    sudo $DOCKER exec $image /bin/bash -c "mkdir /home/mluser/.mujoco/ && mv /home/mluser/mjkey.txt /home/mluser/.mujoco"
    sudo $DOCKER exec $image /bin/bash -c "wget https://www.roboti.us/download/mjpro131_linux.zip && unzip mjpro131_linux.zip -d /home/mluser/.mujoco"
    sudo $DOCKER exec $image /bin/bash -c "wget https://www.roboti.us/download/mjpro150_linux.zip && unzip mjpro150_linux.zip -d /home/mluser/.mujoco"
    echolog OK
fi

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

######################################################################
# convenience scripts
######################################################################

echo '#!/bin/bash

set -e
image=$($HOME/current-image.sh)
cols=$(tput cols)
rows=$(tput lines)
sudo '"$DOCKER"' exec --detach-keys="ctrl-q,ctrl-q" --user mluser --interactive --tty $image /bin/bash -i -c "
stty cols $cols rows $rows
exec /bin/bash -i -l
"
' > docker-up.sh
chmod +x docker-up.sh

echolog
echolog "*****************************************************************"
echolog "server-install-deeplearn.sh: ALL DONE! (rebooting)"
echolog "*****************************************************************"
echolog

trap '' EXIT

sudo reboot

