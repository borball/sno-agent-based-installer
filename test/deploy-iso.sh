#!/bin/bash

iso_file=$1
# iso_image like http://192.168.58.15/iso/sno130.iso
iso_image=$2

if [ -z "$iso_file" ] || [ -z "$iso_image" ]; then
  echo "Usage: $0 <iso_file> <iso_image>"
  exit 1
fi

if [ ! -f "$iso_file" ]; then
  echo "ISO file $iso_file not found"
  exit 1
fi

iso_name=$(echo $iso_image | awk -F '/' '{print $NF}')
scp $iso_file 192.168.58.15:/var/www/html/iso/$iso_name

echo "ISO deployed to 192.168.58.15:/var/www/html/iso/$iso_name"

