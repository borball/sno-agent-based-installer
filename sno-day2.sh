#!/bin/bash

if [ ! -f "/usr/bin/yq" ] && [ ! -f "/app/vbuild/RHEL7-x86_64/yq/4.25.1/bin/yq" ]; then
  echo "cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if [ ! -f "/usr/local/bin/jinja2" ]; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install jinja2-cli
  pip3 install jinja2-cli[yaml]
fi

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
templates=$basedir/templates

config_file=$1; shift
if [ -z "$config_file" ]
then
  config_file=config.yaml
fi

cluster_name=$(yq '.cluster.name' $config_file)
cluster_workspace=$cluster_name
export KUBECONFIG=$cluster_workspace/auth/kubeconfig

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
echo
echo "------------------------------------------------"
echo "Applying day2 operations...."
echo
jinja2 $templates/openshift/day2/performance-profile.yaml.j2 $config_file | oc apply -f -
oc apply -f $templates/openshift/day2/performance-patch-tuned.yaml

oc apply -f $templates/openshift/day2/cluster-monitoring-cm.yaml
oc patch operatorhub cluster --type json -p "$(cat $templates/openshift/day2/patchoperatorhub.yaml)"
oc patch consoles.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/managementState", "value":"Removed"}']
oc patch network.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/disableNetworkDiagnostics", "value":true}']
echo
echo "Done."
