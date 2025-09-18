#!/bin/bash

# use to set env variables for 60-create-lvs-mc.yaml.j2

config_file=$1

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

if [[ -z $config_file ]]; then
  echo "Usage: $0 <config_file>"
  exit 1
fi

if [[ ! -f $config_file ]]; then
  echo "Config file $config_file not found"
  exit 1
fi

export CREATE_LVS_FOR_SNO=$(cat $basedir/create_lvs_for_lso.sh |base64 -w0)
export DISK=$(yq '.day1.operators.local-storage.provision.data.disk_by_path' $config_file)
export LVS=$(yq ".day1.operators.local-storage.provision.data.partitions|to_entries|map(.value + \"x\" + .key)|join(\" \")" $config_file)

