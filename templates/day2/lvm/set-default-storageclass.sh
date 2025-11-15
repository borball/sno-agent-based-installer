#!/bin/bash

config_file=$1
kubeconfig=$2

# Set the default storage class to the LVM storage class
timeout=60
while ! oc --kubeconfig=$kubeconfig get storageclass -o name; do
  timeout=$((timeout - 1))
  if [ $timeout -eq 0 ]; then
    echo "Timeout waiting for storageclass"
    exit 1
  fi
  sleep 1
done
oc --kubeconfig=$kubeconfig patch $(oc --kubeconfig=$kubeconfig get storageclass -o name) -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'
