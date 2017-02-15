#!/bin/bash

set -eu
# http://stackoverflow.com/questions/10768160/ip-address-converter
dec2ip () {
    delim=""
    local ip dec=$@
    for e in {3..0}
    do
        ((octet = dec / (256 ** e) ))
        ((dec -= octet * 256 ** e))
        ip+=$delim$octet
        delim=.
    done
    printf '%s\n' "$ip"
}
ip2dec () {
    local a b c d ip=$@
    IFS=. read -r a b c d <<< "$ip"
    printf '%d\n' "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
}

# these values are merged into the manifest via environment variables instead of using spruce's (( file ))
# because (( file )) doesn't support chomping, and the bosh-io-release-resource adds newlines :(
export RELEASES_BOSH_URL=$(cat bosh-release/url  | tr -d '\n')
export RELEASES_BOSH_SHA1=$(cat bosh-release/sha1  | tr -d '\n')

export RELEASES_BOSH_AWS_CPI_URL=$(cat bosh-aws-cpi-release/url  | tr -d '\n')
export RELEASES_BOSH_AWS_CPI_SHA1=$(cat bosh-aws-cpi-release/sha1  | tr -d '\n')

export STEMCELL_URL=$(cat stemcell/url  | tr -d '\n')
export STEMCELL_SHA1=$(cat stemcell/sha1  | tr -d '\n')

# calcuate ip addresses based on offsets from IaaS provided subnets

# get our vpc address space
VPC_CIDR=$(grep vpc_cidr terraform-state/*.yml | awk '{print $2}')
# amazon dns is always + 2
export AMAZON_DNS=$(dec2ip $(( $(ip2dec ${VPC_CIDR}) + 2)))

# get our subnet address space
PRIVATE_CIDR=$(grep private_subnet_az1_cidr terraform-state/*.yml | awk '{print $2}')

# we want to be 77 off the space
export STATIC_ADDRESS=$(dec2ip $(( $(ip2dec ${PRIVATE_CIDR}) + 77)))

# decrypt the secrets
mkdir -p secrets-decrypted
for f in secrets/*.yml; do
	openssl enc -aes-256-cbc -d -a -pass "pass:${SECRETS_PASSPHRASE}" -in ${f} -out secrets-decrypted/$(basename ${f})
done

# generate the deployment manifest
spruce merge --prune secrets --prune terraform_outputs deploy-bosh/masterbosh/manifest.yml terraform-state/*.yml secrets-decrypted/*.yml > deployment-manifest.yml

# extract the ssh key from our secrets because bosh create-env wants it on the file system :/
# TODO: is there a better way to do this than converting to json + jq?
spruce json secrets-decrypted/*.yml | jq -r .secrets.masterbosh.ssh.private_key > ssh.key

# and deploy it!
set -x
bosh-cli create-env --state=state/*.json deployment-manifest.yml

