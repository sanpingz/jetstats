#!/usr/bin/env bash
# Build jtop tool
#
# Version 0.1.1
#
# Authors:
#  - Calvin Zhang
#
# Usage:
#   LOG_LEVEL=3 bash ./jetbuild -m 0863af_berwan_dev_2


### Configuration
#####################################################################

# Environment variables and their defaults
LOG_LEVEL="${LOG_LEVEL:-3}"  # 4 = trace -> 0 = error
LOG_FILE="${LOG_FILE}"  # replace with a specified log file

# Commandline options. This defines the usage page, and is used to parse cli opts & defaults from.
# The parsing is unforgiving so be precise in your syntax
read -r -d '' usage <<-'EOF'
  -v   [arg] Deb version, e.g. 1.0.1.
  -h         Print a help message and exit.
EOF

# Set magic variables for current file and its directory.
# BASH_SOURCE[0] is used so we can display the current file even if it is sourced by a parent script.
# If you need the script that was executed, consider using $0 instead.
readonly __dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly __name="$(basename "${BASH_SOURCE[0]}")"
readonly __file="${__dir}/${__name}"

readonly BUILD_DIR="${__dir}/build"
readonly DIST_DIR="${__dir}/dist"

### Helper Functions
#####################################################################

[[ -n "${LOG_FILE}" ]] && mkdir -p "$(dirname "${LOG_FILE}")"

function _fmt() {
    local msg
    msg="$(date -u +"%Y-%m-%d %H:%M:%S") [${1}] ${*:2}"
    if [ -z "${LOG_FILE}" ]; then
        echo "${msg}" 2>&1
    else
        echo "${msg}" >> ${LOG_FILE} 2>&1
    fi
}

function error()     { _fmt error "${@}" || true; exit 1; }
function warning()   { [[ "${LOG_LEVEL}" -ge 1 ]] && _fmt warning "${@}" || true; }
function info()      { [[ "${LOG_LEVEL}" -ge 2 ]] && _fmt info "${@}" || true; }
function debug()     { [[ "${LOG_LEVEL}" -ge 3 ]] && _fmt debug "${@}" || true; }
function trace()     { [[ "${LOG_LEVEL}" -ge 4 ]] && _fmt trace "${@}" || true; }

function help() {
    echo "" 1>&2
    echo " ${*}" 1>&2
    echo "" 1>&2
    echo "  ${usage}" 1>&2
    echo "" 1>&2
    exit 1
}

function cleanup_before_exit() {
    # Clean up the children process at exit
    pkill -P $$ || true
    debug "Cleaning up. Done"
}
trap cleanup_before_exit EXIT


### Parse commandline options
#####################################################################

# Translate usage string -> getopts arguments, and set $arg_<flag> defaults
while read line; do
    opt="$(echo "${line}" |awk '{print $1}' |sed -e 's#^-##')"
    if ! echo "${line}" |egrep '\[.*\]' >/dev/null 2>&1; then
        init="0" # it's a flag. init with 0
    else
        opt="${opt}:" # add : if opt has arg
        init=""  # it has an arg. init with ""
    fi
    opts="${opts}${opt}"

    varname="arg_${opt:0:1}"
    if ! echo "${line}" |egrep '\. Default=' >/dev/null 2>&1; then
        eval "${varname}=\"${init}\""
    else
        match="$(echo "${line}" |sed 's#^.*Default=\(\)#\1#g')"
        eval "${varname}=\"${match}\""
    fi
done <<< "${usage}"

# Reset in case getopts has been used previously in the shell.
OPTIND=1

# Overwrite $arg_<flag> defaults with the actual CLI options
while getopts "${opts}" opt; do
    line="$(echo "${usage}" |grep "\-${opt}")"

    [ "${opt}" = "?" ] && help "Invalid use of script: ${*} "
    varname="arg_${opt:0:1}"
    default="${!varname}"

    value="${OPTARG}"
    if [ -z "${OPTARG}" ] && [ "${default}" = "0" ]; then
        value="1"
    fi

    eval "${varname}=\"${value}\""
    debug "Argument ${varname} = ($default) -> ${!varname}"
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift


### Switches (like -d for debug mode, -h for showing help page)
#####################################################################

# debug mode
if [[ "${arg_d}" = "1" ]]; then
    set -o xtrace
    LOG_LEVEL="4"
fi

# help mode
if [[ "${arg_h}" = "1" ]]; then
    # Help exists with code 1
    help "Help using ${0}"
fi


### Validation (decide what's required for running your script and error out)
#####################################################################

# [[ -z "${arg_v}" ]]     && help    "Deployment version with -v is required."
[[ -z "${arg_v}" ]]     && error "Deb version is required."
[[ -z "${LOG_LEVEL}" ]] && error "Cannot continue without LOG_LEVEL."


### Runtime
#####################################################################

# Exit on error. Append ||true if you expect an error.
# `set` is safer than relying on a shebang like `#!/bin/bash -e` because that is neutralized
# when someone runs your script as `bash yourscript.sh`
set -o errexit
set -o nounset

# Bash will remember & return the highest exitcode in a chain of pipes.
# This way you can catch the error in case mysqldump fails in `mysqldump |gzip`
set -o pipefail

info "Running on ${OSTYPE}"

debug "__dir: ${__dir}"
debug "__file: ${__file}"
debug "__name: ${__name}"

readonly NAME="jetstats"
readonly ARCH="arm64"
readonly VERSION="${arg_v}"


### User Defined Functions
#####################################################################
# add function here

function main() {
    local dist_name="${NAME}_${VERSION}_${ARCH}"
    local build_dir="${BUILD_DIR}/${dist_name}"
    local target_dir="${build_dir}/opt/${NAME}"
    local bin_dir="${build_dir}/usr/local/bin"

    info "Start building deb ${dist_name} ..."

    rm -rf "${build_dir}"
    mkdir -p "${build_dir}/DEBIAN" "${target_dir}" "${DIST_DIR}"

    cat > "${build_dir}/DEBIAN/control" <<-EOF
Package: ${NAME}
Version: ${VERSION}
Section: base
Priority: optional
Architecture: ${ARCH}
Depends: python3
Maintainer: Calvin Zhang <@jetdev.com>
Description: Jetson Monitor
 System monitoring utility for Nvidia Jetson
EOF
    (
        cd "${__dir}" \
        && cp -rf jtop "${target_dir}/" \
        && cp -rf scripts "${target_dir}/" \
        && cp deb/jtop "${bin_dir}/"
    )
    chmod +x "${bin_dir}/"*

    (
        cd "${BUILD_DIR}" \
        && dpkg-deb --build "${dist_name}" \
        && mv "${dist_name}.deb" "${DIST_DIR}"
    )

    info "Success"
}

### Main Function
#####################################################################
main
