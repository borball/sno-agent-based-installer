#!/bin/bash

config_file=$1

if [[ -z $config_file ]]; then
  echo "Usage: $0 <config_file>"
  exit 1
fi

if [[ ! -f $config_file ]]; then
  echo "Config file $config_file not found"
  exit 1
fi

export CREATE_LVS_FOR_SNO=$(cat $templates/day1/local-storage/create_lvs_for_lso.sh |base64 -w0)
export DISK=$(yq '.operators.local-storage.provision.disk_by_path' $config_file)
export LVS=$(yq ".operators.local-storage.provision.${partitions_key}|to_entries|map(.value + \"x\" + .key)|join(\" \")" $config_file)
