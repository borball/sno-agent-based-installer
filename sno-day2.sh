#!/bin/bash
# 
# Helper script to apply the day2 operations on SNO node
# Usage: ./sno-day2.sh config.yaml
#

if [ ! -f "/usr/bin/yq" ] && [ ! -f "/app/vbuild/RHEL7-x86_64/yq/4.25.1/bin/yq" ]; then
  echo "cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if [ ! -f "/usr/local/bin/jinja2" ]; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install jinja2-cli
  pip3 install jinja2-cli[yaml]
fi

usage(){
	echo "Usage: $0 [config.yaml]"
  echo "Example: $0 config-sno130.yaml"
}

if [ $# -lt 1 ]
then
  usage
  exit
fi

if [[ ( $@ == "--help") ||  $@ == "-h" ]]
then 
  usage
  exit
fi


info(){
  printf  $(tput setaf 2)"%-28s %-10s"$(tput sgr0)"\n" "$@"
}

warn(){
  printf  $(tput setaf 3)"%-28s %-10s"$(tput sgr0)"\n" "$@"
}

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
templates=$basedir/templates

config_file=$1;

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
  warn "performance profile:" "disabled"
else
  info "performance profile:" "enabled"
  jinja2 $templates/openshift/day2/performance-profile.yaml.j2 $config_file | oc apply -f -
fi

if [ "false" = "$(yq '.day2.tuned' $config_file)" ]; then
  warn "tuned performance patch:" "disabled"
else
  info "tuned performance patch:" "enabled"
  jinja2 $templates/openshift/day2/performance-patch-tuned.yaml.j2 $config_file | oc apply -f -
fi

if [ "true" = "$(yq '.day2.kdump_tuned' $config_file)" ]; then
  info "tuned kdump settings:" "enabled"
  oc apply -f $templates/openshift/day2/performance-patch-kdump-setting.yaml
else
  warn "tuned kdump settings:" "disabled"
fi

if [ "false" = "$(yq '.day2.cluster_monitor' $config_file)" ]; then
  echo "cluster monitor:" "disabled"
else
  info "cluster monitor:" "enabled"
  oc apply -f $templates/openshift/day2/cluster-monitoring-cm.yaml
fi

if [ "false" = "$(yq '.day2.operator_hub' $config_file)" ]; then
  echo "operator hub:" "disabled"
else
  info "operator hub:" "enabled"
  oc patch operatorhub cluster --type json -p "$(cat $templates/openshift/day2/patchoperatorhub.yaml)"
fi

if [ "false" = "$(yq '.day2.console' $config_file)" ]; then
  warn "openshift console:" "disabled"
else
  info "openshift console:" "enabled"
  oc patch consoles.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/managementState", "value":"Removed"}']
fi

if [ "false" = "$(yq '.day2.network_diagnostics' $config_file)" ]; then
  warn "network diagnostics:" "disabled"
else
  info "network diagnostics:" "enabled"
  oc patch network.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/disableNetworkDiagnostics", "value":true}']
fi

if [ "true" = "$(yq '.day2.ptp_amq' $config_file)" ]; then
  info "ptp amq router:" "enabled"
  oc apply -f -f $templates/openshift/day2/ptp-amq-instance.yaml
else
  warn "ptp amq router:" "disabled"
fi

echo
echo "Done."
