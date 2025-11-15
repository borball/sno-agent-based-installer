#!/bin/bash

config_file=$1
kubeconfig=$2

oc --kubeconfig=$kubeconfig patch network.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/disableNetworkDiagnostics", "value":true}']
