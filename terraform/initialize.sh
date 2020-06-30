#!/bin/bash

# Initialize Terraform plugins
terraform init

# Generate a new key pair
mkdir -p ./.ssh
ssh-keygen -t rsa -b 4096 -C ubuntu -N '' -f ./.ssh/id_rsa <<< y