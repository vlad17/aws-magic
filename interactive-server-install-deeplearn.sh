#!/bin/bash
#
# Runs deeplearn-server-setup.sh interactively

set -e

if ! [ -d $HOME/aws-instances ]; then
    echo "expecting ~/aws-instances to exist"
    exit 1
fi

instances=$(find $HOME/aws-instances -maxdepth 1 -mindepth 1 -type d -not -name .deleted -printf '%f,')
if [ -z "$instances" ]; then
    echo "no instances in ~/aws-instances available"
    exit 1
fi
instances="${instances::-1}"

read -p "choose instance among {$instances}: " instance
if ! [ -d $HOME/aws-instances/$instance ] || [ -z "$instance" ] ; then
    echo "invalid choice $instance"
    exit 1
fi

if [ $($HOME/aws-instances/$instance/state) != "running" ]; then
    echo "instance $instance not running"
    exit 1
fi

echo "jupyter server password"
passhash=$(python -c "from notebook.auth import passwd; print(passwd())")

read -p "git token file location [~/aws-git-token]: " tokenloc
tokenloc=${tokenloc:-$HOME/aws-git-token}
gittoken=$(cat $tokenloc)
if [ -z "$gittoken" ]; then
    echo "git token invalid"
    exit 1
fi

read -p "git pub key name [aws-$instance]: " keyname
keyname=${keyname:-aws-$instance}

read -p "mujoco license file [~/.mujoco/mjkey.txt]: " mjkey
mjkey=${mjkey:-$HOME/.mujoco/mjkey.txt}
if ! [ -f "$mjkey" ]; then
    echo 'mujoco file not present'
    exit 1
fi

echo
echo "initiating install (this make take ~5 minutes):"

scp -q -oStrictHostKeyChecking=no -i "$HOME/.ssh/aws-key-$instance.pem" "$mjkey" ubuntu@$($HOME/aws-instances/$instance/ip):~/mjkey.txt
script_for_server=$(dirname $(readlink -f "$0"))/server/server-install-deeplearn.sh
scp -q -oStrictHostKeyChecking=no -i "$HOME/.ssh/aws-key-$instance.pem" $script_for_server ubuntu@$($HOME/aws-instances/$instance/ip):~
# https://serverfault.com/questions/414341
# https://unix.stackexchange.com/questions/45941
$HOME/aws-instances/$instance/ssh -t "bash ~/server-install-deeplearn.sh $passhash $gittoken $keyname 2>&1 | tee /tmp/install-out"

