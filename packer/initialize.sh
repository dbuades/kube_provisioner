#!/bin/bash

# Generate a new key pair
mkdir -p ./.ssh
ssh-keygen -t rsa -b 4096 -C packer -N '' -f ./.ssh/packer <<< y
KEY=$(<./.ssh/packer.pub)

# Replace the placeholder ${id_rsa.pub} by the actual public key
sed "s%\${id_rsa.pub}%$KEY%" ./cloud-init/user-data_template > ./cloud-init/user-data