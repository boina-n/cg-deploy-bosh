#!/bin/bash

set -e -u

bosh-cli -n --ca-cert ${BOSH_CACERT} alias-env env

spruce merge bosh-config/cloud-config.yml > cloud-config-merged.yml

bosh-cli update-cloud-config cloud-config-merged.yml
