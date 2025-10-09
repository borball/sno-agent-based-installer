#!/bin/bash
#
# Helper script to validate if the SNO node contains all the necessary tunings
# usage: ./sno-ready.sh
# usage: ./sno-ready.sh <cluster-name>
# The script will validate the cluster configurations towards the latest cluster created by sno-install.sh if <cluster-name> is not present
# If cluster-name presents it will validate the cluster configurations towards the cluster with config file: instance/<cluster-name>/config-resolved.yaml
#

if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
fi

SSH="ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -o LogLevel=quiet"

usage(){
	echo "Usage: $0 <cluster-name>"
	echo "If <cluster-name> is not present, it will validate the configurations on the newest cluster installed last time"
  echo "Example: $0"
  echo "Example: $0 sno130"
}

if [[ ( $@ == "--help") ||  $@ == "-h" ]]
then
  usage
  exit
fi

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

cluster_name=$1; shift

if [ -z "$cluster_name" ]; then
  cluster_name=$(ls -t $basedir/instances |head -1)
  debug "Auto-selected cluster: $cluster_name"
fi

cluster_workspace=$basedir/instances/$cluster_name
config_file=$cluster_workspace/config-resolved.yaml

day2_workspace=$cluster_workspace/day2
cluster_tunings_workspace=$day2_workspace/cluster-tunings
node_tunings_workspace=$day2_workspace/node-tunings
operators_workspace=$day2_workspace/operators
operators=$basedir/operators
templates=$basedir/templates

FILTER_FIELDS='
del(.metadata.creationTimestamp) |
del(.metadata.resourceVersion) |
del(.metadata.annotations) |
del(.metadata.uid) |
del(.metadata.generation) |
del(.status) |
del(.metadata.finalizers) |
del(.metadata.ownerReferences) |
del(.spec.clusterID) |
del(.metadata.managedFields)
'

export KUBECONFIG=$cluster_workspace/auth/kubeconfig

ocp_release=$(oc version -o json|jq -r '.openshiftVersion')
ocp_y_version=$(echo $ocp_release | cut -d. -f 1-2)

ssh_priv_key_input=$(yq -r '.ssh_priv_key //""' $config_file)
if [[ ! -z "${ssh_priv_key_input}" ]]; then
  ssh_key_path=$(eval echo $ssh_priv_key_input)
  SSH+=" -i ${ssh_key_path}"
fi

# Color codes for better output
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# Enhanced output functions
info(){
  printf "${GREEN}✓${RESET} %-64s ${GREEN}%-10s${RESET}\n" "$@"
}
  
warn(){
  printf "${YELLOW}⚠${RESET} %-64s ${YELLOW}%-10s${RESET}\n" "$@"
}

error(){
  printf "${RED}✗${RESET} %-64s ${RED}%-10s${RESET}\n" "$@"
}

step(){
  printf "\n${BOLD}${BLUE}▶${RESET} ${BOLD}%s${RESET}\n" "$1"
}

debug(){
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf "${MAGENTA}[DEBUG]${RESET} %s\n" "$1"
  fi
}

header(){
  echo
  printf "${BOLD}${CYAN}%s${RESET}\n" "$1"
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s=' {1..60})"
}

separator(){
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s-' {1..60})"
}

short_path(){
  echo "$*" | sed -e "s;${basedir};\${basedir};g" -e "s;${HOME};\${HOME};g"
}

export_address(){
  export address=$(oc get node -o jsonpath='{..addresses[?(@.type=="InternalIP")].address}'|awk '{print $1;}')
}

# Validate environment and dependencies
validate_environment(){
  debug "Validating environment and dependencies"
  local validation_failed=false
  
  # Check required commands
  local required_commands=("yq" "jinja2" "oc")
  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "Required command not found: $cmd" "Please install $cmd"
      validation_failed=true
    else
      debug "  ✓ Found command: $cmd"
    fi
  done
  
  # Check if KUBECONFIG will be valid
  if [[ -n "$KUBECONFIG" ]]; then
    debug "KUBECONFIG environment variable set to: $KUBECONFIG"
  fi
  
  if $validation_failed; then
    error "Environment validation failed" "Cannot continue"
    return 1
  fi
  
  debug "Environment validation passed"
  return 0
}

check_node(){
  step "Checking node status"
  if [ $(oc get node -o jsonpath='{..conditions[?(@.type=="Ready")].status}') = "True" ]; then
    info "Node" "ready"
  else
    warn "Node" "not ready"
  fi
}

check_pods(){
  step "Checking all pods"
  if [ $(oc get pods -A |grep -vE "Running|Completed" |wc -l) -gt 1 ]; then
    warn "Some pods are failing or creating."
    oc get pods -A |grep -vE "Running|Completed"
  else
    info "No failing pods."
  fi
}

check_cluster_operators(){
  step "Checking cluster operators"
  for name in $(oc get co -o jsonpath={..metadata.name}); do
    local progressing=$(oc get co $name -o jsonpath='{..conditions[?(@.type=="Progressing")].status}')
    local available=$(oc get co $name -o jsonpath='{..conditions[?(@.type=="Available")].status}')
    local degraded=$(oc get co $name -o jsonpath='{..conditions[?(@.type=="Degraded")].status}')
    if [ "$available" = "True" -a "$progressing" = "False" -a "$degraded" = "False" ]; then
      info "cluster operator $name " "healthy"
    else
      warn "cluster operator $name " "unhealthy"
    fi
  done
}

check_workload_partitioning(){
  step "Checking workload partitioning"
  if [ "true" = "$(yq '.node_tunings.workload_partitioning.enabled' $config_file)" ]; then
    info "workload_partition" "enabled in $config_file"
    if [ $(oc get mc |grep 01-master-cpu-partitioning | wc -l) -eq 1 ]; then
      info "mc 01-master-cpu-partitioning" "found"
    else
      warn "mc 01-master-cpu-partitioning" "not found"
    fi
  else
    warn "workload_partition" "not enabled in $config_file"
  fi
}

should_exclude_machine_config(){
  local file=$1
  local exclude_patterns=$(yq -r '.cluster_tunings.excludes[]' $config_file 2>/dev/null)

  if [[ -n "$exclude_patterns" && "$exclude_patterns" != "null" ]]; then
    for pattern in $exclude_patterns; do
      if [[ "$file" == *"$pattern"* ]]; then
        return 0
      fi
    done
  fi
  return 1
}

check_machine_config(){
  local file=$1
  local status=$2
  mc_name=$(yq ".metadata.name" $file)
  if [ "$status" = "included" ]; then
    if [ $(oc get mc |grep $mc_name | wc -l) -eq 1 ]; then
      info "  ├─ $(basename $file)" "included in $(basename $config_file) and found"
    else
      warn "  ├─ $(basename $file)" "included in $(basename $config_file) but not found"
    fi
  fi

  if [ "$status" = "excluded" ]; then
    if [ $(oc get mc |grep $mc_name | wc -l) -eq 1 ]; then
      warn "  ├─ $(basename $file)" "excluded in $(basename $config_file) but still found"
    else
      info "  ├─ $(basename $file)" "excluded in $(basename $config_file) and not found"
    fi
  fi
  
}

is_mc_file(){
  local file=$1
  if [[ $(yq ".kind" $file) == "MachineConfig" ]]; then
    return 0
  else
    return 1
  fi
}

check_machine_configs(){
  step "Checking required machine configs"

  cluster_tunings_version=$(yq '.cluster_tunings.version' $config_file)
  if [[ -z "$cluster_tunings_version" || "$cluster_tunings_version" == "null" ]] || [[ "$cluster_tunings_version" == "none" ]]; then
    warn "Cluster tunings" "disabled in $config_file"
  else
    if [[ -d "$templates/day1/cluster-tunings/$cluster_tunings_version" ]]; then
      # Count total available files
      tuning_files=$(ls $templates/day1/cluster-tunings/$cluster_tunings_version/*.yaml 2>/dev/null)
      exclude_patterns=$(yq -r '.cluster_tunings.excludes[]' $config_file 2>/dev/null)
      debug "Exclude patterns: $exclude_patterns"
      for file in $tuning_files; do
        if is_mc_file "$file"; then
          if should_exclude_machine_config "$file"; then
            check_machine_config "$file" "excluded"
            debug "Excluded: $file"
          else
            check_machine_config "$file" "included"
            debug "Included: $file"
          fi
        fi
      done
    else
      warn "Cluster tunings" "version $cluster_tunings_version not found"
      return 1
    fi
  fi
}

check_machine_config_pools(){
  step "Checking machine config pool"
  updated=$(oc get mcp master -o jsonpath='{..conditions[?(@.type=="Updated")].status}')
  updating=$(oc get mcp master -o jsonpath='{..conditions[?(@.type=="Updating")].status}')
  degraded=$(oc get mcp master -o jsonpath='{..conditions[?(@.type=="Degraded")].status}')
  if [ $updated = "True" -a $updating = "False" -a $degraded = "False" ]; then
    info "mcp master" "updated and not degraded"
  else
    warn "mcp master" "updating or degraded"
  fi
}

check_performance_profile(){
  step "Checking required performance profile"

  if [ "true" = "$(yq '.node_tunings.performance_profile.enabled' $config_file)" ]; then
    desired_file=$node_tunings_workspace/performance-profile/performance-profile-final.yaml
    if [ ! -f "$desired_file" ]; then
      error "Performance profile" "not found in $desired_file"
      return 0
    fi
    pretty_desired_file=$node_tunings_workspace/performance-profile/performance-profile-pretty.yaml
    profile_name=$(yq ".metadata.name" $desired_file)
    if [ $(oc get performanceprofile |grep $profile_name | wc -l) -eq 1 ]; then
      info "PerformanceProfile $profile_name found"
      live_file=$node_tunings_workspace/performance-profile/performance-profile-live.yaml
      yq eval "${FILTER_FIELDS}" $desired_file | yq '... comments=""' | yq -P 'sort_keys(..)' |yq eval --prettyPrint > $pretty_desired_file
      oc get performanceprofile $profile_name -o yaml | yq '... comments=""' | yq -P 'sort_keys(..)' | yq eval "${FILTER_FIELDS}" |yq eval --prettyPrint > $live_file
      diff -q $pretty_desired_file $live_file > /dev/null
      if [ $? -eq 0 ]; then
        info "PerformanceProfile $profile_name is identical to the desired one."
      else
        warn "PerformanceProfile $profile_name is not identical to the desired one."
        diff --suppress-common-lines --side-by-side $pretty_desired_file $live_file
        warn "More details please run: oc diff -f $desired_file"
      fi
    else
      warn "PerformanceProfile $profile_name is not found."
    fi
  else
    warn "Performance profile" "disabled in $config_file"
  fi
}

check_tuned_profile(){
  step "Checking required tuned profile"

  if [ "true" = "$(yq '.node_tunings.tuned_profile.enabled' $config_file)" ]; then
    profiles=$(yq '.node_tunings.tuned_profile|keys[]|select(.!="enabled")' $config_file 2>/dev/null)

      # Get all profiles from config
    local profiles
    readarray -t profiles < <(yq '.node_tunings.tuned_profile|keys[]|select(.!="enabled")' "$config_file" 2>/dev/null)
    if [[ ${#profiles[@]} -le 0 ]]; then
      warn "No tuned profiles configured" "skipping"
      return 0
    fi

    info "Configured tuned profiles: ${profiles[@]}"

    # Process each profile
    for profile in "${profiles[@]}"; do
      desired_file=$node_tunings_workspace/tuned-profiles/tuned-$profile.yaml
      profile_name=$(yq ".metadata.name" $desired_file)
      pretty_desired_file=$node_tunings_workspace/tuned-profiles/tuned-$profile-pretty.yaml
      live_file=$node_tunings_workspace/tuned-profiles/tuned-$profile-live.yaml
      yq eval "${FILTER_FIELDS}" $desired_file | yq '... comments=""' | yq -P 'sort_keys(..)' |yq eval --prettyPrint > "${pretty_desired_file}" 2>/dev/null;
      
      oc get tuned $profile_name -n openshift-cluster-node-tuning-operator -o yaml | yq '... comments=""' | yq -P 'sort_keys(..)' | yq eval "${FILTER_FIELDS}" |yq eval --prettyPrint > $live_file
      diff -q $pretty_desired_file $live_file > /dev/null
      if [ $? -eq 0 ]; then
        info "TunedProfile $profile_name is identical to the desired one."
      else
        warn "TunedProfile $profile_name is not identical to the desired one."
        diff --suppress-common-lines --side-by-side $pretty_desired_file $live_file
        warn "More details please run: oc diff -f $desired_file"
      fi
    done
  else
    warn "Tuned profile" "disabled in $config_file"
  fi
}

check_operator(){
  local key=$1
  local operator_name=$(yq ".operators.$key.name" $operators/operators.yaml)
  local operator_desc=$(yq ".operators.$key.desc" $operators/operators.yaml)
  
  #if has yaml file, then check the namespace
  if [ -f "operators/$key/*.yaml" ]; then
    ns=$(yq '. | select(.kind == "Namespace")|.metadata.name' operators/$key/*.yaml)
  else
    ns=$(jinja2 operators/$key/*.yaml.j2 | yq ".metadata.namespace")
  fi

  debug "Operator: $operator_name, Namespace: $ns"

  csv=$(oc get csv -n $ns |grep -E "$operator_name|$key" |wc -l)
  if [ $csv -eq 1 ]; then
    info "$operator_desc" "available"
  else
    warn "$operator_desc" "not available"
  fi
  #todo, check csv in the namespace of the operator and status of the csv
}

check_operators(){
  step "Checking operators"
  readarray -t keys < <(yq ".operators|keys" $config_file|yq '.[]')
  
  for ((k=0; k<${#keys[@]}; k++)); do
    key="${keys[$k]}"
    if [ "true" = "$(yq ".operators.$key.enabled" $config_file)" ]; then
      check_operator $key
    fi
  done
}

check_cluster_capabilities(){
  step "Checking cluster capabilities"
  
  baseline_capability=$(yq -r ".cluster.capabilities.baselineCapabilitySet" $config_file)
  debug "Baseline capability: ${baseline_capability}"

  if [ "$baseline_capability" = "None" ]; then
    info "Baseline capability" "None"

    enabled_capabilities=$(oc get clusterversion version -o yaml |yq -r ".status.capabilities.enabledCapabilities[]")
    config_capabilities=$(yq -r ".cluster.capabilities.additionalEnabledCapabilities[]" $config_file)
    debug "Enabled capabilities: ${enabled_capabilities[@]}"
    debug "Config capabilities: ${config_capabilities[@]}"

    for capability in ${config_capabilities[@]}; do
      if [ $(echo ${enabled_capabilities[@]} |grep $capability |wc -l) -eq 1 ]; then
        info "(Additional capability) $capability " "enabled"
      else
        warn "(Additional capability) $capability " "not enabled"
      fi
    done

    for capability in ${enabled_capabilities[@]}; do
      if [ $(echo ${config_capabilities[@]} |grep $capability |wc -l) -eq 1 ]; then
        sleep 1
      else
        warn "(Additional capability) $capability " "enabled but not needed"
      fi
    done
  else
    warn "Baseline capability" "${baseline_capability}"
  fi
}

check_catalog_sources(){
  step "Checking Catalog sources"

  if [ "true" = "$(yq '.catalog_sources.create_marketplace_ns' $config_file)" ]; then
    if [ $(oc get namespace openshift-marketplace |wc -l) -eq "0" ]; then
      warn "Namespace openshift-marketplace" "configured but not found"
    else
      info "Namespace openshift-marketplace" "found"
    fi
  fi

  if [ "true" = "$(yq '.catalog_sources.update_operator_hub' $config_file)" ]; then
    for source in $(yq -r '.catalog_sources.defaults[]' $config_file); do
      disabled=$(oc get operatorhubs cluster -o yaml | yq '.spec.sources[] | select(.name == "'$source'") | .disabled // false')
      debug "OperatorHub $source disabled: $disabled"
      if [ "$disabled" = "true" ]; then
        warn "OperatorHub $source" "should not be disabled but disabled"
      else
        info "OperatorHub $source" "not disabled as needed"
      fi
    done
  fi
  
  if [ "true" = "$(yq '.catalog_sources.create_default_catalog_sources' $config_file)" ]; then
    for source in $(yq -r '.catalog_sources.defaults[]' $config_file); do
      if [ $(oc get catalogsource -n openshift-marketplace |grep $source|wc -l) -eq "0" ]; then
        warn "Catalog $source" "not created"
      else
        info "Catalog $source" "created"
      fi
    done
  fi
}

check_installplans(){
  step "Checking InstallPlans"
  if [ $(oc get installplans.operators.coreos.com -A |grep false |wc -l) -gt 0 ]; then
    warn "InstallPlans below are not approved yet."
    oc get installplans.operators.coreos.com -A |grep false
  else
    info "All InstallPlans have been approved or auto-approved."
  fi
}

check_extra_readiness(){
  extra_readiness=$(yq '.readiness.extra_checks' $config_file)
  if [ "$extra_readiness" == "null" ]; then
    sleep 1
  else
    all_paths_config=$(yq '.readiness.extra_checks|join(" ")' $config_file)
    all_paths=$(eval echo $all_paths_config)
    for d in $all_paths; do
      if [[ -d "$d" ]]; then
        step "Extra Checking $d"
        readarray -t check_files < <(find ${d} -type f \( -name "*.yaml" -o -name "*.yaml.j2" -o -name "*.sh" \) |sort)
        for ((i=0; i<${#check_files[@]}; i++)); do
          file="${check_files[$i]}"
          case "$file" in
            *.yaml)
              output=$(oc diff -f $file)
              if [[ $? -ne 0 ]]; then
		            warn $(basename $file) "Failed"
              else
                info $(basename $file) "Successful"
              fi
              echo "$output"
              ;;
            *.yaml.j2)
              output=$(jinja2 $file $config_file | oc diff -f -)
              if [[ $? -ne 0 ]]; then
                warn $(basename $file) "Failed"
              else
                info $(basename $file) "Successful"
              fi
              echo "$output"
              ;;
            *.sh)
              output=$(. $file)
              if [[ $? -ne 0 ]]; then
                warn $(basename $file) "Failed"
              else
                info $(basename $file) "Successful"
              fi
              echo "$output"
              ;;
            *)
              warn $file "Skipped: unknown type"
              ;;
          esac
         done
      fi
    done
  fi
}

header "SNO Agent-Based Installer - Readiness Validation"

# Validate configuration file
if [ -f "$config_file" ]; then
  info "Configuration file" "$(short_path $config_file)"
  info "Target cluster" "$cluster_name"
else
  error "Config file not found" "$(short_path $config_file)"
  exit 1
fi

# Validate environment before proceeding
if ! validate_environment; then
  exit 1
fi

# Show debug status
if [[ "${DEBUG:-false}" == "true" ]]; then
  info "Debug mode" "ENABLED (set DEBUG=false to disable)"
else
  info "Debug mode" "disabled (set DEBUG=true to enable detailed logging)"
fi

debug "Script execution started at: $(date)"
debug "Configuration file: $config_file"
debug "Target cluster: $cluster_name"
debug "OpenShift version: ${ocp_release:-unknown}"

step "Gathering cluster information"
if ! oc get clusterversion >/dev/null 2>&1; then
  error "Cluster is not reachable" "Check KUBECONFIG and connectivity"
  printf "${RED}KUBECONFIG: ${YELLOW}%s${RESET}\n" "${KUBECONFIG:-not set}"
  exit 1
fi
oc get clusterversion

check_node
check_cluster_operators
export_address
check_pods
check_machine_config_pools
check_machine_configs
check_performance_profile
check_tuned_profile
check_operators
check_cluster_capabilities
check_catalog_sources
check_installplans
check_extra_readiness

header "SNO Readiness Check Complete - Summary"

debug "Script execution completed at: $(date)"

info "✅ All checks completed" "successfully"
info "📁 Kubeconfig location" "$(short_path $cluster_workspace/auth/kubeconfig)"
info "⚙️  Configuration file" "$(short_path $config_file)"
info "🎯 Target cluster" "$cluster_name"
info "🔧 OpenShift version" "$ocp_release"
separator
printf "${BOLD}${GREEN}🎉 SNO readiness validation completed!${RESET}\n"
if [[ "${DEBUG:-false}" != "true" ]]; then
  printf "${CYAN}For detailed debugging, run with: ${YELLOW}DEBUG=true %s${RESET}\n" "$0"
fi
