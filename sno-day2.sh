#!/bin/bash

BASEDIR="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source ${BASEDIR}/config.cfg
CLUSTER_WORKSPACE=$CLUSTERNAME
TEMPLATES=$BASEDIR/templates

export KUBECONFIG=$CLUSTER_WORKSPACE/auth/kubeconfig

oc get clusterversion
echo
oc get nodes
echo
oc get co
echo
oc get operator
echo
oc get csv -A
echo

#day2: performance profile and tuned
envsubst < $TEMPLATES/openshift/day2/performance-profile.yaml.tmpl | oc apply -f -
oc apply -f $TEMPLATES/openshift/day2/performance-patch-tuned.yaml

oc apply -f $TEMPLATES/openshift/day2/cluster-monitoring-cm.yaml
oc patch operatorhub cluster --type json -p "$(cat $TEMPLATES/openshift/day2/patchoperatorhub.yaml)"
oc patch consoles.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/managementState", "value":"Removed"}']
oc patch network.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/disableNetworkDiagnostics", "value":true}']
