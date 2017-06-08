#!/bin/bash

set -eux

bosh-cli deployments --json \
  | jq -r --arg version $(cat ubuntu-stemcell/version) \
  '[.Tables | .[0].Rows[] | select (.stemcell_s | contains($version) | not) | .name] | join(", ")' \
  > message/message.txt
