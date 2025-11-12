#!/bin/bash

ID=${1}
LOGVOLS=${2}
set -ex

help()
{
  echo "Run the script as follows: ${0} <serial_number> <string of LVs to create>"
  echo Example: ${0} S123NC4T567890 \'"1x64m" "2x100m" "3x1g" "2x2g" "1x4g" "2x5g" "1x15g" "1x30g"\'
}

checks()
{
  if [[ $(id -u) != "0" ]]
  then
    echo "This script must be run as root"
    exit 1
  fi

  if [[ ${DEVICE} == "/dev/disk/by-id/nvme-" ]]
  then
    echo "You must provide a device"
    help
    exit 1
  fi

  if [[ -z ${LOGVOLS} ]]
  then
    echo "You must describe the LVs you wish to create"
    help
    exit 1
  fi

  if [[ ! -b ${DEVICE} ]]
  then
    echo "${DEVICE} not found"
    exit 1
  fi
}

preparePV()
{
  if [[ $(pvdisplay ${DEVICE} 2>/dev/null| wc -l) == "0" ]]
  then
    echo "Initializing PV"
    pvcreate ${DEVICE}
  fi
}

prepareVG()
{
  if [[ $(vgdisplay autopart 2>/dev/null | wc -l) == "0" ]]
  then
    echo "Initializing VG"
    vgcreate autopart ${DEVICE}
  fi
}

createLV()
{
  SIZE=${1}
  VG=${2}
  LAST_LV=$(lvs autopart --no-headings --separator , 2>/dev/null | awk -F "," '{print $1}' | awk -F "lv_" '{print $2}' | sort -n | tail -1)
  NEW_LV=$((LAST_LV + 1))
  lvcreate -W y --yes -L ${SIZE} --name lv_${NEW_LV} ${VG}
}

getDev()
{
  DEVICE=/dev/disk/by-path/$ID
  echo $DEVICE
}

main()
{

  getDev
  checks
  preparePV
  prepareVG
  for lv in $LOGVOLS; do
    NUM_LVS=$(echo $lv | sed -e 's/\"//g' | awk -Fx '{print $1}')
    SIZE_LVS=$(echo $lv | sed -e 's/\"//g' | awk -Fx '{print $2}')
    CURRENT_LVS=$(lvdisplay -c -S lv_size=${SIZE_LVS} | wc -l)
    if [[ $CURRENT_LVS -lt $NUM_LVS ]]; then
      echo creating $SIZE_LVS PVs
      for (( part=$CURRENT_LVS+1; part<=${NUM_LVS}; part++ )); do
        createLV ${SIZE_LVS} autopart
      done
    fi
  done

}

main
