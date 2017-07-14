#!/bin/bash
#
# Assumes aws cli set up.
# TODO: make this resistant to failure

if [ "$#" -ne 3 ]; then
    echo "Usage: setup-instance.sh ami instanceType name"
    exit 1
fi

ami="$1"
instanceType="$2"
name="$3"

cidr="0.0.0.0/0"

hash aws 2>/dev/null
if [ $? -ne 0 ]; then
    echo >&2 "'aws' command line tool required, but not installed.  Aborting."
    exit 1
fi

if [ -z "$(aws configure get aws_access_key_id)" ]; then
    echo "AWS credentials not configured.  Aborting"
    exit 1
fi

if [ -f $HOME/.ssh/aws-key-$name.pem ]; then
    echo "Old key pair ~/.ssh/aws-key-$name.pem already exists, remove. Aborting"
    exit 1
fi

echo "creating a VPC for our machine"
vpcId=$(aws ec2 create-vpc --cidr-block 10.0.0.0/28 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $vpcId --tags --tags Key=Name,Value=$name
aws ec2 modify-vpc-attribute --vpc-id $vpcId --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id $vpcId --enable-dns-hostnames "{\"Value\":true}"

echo "attaching a public internet gateway to it"
internetGatewayId=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags --resources $internetGatewayId --tags --tags Key=Name,Value=$name-gateway
aws ec2 attach-internet-gateway --internet-gateway-id $internetGatewayId --vpc-id $vpcId

echo "creating a subnet for the local 10.0.0.0/28 addresses"
subnetId=$(aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.0.0/28 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $subnetId --tags --tags Key=Name,Value=$name-subnet

echo "add a route table which send all non-local addresses to the gateway"
routeTableId=$(aws ec2 create-route-table --vpc-id $vpcId --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $routeTableId --tags --tags Key=Name,Value=$name-route-table
routeTableAssoc=$(aws ec2 associate-route-table --route-table-id $routeTableId --subnet-id $subnetId --output text)
aws ec2 create-route --route-table-id $routeTableId --destination-cidr-block "0.0.0.0/0" --gateway-id $internetGatewayId >/dev/null

echo "security: only enable ssh or jupyter over ports 8888-8988 from $cidr"
securityGroupId=$(aws ec2 create-security-group --group-name $name-security-group --description "sg for $name (lone $instanceType VPC)" --vpc-id $vpcId --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $securityGroupId --protocol tcp --port 22 --cidr $cidr
aws ec2 authorize-security-group-ingress --group-id $securityGroupId --protocol tcp --port 8888-8988 --cidr $cidr

echo "create ssh key aws-key-$name.pem"
mkdir -p $HOME/.ssh
aws ec2 create-key-pair --key-name aws-key-$name --query 'KeyMaterial' --output text > $HOME/.ssh/aws-key-$name.pem
chmod 400 $HOME/.ssh/aws-key-$name.pem

echo "Allocating instance $instanceType"
instanceId=$(aws ec2 run-instances --image-id $ami --count 1 --instance-type $instanceType --key-name aws-key-$name --security-group-ids $securityGroupId --subnet-id $subnetId --associate-public-ip-address --block-device-mapping "[ { \"DeviceName\": \"/dev/sda1\", \"Ebs\": { \"VolumeSize\": 128, \"VolumeType\": \"gp2\" } } ]" --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $instanceId --tags --tags Key=Name,Value=$name-gpu-machine
allocAddr=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)

echo "Spinning up instance $instanceId at $allocAddr"
aws ec2 wait instance-running --instance-ids $instanceId

sleep 10 # wait for ssh service to start running too

assocId=$(aws ec2 associate-address --instance-id $instanceId --allocation-id $allocAddr --query 'AssociationId' --output text)
instanceUrl=$(aws ec2 describe-instances --instance-ids $instanceId --query 'Reservations[0].Instances[0].PublicDnsName' --output text)

mkdir -p $HOME/aws-instances/
mkdir -p $HOME/aws-instances/.deleted
CMD_DIR="$HOME/aws-instances/$name"
mkdir -p $CMD_DIR

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

echo "#!/bin/bash

aws ec2 disassociate-address --association-id $assocId
aws ec2 release-address --allocation-id $allocAddr
# volume gets deleted with the instance automatically
aws ec2 terminate-instances --instance-ids $instanceId
aws ec2 wait instance-terminated --instance-ids $instanceId
aws ec2 delete-security-group --group-id $securityGroupId
aws ec2 disassociate-route-table --association-id $routeTableAssoc
aws ec2 delete-route-table --route-table-id $routeTableId
aws ec2 detach-internet-gateway --internet-gateway-id $internetGatewayId --vpc-id $vpcId
aws ec2 delete-internet-gateway --internet-gateway-id $internetGatewayId
aws ec2 delete-subnet --subnet-id $subnetId
aws ec2 delete-vpc --vpc-id $vpcId
aws ec2 delete-key-pair --key-name aws-key-$name
rm -rf $HOME/aws-instances/.deleted/$name # rm previous backup
mv $CMD_DIR $HOME/aws-instances/.deleted
mv $HOME/.ssh/aws-key-$name.pem $HOME/aws-instances/.deleted/$name
" > "$CMD_DIR/delete"
chmod +x "$CMD_DIR/delete"

echo 
echo "DONE, server is ready!"
