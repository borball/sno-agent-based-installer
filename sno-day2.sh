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

debug(){
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf "${MAGENTA}[DEBUG]${RESET} %s\n" "$1"
  fi
}

# Enhanced file copy function with validation and debugging
safe_copy(){
  local src="$1"
  local dest="$2"
  local description="${3:-file}"
  local copied_count=0
  local failed_count=0
  
  debug "safe_copy: src='$src' dest='$dest' desc='$description'"
  
  # Handle wildcard patterns
  if [[ "$src" == *"*"* ]]; then
    # Check if any files match the pattern
    local matches=($(ls $src 2>/dev/null))
    if [[ ${#matches[@]} -eq 0 ]]; then
      debug "No files match pattern: $src"
      return 0
    fi
    
    debug "Found ${#matches[@]} files matching pattern: $src"
    for file in "${matches[@]}"; do
      if [[ -f "$file" ]]; then
        local filename=$(basename "$file")
        if cp "$file" "$dest/" 2>/dev/null; then
          debug "  ✓ Copied: $filename"
          ((copied_count++))
        else
          warn "  ✗ Failed to copy: $filename" "ERROR"
          ((failed_count++))
        fi
      fi
    done
  else
    # Handle single file/directory
    if [[ -f "$src" ]]; then
      local filename=$(basename "$src")
      if cp "$src" "$dest" 2>/dev/null; then
        debug "  ✓ Copied: $filename"
        ((copied_count++))
      else
        warn "  ✗ Failed to copy: $filename" "ERROR"
        ((failed_count++))
      fi
    elif [[ -d "$src" ]]; then
      if cp -r "$src"/* "$dest/" 2>/dev/null; then
        debug "  ✓ Copied directory contents: $src"
        copied_count=$(find "$src" -type f | wc -l)
      else
        warn "  ✗ Failed to copy directory: $src" "ERROR"
        ((failed_count++))
      fi
    else
      debug "Source does not exist or is not accessible: $src"
    fi
  fi
  
  if [[ $copied_count -gt 0 ]]; then
    info "  └─ $description" "copied ($copied_count files)"
  fi
  
  if [[ $failed_count -gt 0 ]]; then
    warn "  └─ $description" "failed ($failed_count files)"
  fi
  
  return $failed_count
}

# Enhanced directory preparation function
prepare_workspace(){
  local workspace_path="$1"
  local description="${2:-workspace}"
  
  debug "prepare_workspace: path='$workspace_path' desc='$description'"
  
  if mkdir -p "$workspace_path" 2>/dev/null; then
    debug "  ✓ Created directory: $workspace_path"
  else
    error "Failed to create directory: $workspace_path" "ERROR"
    return 1
  fi
  
  # Clean existing content
  if [[ -d "$workspace_path" ]]; then
    local file_count=$(find "$workspace_path" -type f 2>/dev/null | wc -l)
    if [[ $file_count -gt 0 ]]; then
      debug "  Cleaning $file_count existing files from: $workspace_path"
      rm -rf "$workspace_path"/*
    fi
    info "$description directory" "prepared ($workspace_path)"
  fi
  
  return 0
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
  
  # Check templates directory
  if [[ ! -d "$templates" ]]; then
    error "Templates directory not found: $templates" "Check installation"
    validation_failed=true
  else
    debug "  ✓ Templates directory exists: $templates"
  fi
  
  if $validation_failed; then
    error "Environment validation failed" "Cannot continue"
    return 1
  fi
  
  debug "Environment validation passed"
  return 0
}

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
templates=$basedir/templates

# Validate environment before proceeding
if ! validate_environment; then
  exit 1
fi

cluster_name=$1; shift

if [ -z "$cluster_name" ]; then
  cluster_name=$(ls -t $basedir/instances |head -1)
  debug "Auto-selected cluster: $cluster_name"
fi

cluster_workspace=$basedir/instances/$cluster_name
day2_workspace=$cluster_workspace/day2

# Initialize day2 workspace with enhanced logging
debug "Initializing day2 workspace for cluster: $cluster_name"
debug "Cluster workspace: $cluster_workspace"
debug "Day2 workspace: $day2_workspace"

if ! prepare_workspace "$day2_workspace" "Day2 workspace"; then
  error "Failed to initialize day2 workspace" "$day2_workspace"
  exit 1
fi

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
    #don't block operation if there are uninstalled subscriptions
    #exit 1
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
      #don't block operation if there are CSV installation timeout
      #exit 1
      return
    fi
    ((i=i+1))
  done
}

ocp_release=$(oc version -o json|jq -r '.openshiftVersion')
ocp_y_version=$(echo $ocp_release | cut -d. -f 1-2)
export OCP_Y_VERSION=$ocp_y_release
export OCP_Z_VERSION=$ocp_release

pause_mcp_update(){
  if [ "$(yq '.update_control.pause_before_update' $config_file)" = "true" ]; then
    step "Pausing master machine config pool update"
    trap resume_mcp_update SIGINT SIGABRT SIGKILL
    oc patch --type=merge --patch='{"spec":{"paused":true}}' mcp/master
  else
    info "MCP update" "not paused"
    return
  fi

}

resume_mcp_update(){
  if [ "$(yq '.update_control.pause_before_update' $config_file)" = "true" ]; then
    delay_mcp_update=$(yq '.update_control.delay_after_update // 0' $config_file)

    if [[ ${delay_mcp_update} -gt 0 ]]; then
      step "Resuming master machine config pool update (delayed ${delay_mcp_update}s)"
      sleep ${delay_mcp_update}
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
  else
    return
  fi

}

cluster_tunings(){
  step "Configuring cluster tunings"
  if [[ "$(yq '.cluster_tunings' $config_file)" == "null" || "$(yq '.cluster_tunings' $config_file)" == "none" ]]; then
    warn "Cluster tunings" "disabled"
  else
    info "Cluster tunings" "enabled"
    cluster_tunings=$(yq '.cluster_tunings' $config_file)
    debug "Cluster tunings config: $cluster_tunings"
    
    # Prepare cluster tunings workspace
    local tunings_workspace="$day2_workspace/cluster-tunings"
    if ! prepare_workspace "$tunings_workspace" "Cluster tunings"; then
      error "Failed to prepare cluster tunings workspace" "$tunings_workspace"
      return 1
    fi
    
    # Check if source directory exists
    local source_dir="$templates/day2/cluster-tunings"
    if [[ ! -d "$source_dir" ]]; then
      warn "Cluster tunings source directory not found" "$source_dir"
      return 0
    fi
    
    debug "Processing cluster tunings from: $source_dir"
    local processed_count=0
    local failed_count=0
    
    # Process all files in cluster-tunings directory
    for file in "$source_dir"/*; do
      if [[ ! -f "$file" ]]; then
        debug "Skipping non-file: $file"
        continue
      fi
      
      local filename=$(basename "$file")
      debug "Processing cluster tuning file: $filename"
      
      case "$file" in
        *.sh)
          if safe_copy "$file" "$tunings_workspace/$filename" "Shell script ($filename)"; then
            info "  └─ $filename" "copied & executing"
            if . "$file"; then
              debug "  ✓ Successfully executed: $filename"
            else
              warn "  ✗ Failed to execute: $filename" "ERROR"
              ((failed_count++))
            fi
          else
            ((failed_count++))
          fi
          ;;
        *.yaml)
          if safe_copy "$file" "$tunings_workspace/$filename" "YAML manifest ($filename)"; then
            info "  └─ $filename" "copied & applying"
            local output
            if output=$(oc apply -f "$tunings_workspace/$filename" 2>&1); then
              debug "  ✓ Successfully applied: $filename"
              debug "    Output: $output"
            else
              warn "  ✗ Failed to apply: $filename" "ERROR"
              debug "    Error: $output"
              ((failed_count++))
            fi
          else
            ((failed_count++))
          fi
          ;;
        *.yaml.j2)
          local rendered_filename=$(echo "$filename" | sed 's/.j2//g')
          info "  └─ $filename" "rendering & applying"
          local output
          if output=$(jinja2 "$file" "$config_file" > "$tunings_workspace/$rendered_filename" 2>&1); then
            debug "  ✓ Successfully rendered: $filename -> $rendered_filename"
            if output=$(oc apply -f "$tunings_workspace/$rendered_filename" 2>&1); then
              debug "  ✓ Successfully applied: $rendered_filename"
              debug "    Output: $output"
            else
              warn "  ✗ Failed to apply rendered file: $rendered_filename" "ERROR"
              debug "    Error: $output"
              ((failed_count++))
            fi
          else
            warn "  ✗ Failed to render template: $filename" "ERROR"
            debug "    Error: $output"
            ((failed_count++))
          fi
          ;;
        *)
          debug "Skipping unknown file type: $filename"
          ;;
      esac
      ((processed_count++))
    done
    
    if [[ $processed_count -eq 0 ]]; then
      warn "No cluster tuning files found" "$source_dir"
    else
      info "Processed $processed_count cluster tuning files" "$(( processed_count - failed_count )) succeeded, $failed_count failed"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
      warn "Some cluster tuning operations failed" "Check logs above"
    fi
  fi
}

performance_profile(){
  info "Performance profile" "enabled"
  local profile=$(yq '.node_tunings.performance_profile.profile' $config_file)
  debug "Performance profile: $profile"
  
  # Prepare performance profile workspace
  local perf_workspace="$day2_workspace/node-tunings/performance-profile"
  if ! prepare_workspace "$perf_workspace" "Performance profile"; then
    error "Failed to prepare performance profile workspace" "$perf_workspace"
    return 1
  fi
  
  local source_template="$templates/day2/performance-profile/performance-profile-$profile.yaml.j2"
  local profile_default_file="$templates/cluster-profile-${profile}-${ocp_y_version}.yaml"
  
  debug "Source file: $source_template"
  debug "Template file: $profile_default_file"
  
  if [[ ! -f "$source_template" ]]; then
    error "Performance profile template not found" "$source_template"
    return 1
  fi
  
  if [[ ! -f "$profile_default_file" ]]; then
    error "Profile default file not found" "$profile_default_file"
    return 1
  fi
  
  debug "  Template validation passed"
  
  info "  └─ performance-profile-$profile.yaml.j2" "rendering & applying"
  
  local base_spec_file="$perf_workspace/performance-profile-$profile-base-spec.yaml"
  local profile_default_spec_file="$perf_workspace/performance-profile-${profile}-${ocp_y_version}-spec.yaml"
  local middle_merged_spec_file="$perf_workspace/performance-profile-$profile-middle-merged-spec.yaml"
  local user_spec_file="$perf_workspace/performance-profile-user-spec.yaml"
  local final_spec_file="$perf_workspace/performance-profile-$profile-final-spec.yaml"
  local output_file="$perf_workspace/performance-profile-final.yaml"

  # Extract spec from template, profile defaults, and user config
  debug "  Extracting base spec from template: $source_template"
  if ! jinja2 "$source_template" | yq '.spec' > "$base_spec_file"; then
    error "Failed to extract base spec from template" "$source_template"
    return 1
  fi
  
  debug "  Extracting profile defaults from: $profile_default_file"
  if ! yq '.node_tunings.performance_profile.spec' "$profile_default_file" > "$profile_default_spec_file"; then
    error "Failed to extract profile defaults" "$profile_default_file"
    return 1
  fi
  
  debug "  Extracting user overrides from: $config_file"
  if ! yq '.node_tunings.performance_profile.spec' "$config_file" > "$user_spec_file"; then
    error "Failed to extract user overrides" "$config_file"
    return 1
  fi

  # Merge 3 spec files: base <- profile_defaults <- user_overrides
  debug "  Merging base spec with profile defaults"
  if ! yq '. *=load("'$profile_default_spec_file'")' "$base_spec_file" > "$middle_merged_spec_file"; then
    error "Failed to merge base spec with profile defaults" ""
    return 1
  fi
  
  debug "  Applying user overrides to merged spec"
  if ! yq '. *=load("'$user_spec_file'")' "$middle_merged_spec_file" > "$final_spec_file"; then
    error "Failed to apply user overrides to merged spec" ""
    return 1
  fi

  # Generate the final performance profile with user config context
  debug "  Rendering final performance profile with user config context"
  if ! yq '.node_tunings.performance_profile' "$config_file" | jinja2 "$source_template" > "$output_file"; then
    error "Failed to render performance profile template" ""
    return 1
  fi
  
  # Apply the merged spec to the final output file
  debug "  Applying merged spec to final output file"
  local middle_output_file="$perf_workspace/performance-profile-middle.yaml"
  if ! yq '.spec = load("'$final_spec_file'")' "$output_file" > "$middle_output_file"; then
    error "Failed to apply merged spec to output file" ""
    return 1
  fi
  
  if ! cat "$middle_output_file" > "$output_file"; then
    error "Failed to finalize output file" ""
    return 1
  fi

  debug "  ✓ Successfully rendered performance profile template"
  debug "  Final output file: $output_file"
  
  # Validate final output file before applying
  if [[ ! -f "$output_file" ]]; then
    error "Final output file not found" "$output_file"
    return 1
  fi
  
  if ! yq eval '.' "$output_file" >/dev/null 2>&1; then
    error "Final output file contains invalid YAML" "$output_file"
    return 1
  fi
  
  debug "  ✓ Final output file validation passed"
  
  # Apply the rendered manifest
  local apply_output
  if apply_output=$(oc apply -f "$output_file" 2>&1); then
    debug "  ✓ Successfully applied performance profile"
    debug "    Output: $apply_output"
    info "  └─ Performance profile applied" "success"
  else
    error "  ✗ Failed to apply performance profile" "ERROR"
    debug "    Error: $apply_output"
    return 1
  fi
}

tuned_profiles(){
  info "Tuned profiles" "enabled"
  
  # Prepare tuned profiles workspace
  local tuned_workspace="$day2_workspace/node-tunings/tuned-profiles"
  if ! prepare_workspace "$tuned_workspace" "Tuned profiles"; then
    error "Failed to prepare tuned profiles workspace" "$tuned_workspace"
    return 1
  fi
  
  # Get all profiles from config
  local profiles
  readarray -t profiles < <(yq '.node_tunings.tuned_profile|keys[]|select(.!="enabled")' "$config_file" 2>/dev/null)
  if [[ ${#profiles[@]} -le 0 ]]; then
    warn "No tuned profiles configured" "skipping"
    return 0
  fi

  debug "Configured tuned profiles: ${profiles[@]}"
  local processed_count=0
  local failed_count=0
  
  # Process each profile
  for profile in "${profiles[@]}"; do
    debug "Processing tuned profile: $profile"

    local output_file="$tuned_workspace/tuned-$profile.yaml"
    
    local prefix="  ├─"
    if [[ $profile ==  ${profiles[-1]} ]]; then
       prefix="  └─"
    fi
    if [[ -f "$templates/day2/tuned/tuned-$profile.yaml" ]]; then
      local static_tempalte="$templates/day2/tuned/tuned-$profile.yaml"
      # Use static YAML file
      info "${prefix} $profile" "copying & applying using $(basename $static_template)"
      if safe_copy "$static_template" "$output_file" "Tuned profile ($profile)"; then
        local output
        if output=$(oc apply -f "$output_file" 2>&1); then
          debug "  ✓ Successfully applied tuned profile: $profile"
          debug "    Output: $output"
        else
          error "  ✗ Failed to apply tuned profile: $profile" "ERROR"
          debug "    Error: $output"
          ((failed_count++))
        fi
      else
        ((failed_count++))
      fi
    else
      if [[ -f "$templates/day2/tuned/tuned-$profile.yaml.j2" ]]; then
         jinja_template="$templates/day2/tuned/tuned-$profile.yaml.j2"
      else
         jinja_template="$templates/day2/tuned/tuned-generic.yaml.j2"
      fi
      # Use Jinja2 template
      info "${prefix} $profile" "rendering & applying using $(basename $jinja_template)"
      local output
      if output=$((echo "name: $profile"; yq ".node_tunings.tuned_profile.$profile" "$config_file") | jinja2 "$jinja_template" > "$output_file" 2>&1); then
        debug "  ✓ Successfully rendered tuned profile template: $profile"
        
        if output=$(oc apply -f "$output_file" 2>&1); then
          debug "  ✓ Successfully applied tuned profile: $profile"
          debug "    Output: $output"
        else
          error "  ✗ Failed to apply rendered tuned profile: $profile" "ERROR"
          debug "    Error: $output"
          ((failed_count++))
        fi
      else
        error "  ✗ Failed to render tuned profile template: $profile" "ERROR"
        debug "    Error: $output"
        ((failed_count++))
      fi
    fi
    
    ((processed_count++))
  done
  
  info "Processed $processed_count tuned profiles" "$(( processed_count - failed_count )) succeeded, $failed_count failed"
  
  if [[ $failed_count -gt 0 ]]; then
    warn "Some tuned profile operations failed" "Check logs above"
    return 1
  fi
}

node_tunings(){
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
      performance_profile
    else
      warn "Performance profile" "disabled"
    fi

    if [ "$(yq '.node_tunings.tuned_profile.enabled' $config_file)" = "true" ]; then
      tuned_profiles
    else
      warn "Tuned profile" "disabled"
    fi
  fi
}

operator_configs(){
  step "Configuring operator day2 configs"
  
  # Prepare operators workspace
  local operators_workspace="$day2_workspace/operators"
  if ! prepare_workspace "$operators_workspace" "Operators"; then
    error "Failed to prepare operators workspace" "$operators_workspace"
    return 1
  fi
  
  # Get all operator keys
  local keys
  readarray -t keys < <(yq ".operators|keys" "$config_file" 2>/dev/null | yq '.[]' 2>/dev/null)
  
  if [[ ${#keys[@]} -eq 0 ]]; then
    warn "No operators configured" "skipping"
    return 0
  fi
  
  debug "Found ${#keys[@]} operators in config: ${keys[*]}"
  local processed_operators=0
  local failed_operators=0

  for ((k=0; k<${#keys[@]}; k++)); do
    local key="${keys[$k]}"
    local enabled=$(yq ".operators.$key.enabled" "$config_file" 2>/dev/null)
    
    debug "Processing operator: $key (enabled: $enabled)"
    
    if [[ "$enabled" == "true" ]]; then
      info "$key operator" "processing"
      
      # Prepare operator-specific workspace
      local operator_workspace="$operators_workspace/$key"
      if ! prepare_workspace "$operator_workspace" "Operator ($key)"; then
        error "Failed to prepare workspace for operator: $key" "$operator_workspace"
        ((failed_operators++))
        continue
      fi
      
      local source_dir="$templates/day2/$key"
      debug "Source directory for $key: $source_dir"
      
      # Copy base operator files if they exist
      if [[ -d "$source_dir" ]]; then
        # Copy YAML files
        if ls "$source_dir"/*.yaml >/dev/null 2>&1; then
          safe_copy "$source_dir/*.yaml" "$operator_workspace" "YAML manifests for $key"
        fi

        # Copy shell scripts
        if ls "$source_dir"/*.sh >/dev/null 2>&1; then
          safe_copy "$source_dir/*.sh" "$operator_workspace" "Shell scripts for $key"
        fi

        # Copy Jinja2 templates
        if ls "$source_dir"/*.yaml.j2 >/dev/null 2>&1; then
          safe_copy "$source_dir/*.yaml.j2" "$operator_workspace" "Jinja2 templates for $key"
        fi
        
      fi
      
      # Process manifest folders
      local manifest_folders="$source_dir"
      local has_custom_profiles=false
      
      # Check for custom day2 profiles
      local day2_config=$(yq ".operators.$key.day2" "$config_file" 2>/dev/null)
      if [[ "$day2_config" != "null" ]]; then
        debug "Operator $key has custom day2 profiles"
        has_custom_profiles=true
        
        local profile_names
        profile_names=$(yq ".operators.$key.day2[].profile" "$config_file" 2>/dev/null)
        manifest_folders=""
        
        for profile_name in $profile_names; do
          debug "Processing profile: $profile_name for operator: $key"
          local profile_source="$source_dir/$profile_name"
          local profile_workspace="$operator_workspace/$profile_name"
          
          if [[ -d "$profile_source" ]]; then
            if prepare_workspace "$profile_workspace" "Profile ($profile_name)"; then
              safe_copy "$profile_source/*" "$profile_workspace" "Profile files for $key/$profile_name"
              manifest_folders="$manifest_folders $profile_source"
            fi
          else
            warn "Profile directory not found: $profile_source" "skipping"
          fi
        done
        
        # Add base directory back to manifest folders
        manifest_folders="$source_dir $manifest_folders"
      else
        # Check for default profile
        local default_source="$source_dir/default"
        if [[ -d "$default_source" ]]; then
          debug "Using default profile for operator: $key"
          local default_workspace="$operator_workspace/default"
          if prepare_workspace "$default_workspace" "Default profile"; then
            safe_copy "$default_source/*" "$default_workspace" "Default profile files for $key"
            manifest_folders="$manifest_folders $default_source"
          fi
        fi
      fi
      
      debug "Manifest folders for $key: $manifest_folders"
      info "  └─ manifest_folders" "$manifest_folders"
      
      # Process each manifest folder
      local operator_failed=false
      for manifest_folder in $manifest_folders; do
        
        if [[ ! -d "$manifest_folder" ]]; then
          debug "Manifest folder not found: $manifest_folder"
          continue
        fi
        
        debug "Processing manifest folder: $manifest_folder"
         # Determine workspace folder for the manifest_folder
         local workspace=$(basename "$manifest_folder")
         local workspace_folder
         
         # If manifest_folder is the source template directory, use operator_workspace directly
         if [[ "$manifest_folder" == "$source_dir" ]]; then
           workspace_folder="$operator_workspace"
           debug "Using operator workspace directly: $workspace_folder"
         else
           # For profile-specific folders (e.g., default, custom profiles)
           workspace_folder="$operator_workspace/$workspace"
           debug "Using profile workspace: $workspace_folder"
         fi
         
         if [[ ! -d "$workspace_folder" ]]; then
           error "Workspace folder not found: $workspace_folder" "ERROR"
           continue
         fi

        # if kustomization.yaml exists, then apply it
        if [[ -f "$workspace_folder/kustomization.yaml" ]]; then
          info "    └─ applying kustomization.yaml"

          #if any .j2 exists, then render it
          for f in "$workspace_folder"/*.yaml.j2; do
            if [[ -f "$f" ]]; then
              info "    └─ rendering $f"
              debug "Using custom data for $key template: $f"
              yq ".operators.$key.data" "$config_file" | jinja2 "$f" > "$workspace_folder/$(basename "$f" .j2)"
            fi
          done
          debug "Applying kustomization.yaml: $workspace_folder"
          oc apply -k "$workspace_folder"
        else
          # Apply YAML files
          for f in "$workspace_folder"/*.yaml; do
            if [[ -f "$f" ]]; then
              local yaml_name=$(basename "$f")
              info "    └─ applying $yaml_name"
              local output
              if output=$(oc apply -f "$f" 2>&1); then
                debug "  ✓ Successfully applied: $yaml_name"
                debug "    Output: $output"
              else
                warn "  ✗ Failed to apply: $yaml_name" "ERROR"
                debug "    Error: $output"
                operator_failed=true
              fi
            fi
          done

          # Apply Jinja2 templates
          for f in "$workspace_folder"/*.yaml.j2; do
            if [[ -f "$f" ]]; then
              local template_name=$(basename "$f")
              info "    └─ rendering & applying $template_name"
              
              # Check if operator has custom data
              local data_file=$(yq ".operators.$key.data" "$config_file" 2>/dev/null)
              local output
              
              if [[ "$data_file" != "null" ]]; then
                debug "Using custom data for $key template: $template_name"
                if output=$(yq ".operators.$key.data" "$config_file" | jinja2 "$f" | oc apply -f - 2>&1); then
                  debug "  ✓ Successfully rendered & applied with custom data: $template_name"
                  debug "    Output: $output"
                else
                  warn "  ✗ Failed to render/apply with custom data: $template_name" "ERROR"
                  debug "    Error: $output"
                  operator_failed=true
                fi
              else
                debug "Using config file for $key template: $template_name"
                if output=$(jinja2 "$f" "$config_file" | oc apply -f - 2>&1); then
                  debug "  ✓ Successfully rendered & applied: $template_name"
                  debug "    Output: $output"
                else
                  warn "  ✗ Failed to render/apply: $template_name" "ERROR"
                  debug "    Error: $output"
                  operator_failed=true
                fi
              fi
            fi
          done
        fi

        # Execute shell scripts
        for f in "$workspace_folder"/*.sh; do
          if [[ -f "$f" ]]; then
            local script_name=$(basename "$f")
            info "    └─ executing $script_name"
            local output
            if output=$("$f" "$config_file" 2>&1); then
              debug "  ✓ Successfully executed: $script_name"
              debug "    Output: $output"
            else
              warn "  ✗ Failed to execute: $script_name" "ERROR"
              debug "    Error: $output"
              operator_failed=true
            fi
          fi
        done
      done
      
      if $operator_failed; then
        warn "Operator $key had some failures" "check logs above"
        ((failed_operators++))
      else
        info "  └─ Operator $key" "completed successfully"
      fi
      
      ((processed_operators++))
    else
      debug "Operator $key is disabled, skipping"
    fi
  done
  
  info "Processed $processed_operators operators" "$(( processed_operators - failed_operators )) succeeded, $failed_operators failed"
  
  if [[ $failed_operators -gt 0 ]]; then
    warn "Some operator configurations failed" "Check logs above"
  fi
}

install_plan_approval(){
  debug "install_plan_approval: Setting installPlanApproval to '$1'"
  
  subs=$(oc get subs -A -o jsonpath='{range .items[*]}{@.metadata.namespace}{" "}{@.metadata.name}{"\n"}{end}')
  debug "Raw subscription data: $subs"
  
  subs=($subs)
  length=${#subs[@]}
  debug "Found ${#subs[@]} subscription elements (${length} total array elements)"
  debug "Subscription array: ${subs[*]}"
  
  if [[ $length -eq 0 ]]; then
    debug "No subscriptions found to update"
    return 0
  fi
  
  local processed_count=0
  local failed_count=0
  
  for i in $( seq 0 2 $((length-2)) ); do
    ns=${subs[$i]}
    name=${subs[$i+1]}
    debug "Processing subscription $((processed_count + 1)): namespace='$ns', name='$name'"
    
    local prefix="  ├─"
    if [[ $i -eq $((length-2)) ]]; then
      prefix="  └─"
    fi
    info "${prefix} $name subscription installPlanApproval" "$1"
    
    local output
    # Try operators.coreos.com API group first (most common for OpenShift subscriptions)
    if output=$(oc patch subscription.operators.coreos.com -n $ns $name --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/installPlanApproval\", \"value\":\"$1\"}]" 2>&1); then
      debug "  ✓ Successfully updated subscription: $name in namespace: $ns (operators.coreos.com)"
      debug "    Output: $output"
      ((processed_count++))
    else
      debug "    Failed with operators.coreos.com, trying apps.open-cluster-management.io: $output"
      # Fallback to open-cluster-management API group
      if output=$(oc patch subscription.apps.open-cluster-management.io -n $ns $name --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/installPlanApproval\", \"value\":\"$1\"}]" 2>&1); then
        debug "  ✓ Successfully updated subscription: $name in namespace: $ns (apps.open-cluster-management.io)"
        debug "    Output: $output"
        ((processed_count++))
      else
        warn "  ✗ Failed to update subscription: $name in namespace: $ns" "ERROR"
        debug "    Error (operators.coreos.com): Failed with operators.coreos.com API group"
        debug "    Error (apps.open-cluster-management.io): $output"
        ((failed_count++))
      fi
    fi
  done
  
  debug "install_plan_approval completed: $processed_count succeeded, $failed_count failed"
  
  if [[ $failed_count -gt 0 ]]; then
    warn "Some subscription updates failed" "Check logs above"
    return 1
  fi
  
  return 0
}

operator_auto_upgrade(){
  step "Configuring operator auto-upgrade policy"
  case "$(yq '.update_control.disable_operator_auto_upgrade' $config_file)" in
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

extra_manifests(){
  step "Applying extra manifest files"
  
  local extra_manifests_config=$(yq '.extra_manifests.day2' "$config_file" 2>/dev/null)
  if [[ "$extra_manifests_config" == "null" ]]; then
    warn "Extra manifests" "not configured"
    return 0
  fi
  
  # Prepare extra manifests workspace
  local extra_workspace="$day2_workspace/extra-manifests"
  if ! prepare_workspace "$extra_workspace" "Extra manifests"; then
    error "Failed to prepare extra manifests workspace" "$extra_workspace"
    return 1
  fi
  
  # Get all configured paths
  local all_paths_config
  all_paths_config=$(yq '.extra_manifests.day2|join(" ")' "$config_file" 2>/dev/null)
  local all_paths
  all_paths=$(eval echo "$all_paths_config")
  
  debug "Extra manifest paths: $all_paths"
  
  if [[ -z "$all_paths" ]]; then
    warn "No extra manifest paths configured" "skipping"
    return 0
  fi
  
  local processed_dirs=0
  local failed_dirs=0
  local total_processed=0
  local total_failed=0
  
  for d in $all_paths; do
    debug "Processing extra manifest directory: $d"
    
    if [[ ! -d "$d" ]]; then
      warn "Extra manifest directory not found: $d" "skipping"
      ((failed_dirs++))
      continue
    fi
    
    info "Processing extra manifests from" "$d"
    
    # Create subdirectory in workspace
    local dir_basename=$(basename "$d")
    local dir_workspace="$extra_workspace/$dir_basename"
    if ! prepare_workspace "$dir_workspace" "Extra manifests ($dir_basename)"; then
      warn "Failed to prepare workspace for: $d" "skipping"
      ((failed_dirs++))
      continue
    fi
    
    # Copy all files to workspace
    if ! safe_copy "$d/*" "$dir_workspace" "Extra manifest files from $d"; then
      warn "Failed to copy files from: $d" "continuing anyway"
    fi
    
    # Find and process all relevant files
    local manifest_files
    readarray -t manifest_files < <(find "$d" -type f \( -name "*.yaml" -o -name "*.yaml.j2" -o -name "*.sh" \) | sort 2>/dev/null)
    
    debug "Found ${#manifest_files[@]} manifest files in $d"
    
    if [[ ${#manifest_files[@]} -eq 0 ]]; then
      warn "No manifest files found in: $d" "skipping"
      continue
    fi
    
    local dir_processed=0
    local dir_failed=0

    for file in "${manifest_files[@]}"; do
      local filename=$(basename "$file")
      debug "Processing extra manifest file: $filename"
      
      case "$file" in
        *.yaml)
          info "  ├─ $filename" "applying"
          local output
          if output=$(oc apply -f "$file" 2>&1); then
            debug "  ✓ Successfully applied: $filename"
            debug "    Output: $output"
            ((dir_processed++))
          else
            warn "  ├─ $filename" "failed"
            debug "    Error: $output"
            echo "$output"
            ((dir_failed++))
          fi
          ;;
        *.yaml.j2)
          info "  ├─ $filename" "rendering & applying"
          local output
          if output=$(jinja2 "$file" "$config_file" | oc apply -f - 2>&1); then
            debug "  ✓ Successfully rendered & applied: $filename"
            debug "    Output: $output"
            ((dir_processed++))
          else
            warn "  ├─ $filename" "failed"
            debug "    Error: $output"
            echo "$output"
            ((dir_failed++))
          fi
          ;;
        *.sh)
          info "  ├─ $filename" "executing"
          local output
          if output=$(. "$file" 2>&1); then
            debug "  ✓ Successfully executed: $filename"
            debug "    Output: $output"
            ((dir_processed++))
          else
            warn "  ├─ $filename" "failed"
            debug "    Error: $output"
            echo "$output"
            ((dir_failed++))
          fi
          ;;
        *)
          warn "  ├─ $filename" "skipped (unknown type)"
          ;;
      esac
    done
    
    info "  └─ Directory $dir_basename" "processed $dir_processed files, $dir_failed failed"
    ((total_processed += dir_processed))
    ((total_failed += dir_failed))
    
    if [[ $dir_failed -eq 0 ]]; then
      ((processed_dirs++))
    else
      ((failed_dirs++))
    fi
  done
  
  info "Extra manifests summary" "$processed_dirs directories succeeded, $failed_dirs failed"
  info "File processing summary" "$total_processed files succeeded, $total_failed failed"
  
  if [[ $failed_dirs -gt 0 || $total_failed -gt 0 ]]; then
    warn "Some extra manifest operations failed" "Check logs above"
  fi
}

header "SNO Day2 Operations - Cluster Configuration"

# Show debug status
if [[ "${DEBUG:-false}" == "true" ]]; then
  info "Debug mode" "ENABLED (set DEBUG=false to disable)"
else
  info "Debug mode" "disabled (set DEBUG=true to enable detailed logging)"
fi

debug "Script execution started at: $(date)"
debug "Day2 workspace location: $day2_workspace"
debug "Templates directory: $templates"
debug "Configuration file: $config_file"
debug "OpenShift version: ${ocp_release:-unknown}"

step "Gathering cluster information"
cluster_info

separator
step "Applying day2 operations"

pause_mcp_update
cluster_tunings
node_tunings
operator_configs
operator_auto_upgrade
extra_manifests
resume_mcp_update

header "Day2 Operations Complete - Summary"

debug "Script execution completed at: $(date)"

# Calculate workspace usage
workspace_size="unknown"
if command -v du >/dev/null 2>&1; then
  workspace_size=$(du -sh "$day2_workspace" 2>/dev/null | cut -f1 || echo "unknown")
fi

file_count="unknown"
if [[ -d "$day2_workspace" ]]; then
  file_count=$(find "$day2_workspace" -type f 2>/dev/null | wc -l || echo "unknown")
fi

info "✅ Day2 configuration applied" "successfully"
info "📁 Kubeconfig location" "$cluster_workspace/auth/kubeconfig"
info "⚙️  Configuration file" "$config_file"
info "🎯 Target cluster" "$cluster_name"
info "🔧 OpenShift version" "$ocp_release"
info "📂 Workspace location" "$day2_workspace"
info "📊 Workspace size" "$workspace_size ($file_count files)"

debug "Final workspace contents:"
if [[ "${DEBUG:-false}" == "true" ]] && command -v tree >/dev/null 2>&1; then
  tree "$day2_workspace" 2>/dev/null || find "$day2_workspace" -type f 2>/dev/null | head -20
fi

separator
printf "${BOLD}${GREEN}🎉 Day2 operations completed successfully!${RESET}\n"
printf "${CYAN}Next Steps:${RESET}\n"
printf "  └─ Monitor cluster operators and workloads\n"
printf "  └─ Verify performance and tuning configurations\n"
printf "  └─ Check application deployments\n"
printf "  └─ Review backup files in: ${YELLOW}%s${RESET}\n" "$day2_workspace"
if [[ "${DEBUG:-false}" != "true" ]]; then
  printf "  └─ For detailed debugging, run with: ${YELLOW}DEBUG=true %s${RESET}\n" "$0"
fi
