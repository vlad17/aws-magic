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
if ! [ -d $HOME/aws-instances/$instance ]; then
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

read -p "git pub key name [aws-$instance]: " keyname
keyname=${keyname:-aws-$instance}

echo
echo "initiating install (this make take ~5 minutes):"

# https://serverfault.com/questions/414341
# https://unix.stackexchange.com/questions/45941
$HOME/aws-instances/$instance/ssh "nohup sh -c \"curl -s https://raw.githubusercontent.com/vlad17/aws-magic/master/server-install-deeplearn.sh | bash -s $passhash $gittoken $keyname\" > /tmp/install-out & tail -f /tmp/install-out | sed '/^server-install-deeplearn.sh: ALL DONE!$/ q'"
echo "*****************************************************************"
echo

