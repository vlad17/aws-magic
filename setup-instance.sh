#!/bin/bash
#
# Assumes aws cli set up.

if [ "$#" -ne 3 ]; then
    echo "Usage: setup-instance.sh ami instanceType name"
    echo "See aws-magic/README.md for description"
    exit 1
fi

set -e

ami="$1"
instanceType="$2"
name="$3"
cidr_all="0.0.0.0/0"

if ! which aws; then
    echo "'aws' command line tool required, but not installed.  Aborting."
    exit 1
fi

if [ -z "$(aws configure get aws_access_key_id)" ]; then
    echo "AWS credentials not configured.  Aborting"
    exit 1
fi

if [ -z "$name" ]; then
    echo "name that is specified must be non-null"
    exit 1
fi

if [ -d "$HOME/aws-instances/$name" ]; then
    echo "~/aws-instances/$name already exists"
    echo "delete it (and corresponding instances) first."
    echo "Aborting"
    exit 1
fi

if [ -f $HOME/.ssh/aws-key-$name.pem ]; then
    echo "Old key pair ~/.ssh/aws-key-$name.pem already exists, remove it first."
    echo "Aborting"
    exit 1
fi

mkdir -p $HOME/aws-instances/
mkdir -p $HOME/aws-instances/.deleted

# generates the cleanup function, given what is defined in the current shell
function generate_cleanup {
    echo '#!/bin/bash'
    echo
    if [ -n "$assocId" ]; then
        echo echo dissociating $assocId external IP from cloud machine
        echo aws ec2 disassociate-address --association-id $assocId
    fi
    if [ -n "$allocAddr" ]; then
        echo echo releasing external IP $allocAddr
        echo aws ec2 release-address --allocation-id $allocAddr
    fi
    if [ -n "$instanceId" ]; then
        echo echo terminating instance $instanceId
        echo aws ec2 terminate-instances --instance-ids $instanceId
        echo aws ec2 wait instance-terminated --instance-ids $instanceId
    fi
    if [ -n "$securityGroupId" ]; then
        echo echo deleting security group $securityGroupId
        echo aws ec2 delete-security-group --group-id $securityGroupId
    fi
    if [ -n "$routeTableAssoc" ]; then
        echo echo dissociating route table $routeTableAssoc from subnet
        echo aws ec2 disassociate-route-table --association-id $routeTableAssoc
    fi
    if [ -n "$routeTableId" ]; then
        echo echo deleting route table $routeTableId
        echo aws ec2 delete-route-table --route-table-id $routeTableId
    fi
    if [ -n "$internetGatewayId" ]; then
        echo echo detaching and deleting internet gateway $internetGatewayId from vpc $vpcId
        echo aws ec2 detach-internet-gateway --internet-gateway-id $internetGatewayId --vpc-id $vpcId
        echo aws ec2 delete-internet-gateway --internet-gateway-id $internetGatewayId
    fi
    if [ -n "$subnetId" ]; then
        echo echo deleting subnet $subnetId
        echo aws ec2 delete-subnet --subnet-id $subnetId
    fi
    if [ -n "$vpcId" ]; then
        echo echo deleting vpc $vpc
        echo aws ec2 delete-vpc --vpc-id $vpcId
    fi
    echo "echo creating backup directory ~/aws-instances/.deleted/$name"
    echo rm -rf $HOME/aws-instances/.deleted/$name
    echo mkdir -p $HOME/aws-instances/
    echo mkdir -p $HOME/aws-instances/.deleted/
    echo mkdir -p $HOME/aws-instances/.deleted/$name
    
    if [ -f "$HOME/.ssh/aws-key-$name.pem" ]; then
        echo echo deleting key pair for $name
        echo aws ec2 delete-key-pair --key-name aws-key-$name
        echo mv $HOME/.ssh/aws-key-$name.pem $HOME/aws-instances/.deleted/$name
    fi
    if [ -d "$CMD_DIR" ]; then
        echo echo "moving ~/aws-instances/$name to backup location"
        echo cp -rf $CMD_DIR $HOME/aws-instances/.deleted
        echo rm -rf $CMD_DIR
    fi    
}

tmpout=$(mktemp)
function cleanup {
    # generate cleanup given currently-defined variables
    cleanup_script=$(generate_cleanup)
    bash -c "$cleanup_script"
    if [ -f "$tmpout" ]; then
        rm -f "$tmpout"
    fi
    trap '' EXIT SIGINT SIGTERM
}
trap cleanup EXIT SIGINT SIGTERM

echo "creating ~/aws-instances/$name directory"
CMD_DIR="$HOME/aws-instances/$name"
mkdir -p $CMD_DIR

echo "creating ssh key aws-key-$name.pem"
mkdir -p $HOME/.ssh
aws ec2 create-key-pair --key-name aws-key-$name --query 'KeyMaterial' --output text >$HOME/.ssh/aws-key-$name.pem
chmod 400 $HOME/.ssh/aws-key-$name.pem

echo "creating a VPC for cloud machine"
aws ec2 create-vpc --cidr-block 10.0.0.0/28 --query 'Vpc.VpcId' --output text >$tmpout
vpcId=$(cat $tmpout)

aws ec2 create-tags --resources $vpcId --tags --tags Key=Name,Value=$name
aws ec2 modify-vpc-attribute --vpc-id $vpcId --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id $vpcId --enable-dns-hostnames "{\"Value\":true}"

echo "attaching a public internet gateway to it"
aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text >$tmpout
internetGatewayId=$(cat $tmpout)
aws ec2 create-tags --resources $internetGatewayId --tags --tags Key=Name,Value=$name-gateway
aws ec2 attach-internet-gateway --internet-gateway-id $internetGatewayId --vpc-id $vpcId

echo "creating a subnet for the local 10.0.0.0/28 addresses"
aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.0.0/28 --query 'Subnet.SubnetId' --output text >$tmpout
subnetId=$(cat $tmpout)
aws ec2 create-tags --resources $subnetId --tags --tags Key=Name,Value=$name-subnet

echo "add a route table which send all non-local addresses to the gateway"
aws ec2 create-route-table --vpc-id $vpcId --query 'RouteTable.RouteTableId' --output text >$tmpout
routeTableId=$(cat $tmpout)
aws ec2 create-tags --resources $routeTableId --tags --tags Key=Name,Value=$name-route-table
aws ec2 associate-route-table --route-table-id $routeTableId --subnet-id $subnetId --output text >$tmpout
routeTableAssoc=$(cat $tmpout)
aws ec2 create-route --route-table-id $routeTableId --destination-cidr-block "0.0.0.0/0" --gateway-id $internetGatewayId >/dev/null

echo "security: only enable ssh or jupyter over ports 6006,8888-8898 from $cidr_all"
aws ec2 create-security-group --group-name $name-security-group --description "sg for $name (lone $instanceType VPC)" --vpc-id $vpcId --query 'GroupId' --output text >$tmpout
securityGroupId=$(cat $tmpout)
aws ec2 authorize-security-group-ingress --group-id $securityGroupId --protocol tcp --port 22 --cidr $cidr_all
aws ec2 authorize-security-group-ingress --group-id $securityGroupId --protocol tcp --port 8888-8898 --cidr $cidr_all
aws ec2 authorize-security-group-ingress --group-id $securityGroupId --protocol tcp --port 6006 --cidr $cidr_all

echo "Allocating instance $instanceType"
aws ec2 run-instances --image-id $ami --count 1 --instance-type $instanceType --key-name aws-key-$name --security-group-ids $securityGroupId --subnet-id $subnetId --associate-public-ip-address --block-device-mapping "[ { \"DeviceName\": \"/dev/sda1\", \"Ebs\": { \"VolumeSize\": 128, \"VolumeType\": \"gp2\" } } ]" --query 'Instances[0].InstanceId' --output text >$tmpout
instanceId=$(cat $tmpout)
aws ec2 create-tags --resources $instanceId --tags --tags Key=Name,Value=$name
aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text >$tmpout
allocAddr=$(cat $tmpout)

echo "Spinning up instance $instanceId at $allocAddr"
aws ec2 wait instance-running --instance-ids $instanceId

sleep 10 # wait for ssh service to start running too

aws ec2 associate-address --instance-id $instanceId --allocation-id $allocAddr --query 'AssociationId' --output text >$tmpout
assocId=$(cat $tmpout)
aws ec2 describe-instances --instance-ids $instanceId --query 'Reservations[0].Instances[0].PublicDnsName' --output text >$tmpout
instanceUrl=$(cat $tmpout)

echo
echo "$CMD_DIR/start  will start up $instanceType with ami $ami"
echo "$CMD_DIR/ip     will print the public IP of the running instance"
echo "$CMD_DIR/ssh    will ssh into the running instance"
echo "$CMD_DIR/stop   will stop the currently-running instance"
echo "$CMD_DIR/state  will describe the current state of the instance"
echo "$CMD_DIR/delete will stop the instance and delete all metadata about the instance from both your computer and AWS"

echo "#!/bin/bash

aws ec2 start-instances --instance-ids $instanceId
aws ec2 wait instance-running --instance-ids $instanceId
" > "$CMD_DIR/start"
chmod +x "$CMD_DIR/start"

echo "#!/bin/bash

aws ec2 describe-instances --filters \"Name=instance-id,Values=$instanceId\" --query \"Reservations[0].Instances[0].PublicIpAddress\"
" > "$CMD_DIR/ip"
chmod +x "$CMD_DIR/ip"

echo "#!/bin/bash

ssh  -oStrictHostKeyChecking=no -i $HOME/.ssh/aws-key-$name.pem ubuntu@\$($CMD_DIR/ip) \"\$@\"
" > "$CMD_DIR/ssh"
chmod +x "$CMD_DIR/ssh"

echo "#!/bin/bash

aws ec2 stop-instances --instance-ids $instanceId
" > "$CMD_DIR/stop"
chmod +x "$CMD_DIR/stop"

echo "#!/bin/bash

aws ec2 describe-instances --instance-ids $instanceId --query \"Reservations[0].Instances[0].State.Name\"
" > "$CMD_DIR/state"
chmod +x "$CMD_DIR/state"

generate_cleanup > "$CMD_DIR/delete"
chmod +x "$CMD_DIR/delete"

trap '' EXIT SIGINT SIGTERM

echo 
echo "DONE, server is ready!"

