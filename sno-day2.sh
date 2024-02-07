#!/bin/bash
# 
# Helper script to apply the day2 operations on SNO node
# Usage: ./sno-day2.sh config.yaml
#

if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
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
  printf  $(tput setaf 2)"%-60s %-10s"$(tput sgr0)"\n" "$@"
}

warn(){
  printf  $(tput setaf 3)"%-60s %-10s"$(tput sgr0)"\n" "$@"
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

ocp_release=$(oc version -o json|jq -r '.openshiftVersion')
ocp_y_version=$(echo $ocp_release | cut -d. -f 1-2)

echo
echo "------------------------------------------------"
echo "Applying day2 operations...."
echo

if [ "false" = "$(yq '.day2.performance_profile.enabled' $config_file)" ]; then
  warn "performance profile:" "disabled"
else
  info "performance profile:" "enabled"
  if [ "4.12" = $ocp_y_version ] ||  [ "4.13" = $ocp_y_version ]; then
    jinja2 $templates/day2/performance-profile-$ocp_y_version.yaml.j2 $config_file | oc apply -f -
  else
    #4.14+
    jinja2 $templates/day2/performance-profile.yaml.j2 $config_file | oc apply -f -
  fi
fi

echo 

if [ "false" = "$(yq '.day2.tuned_profile.enabled' $config_file)" ]; then
  warn "tuned performance patch:" "disabled"
else
  info "tuned performance patch:" "enabled"
  jinja2 $templates/day2/performance-patch-tuned.yaml.j2 $config_file | oc apply -f -
fi

echo 

if [ "true" = "$(yq '.day2.tuned_profile.kdump' $config_file)" ]; then
  info "tuned kdump settings:" "enabled"
  oc apply -f $templates/day2/performance-patch-kdump-setting.yaml
else
  warn "tuned kdump settings:" "disabled"
fi

echo 

if [ "false" = "$(yq '.day2.cluster_monitor_tuning' $config_file)" ]; then
  warn "cluster monitor tuning:" "disabled"
else
  info "cluster monitor tuning:" "enabled"
  if [ "4.12" = $ocp_y_version ] ||  [ "4.13" = $ocp_y_version ]; then
    oc apply -f $templates/day2/cluster-monitoring-cm.yaml
  else
    oc apply -f $templates/day2/cluster-monitoring-cm-4.14.yaml
  fi
fi

echo 

if [ "false" = "$(yq '.day2.operator_hub_tuning' $config_file)" ]; then
  warn "operator hub tuning:" "disabled"
else
  info "operator hub tuning:" "enabled"
  oc patch operatorhub cluster --type json -p "$(cat $templates/day2/patchoperatorhub.yaml)"
fi

echo 

if [ "false" = "$(yq '.day2.disable_network_diagnostics' $config_file)" ]; then
  warn "network diagnostics:" "enabled"
else
  info "network diagnostics:" "disabled"
  oc patch network.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/disableNetworkDiagnostics", "value":true}']
fi

echo

if [ "disabled" = "$(yq '.day2.ptp.ptpconfig' $config_file)" ]; then
  warn "ptpconfig:" "disabled"
fi
if [ "ordinary" = "$(yq '.day2.ptp.ptpconfig' $config_file)" ]; then
  info "ptpconfig ordinary clock:" "enabled"
  jinja2 $templates/day2/ptpconfig-ordinary-clock.yaml.j2 $config_file | oc apply -f -

fi
if [ "boundary" = "$(yq '.day2.ptp.ptpconfig' $config_file)" ]; then
  info "ptpconfig boundary clock:" "enabled"
  jinja2 $templates/day2/ptpconfig-boundary-clock.yaml.j2 $config_file | oc apply -f -
fi

if [ "true" = "$(yq '.day2.ptp.enable_ptp_event' $config_file)" ]; then
  info "ptp event notification:" "enabled"
  oc apply -f $templates/day2/ptp-operator-config-for-event.yaml
fi

echo
# 4.14+ specific
if [ "4.12" = $ocp_y_version ] ||  [ "4.13" = $ocp_y_version ]; then
  echo
else
  if [ "false" = "$(yq '.day2.disable_olm_pprof' $config_file)" ]; then
    warn "disable olm pprof:" "false"
  else
    info "disable olm pprof:" "true"
    oc apply -f $templates/day2/disable-olm-pprof.yaml
  fi
fi

echo 

if [ "false" = "$(yq '.day2.disable_operator_auto_upgrade' $config_file)" ]; then
  warn "operator auto upgrade:" "enable"
else
  subs=$(oc get subs -A -o jsonpath='{range .items[*]}{@.metadata.namespace}{" "}{@.metadata.name}{"\n"}{end}')
  subs=($subs)
  length=${#subs[@]}
  for i in $( seq 0 2 $((length-2)) ); do
    ns=${subs[$i]}
    name=${subs[$i+1]}
    info "operator $name auto upgrade:" "disabled"
    oc patch subscription -n $ns $name --type='json' -p=['{"op": "replace", "path": "/spec/installPlanApproval", "value":"Manual"}']
  done
fi


echo
echo "Done."
