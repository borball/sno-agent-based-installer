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

echo
echo "------------------------------------------------"
echo "Applying day2 operations...."
echo

if [ "false" = "$(yq '.day2.performance_profile.enabled' $config_file)" ]; then
  echo "performance profile:            disabled"
else
  echo "performance profile:            enabled"
  jinja2 $templates/openshift/day2/performance-profile.yaml.j2 $config_file | oc apply -f -
fi

if [ "false" = "$(yq '.day2.tuned' $config_file)" ]; then
  echo "tune performance patch:         disabled"
else
  echo "tune performance patch:         enabled"
  jinja2 $templates/openshift/day2/performance-profile.yaml.j2 $config_file | oc apply -f -
fi

if [ "false" = "$(yq '.day2.cluster_monitor' $config_file)" ]; then
  echo "cluster monitor:                disabled"
else
  echo "cluster monitor:                enabled"
  oc apply -f $templates/openshift/day2/cluster-monitoring-cm.yaml
fi

if [ "false" = "$(yq '.day2.console' $config_file)" ]; then
  echo "openshift console:              disabled"
else
  echo "openshift console:              enabled"
  oc patch consoles.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/managementState", "value":"Removed"}']
fi

if [ "false" = "$(yq '.day2.network_diagnostics' $config_file)" ]; then
  echo "network diagnostics:            disabled"
else
  echo "network diagnostics:            enabled"
  oc patch network.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/disableNetworkDiagnostics", "value":true}']
fi

echo
echo "Done."
