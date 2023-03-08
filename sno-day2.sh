#!/bin/bash

BASEDIR="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source ${BASEDIR}/config.cfg
CLUSTER_WORKSPACE=$CLUSTERNAME
TEMPLATES=$BASEDIR/templates

export KUBECONFIG=$CLUSTER_WORKSPACE/auth/kubeconfig

oc get clusterversion
oc get nodes
oc get co
oc get operator
oc get csv -A

#day2: performance profile and tuned
envsubst < $TEMPLATES/openshift/day2/performance-profile.yaml.tmpl | oc apply -f -
oc apply -f $TEMPLATES/openshift/day2/performance-patch-tuned.yaml
