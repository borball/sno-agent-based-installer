#!/bin/bash

# Enhanced output functions
info(){
  local msg1="$1"
  local msg2="$2"
  # Calculate display length accounting for multi-byte characters
  local len=${#msg1}
  local padding=$((80 - len))
  if [ $padding -lt 0 ]; then padding=1; fi
  printf "${GREEN}✓${RESET} %s%*s${GREEN}%s${RESET}\n" "$msg1" "$padding" "" "$msg2"
}
  
warn(){
  local msg1="$1"
  local msg2="$2"
  local len=${#msg1}
  local padding=$((80 - len))
  if [ $padding -lt 0 ]; then padding=1; fi
  printf "${YELLOW}⚠${RESET} %s%*s${YELLOW}%s${RESET}\n" "$msg1" "$padding" "" "$msg2"
}

error(){
  local msg1="$1"
  local msg2="$2"
  local len=${#msg1}
  local padding=$((80 - len))
  if [ $padding -lt 0 ]; then padding=1; fi
  printf "${RED}✗${RESET} %s%*s${RED}%s${RESET}\n" "$msg1" "$padding" "" "$msg2"
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

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

tmp_workspace="$(mktemp -d)"
config_file="config-sno130.yaml"
ocp_y_version="4.18"
templates="$basedir/../../templates"
day2_workspace="$tmp_workspace/day2"
performance_profile_workspace="$day2_workspace/node-tunings/performance-profile"

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
  
  info "  └─ performance-profile-$profile.yaml.j2" "rendering & applying"
  
  local base_spec_file="$perf_workspace/performance-profile-$profile-base-spec.yaml"
  local profile_default_spec_file="$templates/cluster-profile-${profile}-${ocp_y_version}-spec.yaml"
  local middle_merged_spec_file="$perf_workspace/performance-profile-$profile-middle-merged-spec.yaml"
  local user_spec_file="$perf_workspace/performance-profile-user-spec.yaml"
  local final_spec_file="$perf_workspace/performance-profile-$profile-final-spec.yaml"
  local output_file="$perf_workspace/performance-profile-final.yaml"

  jinja2 "$source_template" | yq '.spec' > "$base_spec_file"
  yq '.node_tunings.performance_profile.spec' "$profile_default_file" > "$profile_default_spec_file"
  yq '.node_tunings.performance_profile.spec' "$config_file" > "$user_spec_file"

  # merge 3 spec files
  yq '. *=load("'$profile_default_spec_file'")' "$base_spec_file" > "$middle_merged_spec_file"

  yq '. *=load("'$user_spec_file'")' "$middle_merged_spec_file" > "$final_spec_file"

  cat $final_spec_file 
  separator
  yq '.node_tunings.performance_profile' $config_file |jinja2 "$source_template" > "$output_file"

  cat $output_file
  # todo: set output_file.spec to final_spec_file
  local temp_output_file="$perf_workspace/performance-profile-temp.yaml"
  yq '.spec = load("'$final_spec_file'")' "$output_file" > "$temp_output_file"
  mv "$temp_output_file" "$output_file"

  separator
  cat $output_file

}

performance_profile
