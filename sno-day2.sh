#!/bin/bash
# 
# Helper script to apply the day2 operations on SNO node
# Usage: ./sno-day2.sh
# Usage: ./sno-day2.sh <cluster-name>
#
# The script will run day2 config towards the latest cluster created by sno-iso.sh if <cluster-name> is not present
# If cluster-name presents it will run day2 config towards the cluster with config file: instance/<cluster-name>/config-resolved.yaml
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
	echo "Usage: $0 <cluster-name>"
	echo "If <cluster-name> is not present, it will run day2 ops towards the newest cluster installed by sno-install"
  echo "Example: $0"
  echo "Example: $0 sno130"
}

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

cluster_name=$1; shift

if [ -z "$cluster_name" ]; then
  cluster_name=$(ls -t $basedir/instances |head -1)
fi

cluster_workspace=$basedir/instances/$cluster_name

config_file=$cluster_workspace/config-resolved.yaml
if [ -f "$config_file" ]; then
  echo "Will run day2 config towards the cluster $cluster_name with config: $config_file"
else
  "Config file $config_file not exist, please check."
  exit -1
fi

export KUBECONFIG=$cluster_workspace/auth/kubeconfig

cluster_info(){
  oc get clusterversion
  echo
  oc get nodes
  echo
  oc get co
  echo
  oc get operators
  echo
  oc get subs -A
  echo
  oc get csv -A -o name|sort |uniq
}

ocp_release=$(oc version -o json|jq -r '.openshiftVersion')
ocp_y_version=$(echo $ocp_release | cut -d. -f 1-2)

performance_profile(){
  if [ "false" = "$(yq '.day2.performance_profile.enabled' $config_file)" ]; then
    warn "performance profile:" "disabled"
  else
    info "performance profile:" "enabled"
    if [ "4.12" = $ocp_y_version ] ||  [ "4.13" = $ocp_y_version ]; then
      jinja2 $templates/day2/performance-profile/performance-profile-$ocp_y_version.yaml.j2 $config_file | oc apply -f -
    else
      #4.14+
      jinja2 $templates/day2/performance-profile/performance-profile.yaml.j2 $config_file | oc apply -f -
    fi
  fi
}

tuned_profile(){
  if [ "false" = "$(yq '.day2.tuned_profile.enabled' $config_file)" ]; then
    warn "tuned performance patch:" "disabled"
  else
    info "tuned performance patch:" "enabled"
    if [ "4.12" = $ocp_y_version ] || [ "4.13" = $ocp_y_version ] || [ "4.14" = $ocp_y_version ] || [ "4.15" = $ocp_y_version ] ; then
      jinja2 $templates/day2/tuned/performance-patch-tuned.yaml.j2 $config_file | oc apply -f -
    else
      #4.16+
      jinja2 $templates/day2/tuned/performance-patch-tuned-4.16.yaml.j2 $config_file | oc apply -f -
    fi
  fi
}

kdump_for_lab_only(){
  if [ "true" = "$(yq '.day2.tuned_profile.kdump' $config_file)" ]; then
    info "tuned kdump settings:" "enabled"
    oc apply -f $templates/day2/tuned/performance-patch-kdump-setting.yaml
  else
    warn "tuned kdump settings:" "disabled"
  fi
}

cluster_monitoring(){
  if [ "false" = "$(yq '.day2.cluster_monitor_tuning' $config_file)" ]; then
    warn "cluster monitor tuning:" "disabled"
  else
    info "cluster monitor tuning:" "enabled"
    if [ "4.12" = "$ocp_y_version" ]; then
      oc apply -f $templates/day2/cluster-tunings/cluster-monitoring-cm-4.12.yaml
    elif [ "4.13" = "$ocp_y_version" ]; then
      oc apply -f $templates/day2/cluster-tunings/cluster-monitoring-cm-4.13.yaml
    else
      oc apply -f $templates/day2/cluster-tunings/cluster-monitoring-cm.yaml
    fi
  fi
}

network_diagnostics(){
  if [ "false" = "$(yq '.day2.disable_network_diagnostics' $config_file)" ]; then
    warn "network diagnostics:" "enabled"
  else
    info "network diagnostics:" "disabled"
    oc patch network.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/disableNetworkDiagnostics", "value":true}']
  fi
}

ptp_configs(){
  if [ "disabled" = "$(yq '.day2.ptp.ptpconfig' $config_file)" ]; then
    warn "ptpconfig:" "disabled"
  fi
  if [ "ordinary" = "$(yq '.day2.ptp.ptpconfig' $config_file)" ]; then
    info "ptpconfig ordinary clock:" "enabled"
    jinja2 $templates/day2/ptp/ptpconfig-ordinary-clock.yaml.j2 $config_file | oc apply -f -
  fi
  if [ "boundary" = "$(yq '.day2.ptp.ptpconfig' $config_file)" ]; then
    info "ptpconfig boundary clock:" "enabled"
    jinja2 $templates/day2/ptp/ptpconfig-boundary-clock.yaml.j2 $config_file | oc apply -f -
  fi

  if [ "true" = "$(yq '.day2.ptp.enable_ptp_event' $config_file)" ]; then
    info "ptp event notification:" "enabled"
    oc apply -f $templates/day2/ptp/ptp-operator-config-for-event.yaml
  fi
}

sriov_configs(){
  if [ "false" = "$(yq '.day1.operators.sriov.enabled' $config_file)" ]; then
    warn "sriov operator not enabled"
  else
    info "sriov operator configuration"
    jinja2 $templates/day2/sriov/sriov-operator-config-default.yaml.j2 $config_file | oc apply -f -
  fi
}

nmstate_config(){
  if [ "true" = "$(yq '.day1.operators.nmstate.enabled' $config_file)" ]; then
    info "nmstate operator configuration"
    oc apply -f $templates/day2/nmstate/nmstate-nmstate.yaml
  fi
}

metallb_config(){
  if [ "true" = "$(yq '.day1.operators.metallb.enabled' $config_file)" ]; then
    info "metallb-metallb operator configuration"
    oc apply -f $templates/day2/metallb/metallb-metallb.yaml
  fi
}

lvm_config(){
  if [ "true" = "$(yq '.day1.operators.lvm.enabled' $config_file)" ]; then
    info "lvm operator configuration"
    jinja2 $templates/day2/lvm/lvmcluster-singlenode.yaml.j2 $config_file | oc apply -f -
  fi
}

olm_pprof(){
  # 4.14+ specific
  if [ "4.12" = $ocp_y_version ] ||  [ "4.13" = $ocp_y_version ]; then
    echo
  else
    if [ "false" = "$(yq '.day2.disable_olm_pprof' $config_file)" ]; then
      warn "disable olm pprof:" "false"
    else
      info "disable olm pprof:" "true"
      oc apply -f $templates/day2/cluster-tunings/disable-olm-pprof.yaml
    fi
  fi
}

install_plan_approval(){
  subs=$(oc get subs -A -o jsonpath='{range .items[*]}{@.metadata.namespace}{" "}{@.metadata.name}{"\n"}{end}')
  subs=($subs)
  length=${#subs[@]}
  for i in $( seq 0 2 $((length-2)) ); do
    ns=${subs[$i]}
    name=${subs[$i+1]}
    info "operator $name subscription installPlanApproval:" "$1"
    oc patch subscription -n $ns $name --type='json' -p=["{\"op\": \"replace\", \"path\": \"/spec/installPlanApproval\", \"value\":\"$1\"}"]
  done
}

operator_auto_upgrade(){
  case "$(yq '.day2.disable_operator_auto_upgrade' $config_file)" in
    true)
      warn "Disable operators auto upgrade" "true"
      install_plan_approval "Manual"
      ;;
    false)
      warn "Disable operators auto upgrade" "false"
      install_plan_approval "Automatic"
      ;;
    *)
      ;;
  esac
}

echo "------------------------------------------------"
cluster_info
echo
echo "------------------------------------------------"
echo "Applying day2 operations...."
echo

performance_profile
echo
tuned_profile
echo
kdump_for_lab_only
echo
cluster_monitoring
echo
network_diagnostics
ptp_configs
echo
sriov_configs
nmstate_config
metallb_config
lvm_config
echo
olm_pprof
echo
operator_auto_upgrade
echo

echo "Done."
