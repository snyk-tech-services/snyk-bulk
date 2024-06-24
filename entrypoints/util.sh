#!/bin/bash

# shellcheck disable=SC1091
# shellcheck source=cmdline.sh
source "${SOURCEDIR}/cmdline.sh"

declare -gx SNYK_INTEGRATION_NAME SNYK_INTEGRATION_VERSION
SNYK_INTEGRATION_NAME="cse-snyk-bulk"
SNYK_INTEGRATION_VERSION=$(cat "${SOURCEDIR}/version_info | head -n1")

set_debug(){
  if [[ "${SNYK_BULK_DEBUG}" == 1 ]]; then
    set -x
  fi
}

echo_file() {
  #setDebug

  echo "$1"
  #echo "$BASE"
  #echo "$SOURCEDIR"
}

run_snyk() {
  local manifest pkg_manager project
  manifest="${1}"
  pkg_manager="${2}"
  project="${3}"

  if [[ "${SNYK_TEST}" == 1 ]]; then
    snyk_cmd 'test' "${manifest}" "${pkg_manager}" "${project}"
  fi

  if [[ "${SNYK_MONITOR}" == 1 ]]; then
    snyk_cmd 'monitor' "${manifest}" "${pkg_manager}" "${project}"
  fi

}

snyk_cmd(){
  set_debug
  if [[ "${SNYK_BULK_DEBUG}" == 1 ]]; then
    SNYK_DEBUG="--debug"
  else
    SNYK_DEBUG=""
  fi
  local snyk_action manifest pkg_manager project
  snyk_action="${1}"
  manifest="${2}"
  pkg_manager="${3}"
  project="${4}"

  if [[ ${project::1} == "/" ]]; then
    project="${SNYK_BASENAME}${project}"
  else
    project="${SNYK_BASENAME}/${project}"
  fi

  local severity_level fail_on remote_repo

  severity_level="${SNYK_SEVERITY}"  
  fail_on="${SNYK_FAIL}"

  SNYK_PARAMS=(--file="${manifest}" \
    --project-name="${project}" \
    --package-manager="${pkg_manager}" \
    --severity-threshold="${severity_level}" \
    --fail-on="${fail_on}" )
  
  if [[ "${SNYK_BULK_DEBUG}" == 1 ]]; then
    SNYK_PARAMS+=("--debug")
  fi


  if [[ "${SNYK_REMOTE_REPO_URL}" != 0 ]]; then
    SNYK_PARAMS+=("--remote-repo-url=${SNYK_REMOTE_REPO_URL}")
  fi

  if [[ ${#SNYK_EXTRA_OPTIONS[@]} -gt 0 ]]; then
    SNYK_PARAMS+=("${SNYK_EXTRA_OPTIONS[@]}")
  fi

  mkdir -p "${SNYK_JSON_TMP}/${snyk_action}/pass"
  mkdir -p "${SNYK_JSON_TMP}/${snyk_action}/fail"

  # shellcheck disable=SC2086
  project_clean="$(echo ${project} | tr '/' '-' | tr ' ' '-' )"
  
  project_json_fail="${SNYK_JSON_TMP}/${snyk_action}/fail/$(basename "${0}")-${project_clean}.json"
  project_json_pass="${SNYK_JSON_TMP}/${snyk_action}/pass/$(basename "${0}")-${project_clean}.json"


  if [[ ${snyk_action} == "monitor" ]]; then
    snyk monitor --json \
      "${SNYK_PARAMS[@]}" > "${project_json_fail}"
    if [ "${PIPESTATUS[0]}" == '0' ]; then
      mv "${project_json_fail}" "${project_json_pass}"
    fi

  else
    snyk test --json-file-output="${project_json_fail}" \
      "${SNYK_PARAMS[@]}"
    if [ $? == '0' ]; then
      mv "${project_json_fail}" "${project_json_pass}"
    fi
  fi

  
}

snyk_excludes(){
  set_debug
  local target="${1}"
  local -n EXCLUDES=$2

  if [ -f "${target}/.snyk.d/exclude" ]
  then
    local -a exclude_file
    local path
  
    readarray -t exclude_file < "${target}/.snyk.d/exclude"
    EXCLUDES='! -path */node_modules/* ! -path */snyktmp/*'
    for path in "${exclude_file[@]//#*/}"; do
      # very pedantic that we don't want to accidentally render this glob
      if [[ -n "${path}" ]]; then
        EXCLUDES+=' ! -path *'
        EXCLUDES+="${path}"
        EXCLUDES+='*'
      fi
    done
  else
    EXCLUDES='! -path */node_modules/* ! -path */snyktmp/* ! -path */vendor/* ! -path */submodules/*'
  fi
  
  # this adds any entrypoint specific excludes, ie a python.sh-exclude file will be evaluated here
  if [ -f "${target}/.snyk.d/$(basename "${0}")-exclude" ]
  then
    local -a lang_exclude_file
    local lang_path
  
    readarray -t lang_exclude_file < "${target}/.snyk.d/$(basename "${0}")-exclude"
    for lang_path in "${lang_exclude_file[@]//#*/}"; do
      # very pedantic that we don't want to accidentally render this glob
      if [[ -n "${lang_path}" ]]; then
        EXCLUDES+=' ! -path *'
        EXCLUDES+="${lang_path}"
        EXCLUDES+='*'
      fi
    done
  fi
}

output_json(){
  set_debug

  local -a jsonfiles

  local timestamp

  readarray -t jsonfiles < <(find "${SNYK_JSON_TMP}" -type f -name "*.json")

  for jfile in "${jsonfiles[@]}"; do
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    ( echo "${timestamp}|  ${jfile}" >> "${SNYK_LOG_FILE}" ) 2>&1 | tee -a "${SNYK_LOG_FILE}"
  done
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  ( echo "${timestamp}|  Total Projects Tested/Monitored: ${#jsonfiles[@]}" >> "${SNYK_LOG_FILE}" ) 2>&1 | tee -a "${SNYK_LOG_FILE}"

}

stdout_json(){
  local entrypoint
  entrypoint=$(basename "${0}")

  local -a jsonfiles
  readarray -t jsonfiles < <(find "${SNYK_JSON_TMP}" -type f -name "${entrypoint}*.json")
  
  json_file="["
  json_delim=""
  for jfile in "${jsonfiles[@]}"; do
    file_contents=$(cat ${jfile})
    if [[ -n $file_contents ]]; then
      json_file+="${json_delim}${file_contents}"
      json_delim=","
    fi
  done
  json_file+="]"

  printf '%s' "${json_file}"

}

stdout_test_count(){
  local entrypoint
  entrypoint=$(basename "${0}")

  local -a tests
  readarray -t tests < <(find "${SNYK_JSON_TMP}/test" -type f -name "${entrypoint}*.json")

  echo "Tests Performed: ${#tests[@]}"
  
}

use_custom(){
  # this is a stub function for now

  if [ -f .snyk.d/prep.sh ]; then
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    ( echo "${timestamp}|  Custom Script found and starting execution for : $${project_path}" >> "${SNYK_LOG_FILE}" ) 2>&1 | tee -a "${SNYK_LOG_FILE}" 
    /bin/bash .snyk.d/prep.sh
    return 0
  else
    return 1
  fi
}