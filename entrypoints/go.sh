#!/bin/bash

declare -gx SOURCEDIR
SOURCEDIR=$(dirname "$0")
readonly SOURCEDIR

# shellcheck disable=SC1091
# shellcheck source=util.sh
source "${SOURCEDIR}/util.sh"

declare -gx BASE
BASE="$(pwd)"
readonly BASE

snyk_gomod(){
  set_debug

  local manifest
  manifest=$(basename "$1")
  local project_path
  project_path=$(dirname "$1")

  local prefix
  prefix=${project_path#"${SNYK_TARGET}"}

  cd "${project_path}" || exit

  if [[ -f ".snyk.d/prep.sh" ]]; then
    use_custom
  elif [ ! -f "go.sum" ]; then

    (go mod tidy) &>> "${SNYK_LOG_FILE}"

  fi

  run_snyk "${manifest}" "gomodules" "${prefix}/${manifest}"

  cd "${BASE}" || exit
}

snyk_dep(){
  set_debug

  local manifest
  manifest=$(basename "$1")
  local project_path
  project_path=$(dirname "$1")

  local prefix
  prefix=${project_path#"${SNYK_TARGET}"}

  cd "${project_path}" || exit
  if [ -f ".snyk.d/prep.sh" ]; then
    use_custom
  else

    (dep ensure) &>> "${SNYK_LOG_FILE}"
  fi

  run_snyk "${manifest}" "dep (Go)" "${prefix}/${manifest}"

  cd "${BASE}" || exit
}

#snyk_vendor(){
#  set_debug

#  local manifest
#  manifest=$(basename "$1")
#  local project_path
#  project_path=$(dirname "$1")

#  local prefix
#  prefix=${project_path#"${SNYK_TARGET}"}

#  cd "${project_path}" || exit
#  if [ -f ".snyk.d/prep.sh" ]; then
#    use_custom
#  else
#    (govendor sync) &>> "${SNYK_LOG_FILE}"

#  fi

#    run_snyk "${manifest}" "govendor" "${prefix}/${manifest}"

#  cd "${BASE}" || exit
#}

go::main() {
  declare -x SNYK_LOG_FILE

  # global python settings here
  declare -x PIP_DISABLE_PIP_VERSION_CHECK=1

  cmdline "$@"

  set_debug

  SNYK_IGNORES=""
  snyk_excludes "${SNYK_TARGET}" SNYK_IGNORES
  readonly SNYK_IGNORES

  local gomod
  local go_dep
  local govendor

  readarray -t gomod < <(find "${SNYK_TARGET}" -type f -name "go.mod" $SNYK_IGNORES )
  readarray -t go_dep < <(find "${SNYK_TARGET}" -type f -name "Gopkg.lock" $SNYK_IGNORES )
  #readarray -t govendor < <(find "${SNYK_TARGET}" -type f -name "vendor.json" $SNYK_IGNORES )

  for gomod in "${gomod[@]}"; do
    snyk_gomod "${gomod}"
  done

  for go_dep in "${go_dep[@]}"; do
    snyk_dep "${go_dep}"
  done

#  for govendor in "${govendor[@]}"; do
#    snyk_vendor "${govendor}"
#  done

  output_json

  if [[ "${SNYK_JSON_STDOUT}" == 1 ]]; then
    stdout_json
  fi

}

go::main "$@"
