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

read -p "git token file location [~/aws-git-token]: " tokenloc
tokenloc=${tokenloc:-$HOME/aws-git-token}
gittoken=$(cat $tokenloc)
if [ -z "$gittoken" ]; then
    echo "git token invalid"
    exit 1
fi

read -p "git pub key name [aws-$instance]: " keyname
keyname=${keyname:-aws-$instance}

read -p "install deep learning deps over regular deps (y/N)?" yn
case "$yn" in
    [Yy]* ) INSTALL_DEEP="true" ;;
    * ) INSTALL_DEEP="false" ;;
esac

if $INSTALL_DEEP ; then
    echo "jupyter server password"
    passhash=$(python -c "from notebook.auth import passwd; print(passwd())")

    script_for_server=$(dirname $(readlink -f "$0"))/server/server-install-deeplearn.sh
    server_invok="~/server-install-deeplearn.sh $passhash $gittoken $keyname"
else
    read -p "pre-kubernetes install script [~/bin/pre-kubernetes.sh]: " prek
    prek=${prek:-$HOME/bin/pre-kubernetes.sh}
    scp -q -oStrictHostKeyChecking=no -i "$HOME/.ssh/aws-key-$instance.pem" "$prek" ubuntu@$($HOME/aws-instances/$instance/ip):"~/pre-kubernetes.sh"

    echo 'copying ~/.aws to server'
    scp -r -q -oStrictHostKeyChecking=no -i "$HOME/.ssh/aws-key-$instance.pem" "$HOME/.aws" ubuntu@$($HOME/aws-instances/$instance/ip):~
    
    script_for_server=$(dirname $(readlink -f "$0"))/server/server-install-dev.sh
    server_invok="~/server-install-dev.sh $gittoken $keyname"
fi

echo "initiating install (this may take ~5 minutes):"

# TODO wait for ssh here



scp -q -oStrictHostKeyChecking=no -i "$HOME/.ssh/aws-key-$instance.pem" $script_for_server ubuntu@$($HOME/aws-instances/$instance/ip):~
# https://serverfault.com/questions/414341
# https://unix.stackexchange.com/questions/45941
CMD_DIR="$HOME/aws-instances/$instance"

echo '#!/bin/bash
set -e
if [ -z "$1" ]; then
   echo missing src "(location copying from docker)"
   exit 1
fi

if [ -z "$2" ]; then
   echo missing dst "(location copying to on pc)"
   exit 1
fi

tempdir=$('"$CMD_DIR/ssh"' mktemp -d)
'"$CMD_DIR/ssh"' sudo docker cp '"'"'$(~/current-image.sh)'"'"'":$1" $tempdir
scp -r -oStrictHostKeyChecking=no -i '"$HOME/.ssh/aws-key-$instance.pem ubuntu@$($HOME/aws-instances/$instance/ip)"':"$tempdir/*" $2
'"$CMD_DIR/ssh"' -t sudo rm -rf $tempdir
' > "$CMD_DIR/dockercp"
chmod +x "$CMD_DIR/dockercp"

echo '#!/bin/bash
set -e
if [ -z "$1" ]; then
   echo missing src "(location copying from pc)"
   exit 1
fi

if [ -z "$2" ]; then
   echo missing dst "(location copying to docker)"
   exit 1
fi

tempdir=$('"$CMD_DIR/ssh"' mktemp -d)
scp -r -q -oStrictHostKeyChecking=no -i '"$HOME/.ssh/aws-key-$instance.pem"' "$1" '"ubuntu@$($HOME/aws-instances/$instance/ip)"':"$tempdir"
'"$CMD_DIR/ssh"' sudo docker cp "$tempdir/*" '"'"'$(~/current-image.sh)'"'"'":$2"
'"$CMD_DIR/ssh"' -t sudo rm -rf $tempdir
' > "$CMD_DIR/cpdocker"
chmod +x "$CMD_DIR/cpdocker"

echo '#!/bin/bash
set -e
if [ -z "$1" ]; then
   echo missing src "(location copying from aws)"
   exit 1
fi

if [ -z "$2" ]; then
   echo missing dst "(location copying to on pc)"
   exit 1
fi

scp -r -oStrictHostKeyChecking=no -i '"$HOME/.ssh/aws-key-$instance.pem ubuntu@$($HOME/aws-instances/$instance/ip)"':"$1" "$2"
'"$CMD_DIR/ssh"' -t sudo rm -rf $tempdir
' > "$CMD_DIR/cpfrom"
chmod +x "$CMD_DIR/cpfrom"

echo '#!/bin/bash
set -e
if [ -z "$1" ]; then
   echo missing src "(location copying from aws)"
   exit 1
fi

if [ -z "$2" ]; then
   echo missing dst "(location copying to on pc)"
   exit 1
fi

scp -r -oStrictHostKeyChecking=no -i '"$HOME/.ssh/aws-key-$instance.pem"' "$1" '"ubuntu@$($HOME/aws-instances/$instance/ip)"':"$2"
'"$CMD_DIR/ssh"' -t sudo rm -rf $tempdir
' > "$CMD_DIR/cpto"
chmod +x "$CMD_DIR/cpto"


$CMD_DIR/ssh -t "bash $server_invok 2>&1 | tee /tmp/install-out"

# TODO wait for ssh here
