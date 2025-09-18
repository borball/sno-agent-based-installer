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

header(){
  echo
  printf "${BOLD}${CYAN}%s${RESET}\n" "$1"
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s=' {1..60})"
}

separator(){
  printf "${CYAN}%s${RESET}\n" "$(printf '%.0s-' {1..60})"
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
  info "Configuration file" "$config_file"
  info "Target cluster" "$cluster_name"
else
  error "Config file not found" "$config_file"
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

  missing_csv=$(oc get sub -A -o json | jq -cMr '.items[]|select(.status.installedCSV == null) |.metadata|{namespace: .namespace, name: .name}')
  if [[ -n "${missing_csv}" ]]; then
    echo ""
    error "Uninstalled subscriptions found" "Manual intervention required"
    echo "${missing_csv}"
    exit 1
  fi

  i=1
  while [[ ! -z "$(oc get csv --no-headers -A |grep -v 'Succeeded')" ]]; do
    warn "CSV installation in progress" "waiting..."
    oc get csv -A |grep -v "Succeeded"
    if [[ $i -le 5 ]]; then
      info "Waiting [$i/5] for another 30 seconds" "..."
      sleep 30
    else
      error "CSV installation timeout" "Manual intervention required"
      exit 1
    fi
    ((i=i+1))
  done
}

ocp_release=$(oc version -o json|jq -r '.openshiftVersion')
ocp_y_version=$(echo $ocp_release | cut -d. -f 1-2)
export OCP_Y_VERSION=$ocp_y_release
export OCP_Z_VERSION=$ocp_release

delay_mcp_update=$(yq '.day2.delay_mcp_update // 0' $config_file)

pause_mcp_update(){
  step "Pausing master machine config pool update"
  trap resume_mcp_update SIGINT SIGABRT SIGKILL
  oc patch --type=merge --patch='{"spec":{"paused":true}}' mcp/master
}

resume_mcp_update(){
  local delay=${1:-0}
  if [[ ${delay} -gt 0 ]]; then
    step "Resuming master machine config pool update (delayed ${delay}s)"
    sleep ${delay}
  else
    step "Resuming master machine config pool update"
  fi
  for i in {1..20}; do
    oc patch --type=merge --patch='{"spec":{"paused":false}}' mcp/master
    if [[ $? -eq 0 ]]; then
      return
    fi
    warn "Retry ($i/20) in 15 seconds..." "Failed"
    sleep 15
  done
  error "Failed to resume master MCP" "Manual intervention required"
  printf "${RED}Please manually resume using:${RESET}\n"
  printf "${YELLOW}oc patch --type=merge --patch='{\"spec\":{\"paused\":false}}' mcp/master${RESET}\n"
}

node_tuning(){
  step "Configuring node tunings"
  if [ "$(yq '.node_tunings' $config_file)" = "null" ]; then
    warn "Node tuning" "disabled"
  else
    if [ "$(yq '.node_tunings.workload_partitioning.enabled' $config_file)" = "true" ]; then
      info "Workload partitioning" "enabled (configured in day1)"
    else
      warn "Workload partitioning" "disabled"
    fi

    if [ "$(yq '.node_tunings.performance_profile.enabled' $config_file)" = "true" ]; then
      info "Performance profile" "enabled"
      jinja2 $templates/day2/performance-profile/performance-profile.yaml.j2 $config_file | oc apply -f -
    else
      warn "Performance profile" "disabled"
    fi

    if [ "$(yq '.node_tunings.tuned_profile.enabled' $config_file)" = "true" ]; then
      info "Tuned profile" "enabled"
      jinja2 $templates/day2/tuned/performance-patch-tuned.yaml.j2 $config_file | oc apply -f -
    else
      warn "Tuned profile" "disabled"
    fi
  fi
}

operator_configs(){
  step "Configuring OpenShift Operators"
  if [ "$(yq '.operators' $config_file)" = "null" ]; then
    warn "Operators" "not configured"
  else
    readarray -t keys < <(yq ".operators|keys" $config_file|yq '.[]')
    
    enabled_count=0
    disabled_count=0
    
    for key in ${keys[@]}; do
      if [[ $(yq ".operators.$key.enabled" $config_file) == "true" ]]; then
        info "$key operator" "enabled"
        ((enabled_count++))
        
        before_scripts=$(yq ".operators.$key.config.before[]?" $config_file 2>/dev/null)
        if [[ -z "$before_scripts" ]]; then
          info "  ├─ no before scripts"
        else
          info "  ├─ executing before scripts"
          while IFS= read -r script; do
            if [[ -n "$script" && "$script" != "null" ]]; then
              script_path="$templates/day2/$key/$script"
              if [[ -f "$script_path" ]]; then
                info "  │  └─ running $script"
                "$script_path" "$config_file"
              else
                warn "  │  └─ script not found: $script"
              fi
            fi
          done <<< "$before_scripts"
        fi

        manifest_files=$(yq ".operators.$key.config.manifests[]?" $config_file 2>/dev/null)
        if [[ -z "$manifest_files" ]]; then
          info "  └─ using all files from templates/day2/$key/"
          if [[ -d "$templates/day2/$key" ]]; then
            for f in "$templates/day2/$key"/*.yaml "$templates/day2/$key"/*.yaml.j2; do
              if [[ -f "$f" ]]; then
                filename=$(basename "$f")
                if [[ "$f" == *.j2 ]]; then
                  info "     ├─ rendering $filename"
                  data_file=$(yq ".operators.$key.config.data" $config_file)
                  if [[ "$data_file" != "null" ]]; then
                    yq ".operators.$key.config.data" $config_file |jinja2 "$f"  > "$cluster_workspace/openshift/$(basename "$f" .j2)"
                  else
                    jinja2 "$f" "$config_file" > "$cluster_workspace/openshift/$(basename "$f" .j2)"
                  fi
                else
                  info "     ├─ copying $filename"
                  cp "$f" "$cluster_workspace/openshift/"
                fi
              fi
            done
          fi
        else
          info "  └─ using specified manifest files"
          while IFS= read -r manifest; do
            if [[ -n "$manifest" && "$manifest" != "null" ]]; then
              manifest_path="$templates/day2/$key/$manifest"
              if [[ -f "$manifest_path" ]]; then
                filename=$(basename "$manifest")
                if [[ "$manifest" == *.j2 ]]; then
                  info "     ├─ rendering $filename"
                  data_file=$(yq ".operators.$key.config.data" $config_file)
                  if [[ "$data_file" != "null" ]]; then
                    yq ".operators.$key.config.data" $config_file |jinja2 "$manifest_path"  > "$cluster_workspace/openshift/$(basename "$manifest" .j2)"
                  else
                    jinja2 "$manifest_path" "$config_file" > "$cluster_workspace/openshift/$(basename "$manifest" .j2)"
                  fi
                else
                  info "     ├─ copying $filename"
                  cp "$manifest_path" "$cluster_workspace/openshift/"
                fi
              else
                warn "     ├─ manifest not found: $manifest"
              fi
            fi
          done <<< "$manifest_files"
        fi
      else
        warn "$key operator" "disabled"
        ((disabled_count++))
      fi
    done
    
    separator
    info "Operators enabled" "$enabled_count"
    info "Operators disabled" "$disabled_count"
    echo
  fi
}
install_plan_approval(){
  subs=$(oc get subs -A -o jsonpath='{range .items[*]}{@.metadata.namespace}{" "}{@.metadata.name}{"\n"}{end}')
  subs=($subs)
  length=${#subs[@]}
  for i in $( seq 0 2 $((length-2)) ); do
    ns=${subs[$i]}
    name=${subs[$i+1]}
    info "  ├─ $name subscription installPlanApproval" "$1"
    oc patch subscription -n $ns $name --type='json' -p=["{\"op\": \"replace\", \"path\": \"/spec/installPlanApproval\", \"value\":\"$1\"}"]
  done
}

operator_auto_upgrade(){
  step "Configuring operator auto-upgrade policy"
  case "$(yq '.day2.disable_operator_auto_upgrade' $config_file)" in
    true)
      warn "Operator auto-upgrade" "disabled (manual approval)"
      install_plan_approval "Manual"
      ;;
    false)
      info "Operator auto-upgrade" "enabled (automatic approval)"
      install_plan_approval "Automatic"
      ;;
    *)
      info "Operator auto-upgrade" "not configured (keeping defaults)"
      ;;
  esac
}

apply_extra_manifests(){
  step "Applying extra manifest files"
  extra_manifests=$(yq '.day2.extra_manifests' $config_file)
  if [ "$extra_manifests" == "null" ]; then
    warn "Extra manifests" "not configured"
  else
    all_paths_config=$(yq '.day2.extra_manifests|join(" ")' $config_file)
    all_paths=$(eval echo $all_paths_config)
    for d in $all_paths; do
      if [[ -d "$d" ]]; then
        readarray -t csr_files < <(find ${d} -type f \( -name "*.yaml" -o -name "*.yaml.j2" -o -name "*.sh" \) |sort)
        for ((i=0; i<${#csr_files[@]}; i++)); do
          file="${csr_files[$i]}"
          filename=$(basename "$file")
          case "$file" in
            *.yaml)
              output=$(oc apply -f $file 2>&1)
              if [[ $? -ne 0 ]]; then
                warn "  ├─ $filename" "failed"
                echo "$output"
              else
                info "  ├─ $filename" "applied"
              fi
              ;;
	          *.yaml.j2)
              output=$(jinja2 $file $config_file | oc apply -f - 2>&1)
              if [[ $? -ne 0 ]]; then
                warn "  ├─ $filename" "failed"
                echo "$output"
              else
                info "  ├─ $filename" "rendered & applied"
              fi
	            ;;
            *.sh)
              output=$(. $file 2>&1)
              if [[ $? -ne 0 ]]; then
                warn "  ├─ $filename" "failed"
                echo "$output"
              else
                info "  ├─ $filename" "executed"
              fi
              ;;
            *)
              warn "  ├─ $filename" "skipped (unknown type)"
              ;;
          esac
         done
      fi
    done
  fi
}

header "SNO Day2 Operations - Cluster Configuration"

step "Gathering cluster information"
cluster_info

separator
step "Applying day2 operations"

pause_mcp_update

node_tuning

operator_configs

operator_auto_upgrade

apply_extra_manifests

resume_mcp_update $delay_mcp_update

header "Day2 Operations Complete - Summary"
info "✅ Day2 configuration applied" "successfully"
info "📁 Kubeconfig location" "$cluster_workspace/auth/kubeconfig"
info "⚙️  Configuration file" "$config_file"
info "🎯 Target cluster" "$cluster_name"
info "🔧 OpenShift version" "$ocp_release"

separator
printf "${BOLD}${GREEN}🎉 Day2 operations completed successfully!${RESET}\n"
printf "${CYAN}Next Steps:${RESET}\n"
printf "  └─ Monitor cluster operators and workloads\n"
printf "  └─ Verify performance and tuning configurations\n"
printf "  └─ Check application deployments\n"
