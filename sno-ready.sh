#!/bin/bash
# 
# Helper script to validate if the SNO node contains all the necessary tunings
# usage: ./sno-ready.sh
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

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
templates=$basedir/templates

config_file=$1;

cluster_name=$(yq '.cluster.name' $config_file)
cluster_workspace=$cluster_name
export KUBECONFIG=$cluster_workspace/auth/kubeconfig

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

info(){
  echo -e "${GREEN} [+]"$@""
}

warn(){
  echo -e "${RED} [-]"$@""
}

check_node(){
  echo -e "\n${NC}Checking node:"
  if [ $(oc get node -o jsonpath='{..conditions[?(@.type=="Ready")].status}') = "True" ]; then
    info "Node is ready."
  else
    warn "Node is not ready."
  fi
}

check_pods(){
  echo -e "\n${NC}Checking all pods:"
  if [ $(oc get pods -A |grep -vE "Running|Completed" |wc -l) -gt 1 ]; then
    warn "Some pods are failing."
    oc get pods -A |grep -vE "Running|Completed"
  else
    info "No failing pods."
  fi
}

check_mc(){
  echo -e "\n${NC}Checking required machine configs:"
  
  if [ "false" = "$(yq '.day1.workload_partition' $config_file)" ]; then
    warn "workload_partition is not enabled in $config_file"
  else
    if [ $(oc get mc |grep 02-master-workload-partitioning | wc -l) -eq 1 ]; then
      info "MachineConfig 02-master-workload-partitioning exits."
    else
      warn "MachineConfig 02-master-workload-partitioning is not existing."
    fi
  fi

  if [ "false" = "$(yq '.day1.kdump.enabled' $config_file)" ]; then
    warn "kdump service is not enabled in $config_file"
  else
    if [ $(oc get mc |grep 06-kdump-enable-master | wc -l) -eq 1 ]; then
      info "MachineConfig 06-kdump-enable-master exits."
    else
      warn "MachineConfig 06-kdump-enable-master is not existing."
    fi
  fi

  if [ "true" = "$(yq '.day1.kdump.blacklist_ice' $config_file)" ]; then
    if [ $(oc get mc |grep 05-kdump-config-master | wc -l) -eq 1 ]; then
      info "MachineConfig 05-kdump-config-master exits."
    else
      warn "MachineConfig 05-kdump-config-master is not existing."
    fi
  else
    warn "kdump blacklist_ice is not enabled in $config_file"
  fi

  if [ "false" = "$(yq '.day1.boot_accelerate' $config_file)" ]; then
    warn "boot_accelerate is not enabled in $config_file"
  else
    if [ $(oc get mc |grep container-mount-namespace-and-kubelet-conf-master | wc -l) -eq 1 ]; then
      info "MachineConfig container-mount-namespace-and-kubelet-conf-master exits."
    else
      warn "MachineConfig container-mount-namespace-and-kubelet-conf-master is not existing."
    fi

    if [ $(oc get mc |grep 04-accelerated-container-startup-master | wc -l) -eq 1 ]; then
      info "MachineConfig 04-accelerated-container-startup-master exits."
    else
      warn "MachineConfig 04-accelerated-container-startup-master is not existing."
    fi

    if [ $(oc get mc |grep 99-crio-disable-wipe-master | wc -l) -eq 1 ]; then
      info "MachineConfig 99-crio-disable-wipe-master exits."
    else
      warn "MachineConfig 99-crio-disable-wipe-master is not existing."
    fi
  fi

}

check_mcp(){
  echo -e "\n${NC}Checking machine config pool:"
  updated=$(oc get mcp master -o jsonpath='{..conditions[?(@.type=="Updated")].status}')
  updating=$(oc get mcp master -o jsonpath='{..conditions[?(@.type=="Updating")].status}')
  degraded=$(oc get mcp master -o jsonpath='{..conditions[?(@.type=="Degraded")].status}')
  if [ $updated = "True" -a $updating = "False" -a $degraded = "False" ]; then
    info "mcp master is updated and not degraded."
  else
    warn "mcp master is updating or degraded."
  fi
}

check_pp(){
  echo -e "\n${NC}Checking required performance profile:"

  if [ "false" = "$(yq '.day2.performance_profile.enabled' $config_file)" ]; then
    warn "performance profile:" "disabled"
  else
    pp=$(yq '.day2.performance_profile.name //"openshift-node-performance-profile"' $config_file)
    
    if [ $(oc get performanceprofiles |grep $pp | wc -l) -eq 1 ]; then
      info "PerformanceProfile $pp exits."
      check_pp_detail
    else
      warn "PerformanceProfile $pp is not existing."
    fi
  fi
}

check_pp_detail(){
  if [ $(oc get performanceprofile -o jsonpath={..topologyPolicy}) = "single-numa-node" ]; then
    info "topologyPolicy is single-numa-node"
  else
    warn "topologyPolicy is not single-numa-node"
  fi
  if [ $(oc get performanceprofile -o jsonpath={..realTimeKernel.enabled}) = "true" ]; then
    info "realTimeKernel is enabled"
  else
    warn "realTimeKernel is not enabled"
  fi
}


check_tuned(){
  echo -e "\n${NC}Checking required tuned:"

  if [ "false" = "$(yq '.day2.tuned_profile.enabled' $config_file)" ]; then
    warn "Tuned performance patch:" "disabled"
  else   
    if [ $(oc get tuned -n  openshift-cluster-node-tuning-operator performance-patch|grep performance-patch | wc -l) -eq 1 ]; then
      info "Tuned performance-patch exits."
    else
      warn "Tuned performance-patch is not existing."
    fi
  fi

  if [ "true" = "$(yq '.day2.tuned_profile.kdump' $config_file)" ]; then
    if [ $(oc get tuned -n  openshift-cluster-node-tuning-operator performance-patch-kdump-setting|grep performance-patch-kdump-setting | wc -l) -eq 1 ]; then
      info "Tuned performance-patch-kdump-setting exits."
    else
      warn "Tuned performance-patch-kdump-setting is not existing."
    fi
  fi

}

check_sriov(){
  echo -e "\n${NC}Checking SRIOV operator status:"

  if [ "false" = "$(yq '.day1.operators.sriov' $config_file)" ]; then
    warn "SR-IOV operator:" "disabled"
  else   
    if [ $(oc get sriovnetworknodestate -n openshift-sriov-network-operator -o jsonpath={..syncStatus}) = "Succeeded" ]; then
      info "sriovnetworknodestate sync status is 'Succeeded'."
    else
      warn "sriovnetworknodestate sync status is not 'Succeeded'."
    fi
  fi
}

check_ptp(){
  echo -e "\n${NC}Checking PTP operator status:"
  if [ "false" = "$(yq '.day1.operators.ptp' $config_file)" ]; then
    warn "PTP operator:" "disabled"
  else   
    if [ $(oc get daemonset -n openshift-ptp linuxptp-daemon -o jsonpath={.status.numberReady}) -eq 1 ]; then
      info "Ptp linuxptp-daemon is ready."
      check_ptpconfig
    else
      warn "Ptp linuxptp-daemon is not ready."
    fi
  fi
}

check_ptpconfig(){
  if [ "ordinary" = "$(yq '.day2.ptp.ptpconfig' $config_file )" ] || [ "boundary" = "$(yq '.day2.ptp.ptpconfig' $config_file )" ]; then
    if [ $(oc get ptpconfig -n openshift-ptp |grep -v NAME |wc -l) -eq 1 ]; then
      info "PtpConfig exists."
      if [ $(oc get ptpconfig -n openshift-ptp -o jsonpath={..ptpSchedulingPolicy}) = "SCHED_FIFO" ]; then
        info "Ptp SchedulingPolicy is SCHED_FIFO."
      else
        warn "Ptp SchedulingPolicy is not SCHED_FIFO."
      fi
      if [ $(oc get ptpconfig -n openshift-ptp -o jsonpath={..ptpSchedulingPriority}) = "10" ]; then
        info "Ptp ptpSchedulingPriority is 10."
      else
        warn "Ptp SchedulingPolicy is not 10."
      fi
    else
      warn "PtpConfig not exist."
    fi
  fi

}

check_monitoring(){
  echo -e "\n${NC}Checking openshift monitoring."
  if [ "false" = "$(yq '.day2.cluster_monitor_tuning' $config_file)" ]; then
    warn "cluster_monitor_tuning is not enabled in $config_file"
  else
    if [ $(oc get configmap -n openshift-monitoring cluster-monitoring-config -o jsonpath={.data.config\\.yaml} |yq e '.grafana.enabled' -) = "false" ]; then
      info "Grafana is not enabled."
    else
      warn "Grafana is enabled."
    fi
    if [ $(oc get configmap -n openshift-monitoring cluster-monitoring-config -o jsonpath={.data.config\\.yaml} |yq e '.alertmanagerMain.enabled' -) = "false" ]; then
      info "AlertManager is not enabled."
    else
      warn "AlertManager is enabled."
    fi
    if [ $(oc get configmap -n openshift-monitoring cluster-monitoring-config -o jsonpath={.data.config\\.yaml} |yq e '.prometheusK8s.retention' -) = "24h" ]; then
      info "PrometheusK8s retention is not 24h."
    else
      warn "PrometheusK8s retention is 24h."
    fi
  fi
}

check_console(){
  echo -e "\n${NC}Checking openshift console."

  if [ "false" = "$(yq '.day2.disable_ocp_console' $config_file)" ]; then
    warn "disable_ocp_console is not enabled in $config_file"
  else
    if [ $(oc get consoles.operator.openshift.io cluster  -o jsonpath={..managementState}) = "Removed" ]; then
      info "Openshift console is disabled."
    else
      warn "Openshift console is not disabled."
    fi
  fi  
}

check_network_diagnostics(){
  echo -e "\n${NC}Checking network diagnostics."
  if [ "false" = "$(yq '.day2.disable_network_diagnostics' $config_file)" ]; then
    warn "disable_network_diagnostics is not enabled in $config_file"
  else  
    if [ $(oc get network.operator.openshift.io cluster -o jsonpath={..disableNetworkDiagnostics}) = "true" ]; then
      info "Network diagnostics is disabled."
    else
      warn "Network diagnostics is not disabled."
    fi
  fi
}

check_operator_hub(){
  echo -e "\n${NC}Checking Operator hub."
  if [ "false" = "$(yq '.day2.operator_hub_tuning' $config_file)" ]; then
    warn "operator_hub_tuning is not enabled in $config_file"
  else  
    if [ $(oc get catalogsource -n openshift-marketplace |grep community-operators|wc -l) -eq "0" ]; then
      info "Catalog community-operators is disabled."
    else
      warn "Catalog community-operators is not disabled"
    fi
    if [ $(oc get catalogsource -n openshift-marketplace |grep redhat-marketplace|wc -l) -eq "0" ]; then
      info "Catalog redhat-marketplace is disabled."
    else
      warn "Catalog redhat-marketplace is not disabled"
    fi
  fi  
}

check_cmdline(){
  echo -e "\n${NC}Checking /proc/cmdline:"
  export address=$(oc get node -o jsonpath='{..addresses[?(@.type=="InternalIP")].address}')
  export cmdline_arguments=$(ssh core@$address cat /proc/cmdline)

  check_cpuset
}

check_kernel(){
  echo -e "\n${NC}Checking RHCOS kernel:"
  kernel_version=$(ssh core@$address uname -r)
  if [ $(echo $kernel_version |grep rt | wc -l ) -eq 1 ]; then
    info "Node is realtime kernel."
  else
    warn "Node is not realtime kernel"
  fi
}

check_cpuset(){
  for argument in $cmdline_arguments; do
    if [[ "$argument" == *"cpu_affinity"* ]]; then
      cpu_affinity=$argument
    fi
    if [[ "$argument" == *"isolcpus"* ]]; then
      isolcpus=$argument
    fi
  done

  if [ -z $cpu_affinity ]; then
    warn "systemd.cpu_affinity not present."
  else
    info "systemd.cpu_affinity presents: $cpu_affinity"
  fi
  if [ -z $isolcpus ]; then
    warn "isolcpus not present."
  else
    info "isolcpus presents: $isolcpus"
  fi

  cpu_affinity="${cpu_affinity/systemd.cpu_affinity=/}"
  isolcpus="${isolcpus/isolcpus=/}"
  isolcpus="${isolcpus/managed_irq,/}"

  isolcpus_pp=$(oc get performanceprofiles.performance.openshift.io -o jsonpath={..spec.cpu.isolated})
  reservedcpus_pp=$(oc get performanceprofiles.performance.openshift.io -o jsonpath={..spec.cpu.reserved})

  cmd_cpu_affinity=()
  cmd_isolated_cpus=()

  pp_isolated_cpus=()
  pp_reserved_cpus=()

  for n1 in $(echo $cpu_affinity | awk '/-/{for (i=$1; i<=$2; i++)printf "%s%s",i,ORS;next} 1' RS=, FS=-)
  do
    cmd_cpu_affinity+=($n1)
  done

  for n2 in $(echo $isolcpus | awk '/-/{for (i=$1; i<=$2; i++)printf "%s%s",i,ORS;next} 1' RS=, FS=-)
  do
    cmd_isolated_cpus+=("$n2")
  done

  for n3 in $(echo $isolcpus_pp | awk '/-/{for (i=$1; i<=$2; i++)printf "%s%s",i,ORS;next} 1' RS=, FS=-)
  do
    pp_isolated_cpus+=("$n3")
  done

  for n4 in $(echo $reservedcpus_pp | awk '/-/{for (i=$1; i<=$2; i++)printf "%s%s",i,ORS;next} 1' RS=, FS=-)
  do
    pp_reserved_cpus+=("$n4")
  done

  isolated_cpu_match1=1
  isolated_cpu_match2=1
  reserved_cpu_match1=1
  reserved_cpu_match2=1

  for v1 in "${cmd_cpu_affinity[@]}"
  do
    if [[ ! " ${pp_reserved_cpus[*]} " =~ " ${v1} " ]]; then
      reserved_cpu_match1=0
      break
    fi
  done

  for v2 in "${cmd_isolated_cpus[@]}"
  do
    if [[ ! " ${pp_isolated_cpus[*]} " =~ " ${v2} " ]]; then
      isolated_cpu_match1=0
      break
    fi
  done

  for v1 in "${pp_reserved_cpus[@]}"
  do
    if [[ ! " ${cmd_cpu_affinity[*]} " =~ " ${v1} " ]]; then
      reserved_cpu_match2=0
      break
    fi
  done

  for v2 in "${pp_isolated_cpus[@]}"
  do
    if [[ ! " ${cmd_isolated_cpus[*]} " =~ " ${v2} " ]]; then
      isolated_cpu_match2=0
      break
    fi
  done

  if [[ $isolated_cpu_match1 == 1 && $isolated_cpu_match2 == 1 ]]; then
    info "Isolated cpu in cmdline: $isolcpus matches with the ones in performance profile: $isolcpus_pp"
  else
    warn "Isolated cpu in cmdline: $isolcpus not match with the ones in performance profile: $isolcpus_pp"
  fi

  if [[ $reserved_cpu_match1 == 1 && $reserved_cpu_match2 == 1 ]]; then
    info "Reserved cpu in cmdline: $cpu_affinity matches with the ones in performance profile: $reservedcpus_pp"
  else
    warn "Reserved cpu in cmdline: $cpu_affinity not match with the ones in performance profile: $reservedcpus_pp"
  fi

}

check_kdump(){
  echo -e "\n${NC}Checking kdump.service:"
  if [ "false" = "$(yq '.day1.kdump.enabled' $config_file)" ]; then
    warn "kdump is not enabled in $config_file"
  else
    if [[ $(ssh core@$address systemctl is-active kdump) = 'active' ]]; then
      info "kdump is active."
    else
      warn "kdump is not active."
    fi

    if [[ $(ssh core@$address systemctl is-enabled kdump) = 'enabled' ]]; then
      info "kdump is enabled."
    else
      warn "kdump is not enabled."
    fi
  fi  
}

check_chronyd(){
  echo -e "\n${NC}Checking chronyd.service:"
  if [ "disabled" = "$(yq '.day2.ptp.ptpconfig' $config_file)" ]; then
    warn "ptpconfig is not enabled in $config_file"
  else
    if [[ $(ssh core@$address systemctl is-active chronyd) = 'inactive' ]]; then
      info "chronyd is inactive."
    else
      warn "chronyd is active."
    fi

    if [[ $(ssh core@$address systemctl is-enabled chronyd) = 'enabled' ]]; then
      warn "chronyd is enabled."
    else
      info "chronyd is not enabled."
    fi
  fi  
}

check_crio_wipe(){
  echo -e "\n${NC}Checking crio-wipe.service:"
  if [[ $(ssh core@$address systemctl is-active crio-wipe) = 'inactive' ]]; then
    info "crio-wipe is inactive."
  else
    warn "crio-wipe is active."
  fi

  if [[ $(ssh core@$address systemctl is-enabled crio-wipe) = 'enabled' ]]; then
    warn "crio-wipe is enabled."
  else
    info "crio-wipe is not enabled."
  fi
}

oc get node

if [ $? -eq 0 ]; then
  check_node
  check_pods
  check_mc
  check_mcp
  check_pp
  check_tuned
  check_sriov
  check_ptp
  check_monitoring
  check_console
  check_network_diagnostics
  check_operator_hub
  check_cmdline
  check_kernel
  check_kdump
  check_chronyd
  check_crio_wipe

  echo -e "\n${NC}Completed the checking."
else
  echo -e "\n${NC}Please export the KUBECONFIG environment variable before running the check."
fi