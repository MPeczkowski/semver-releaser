#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

minor_keywords=("feat" "feature")
patch_keywords=("patch" "fix")

###################################################################
# Don't modify this part of variables - it might break the script #
###################################################################

# Modified during runtime (
suggested_version_major=0
suggested_version_minor=0
suggested_version_patch=1

debug_mode='false'

# Static variables
readonly REQUIRED_PACKAGES=(git tail getopt)
####################################################################
#                   Functions part                                 #
####################################################################

function return_tag() {
  printf "%d.%d.%d" "${suggested_version_major}" "${suggested_version_minor}" "${suggested_version_patch}"
}

function err_msg() {
  printf "\033[0;31mError\033[0m: %s \n" "${@}" >&2
  exit 2
}

function debug_msg() {
  if [[ ${debug_mode} == "true" ]]; then
    printf "\033[1;33mDebug\033[0m: %s \n" "${@}" >&2
  fi
}

function contains() {
    # Verify if the given list contain keyword
    # $1 - keyword
    # $2 - list
    # Returns: 0 if found keyword in list 1 if not found
    local keyword
    local array_to_search
    keyword="${1}"
    array_to_search="${*:2}"

    for item in ${array_to_search[*]}; do
      if [[ "${keyword}" == "${item}" ]];then
        echo 0
        return
      fi
    done
    echo 1
}

function set_base_release_tag() {
    # GLOBAL VALUES IN USE
    # Try to determinate if the given tag is in semantic version format and if all conditions are fulfilled
    # set given tag as a base for the rest calculations
    # $1 - tag to verify
    # Returns - Nothing
    # Overwrite global values for suggested versions

    local tag
    IFS='.' read -r -a tag <<< "$1"

    local _re_is_number='^[0-9]+$'
    local _error_message="Tag must be in the given format: [major].[minor].[patch]. Example: 1.0.0"

    if [[ ${#tag[@]} -ne 3 ]]; then
      err_msg "${_error_message}"
    fi

    for item in "${tag[@]}"; do
      if ! [[ "${item}" =~ ${_re_is_number} ]]; then
        err_msg "${_error_message} - found character that isn't number (${item})"
      fi
    done

    suggested_version_major=${tag[0]}
    suggested_version_minor=${tag[1]}
    suggested_version_patch=${tag[2]}
}

function verify_required_programs() {
  # GLOBAL VALUES IN USE
  # Confirm all required packages are installed

  for package in "${REQUIRED_PACKAGES[@]}"; do
    if [[ ! $(command -v "${package}") ]]; then
      err_msg "Missing '${package}' in system"
    fi
  done
}

function get_latest_semver_tag() {
  git tag --sort=committerdate | grep --extended-regexp '([0-9]+\.?){3}' --only-matching | tail --lines 1 || echo ""
}

function build_match_regex() {
  # GLOBAL VALUES IN USE
  # Take keywords and combine all to a regex form
  # Returns: Regex form
  keywords=$(IFS='|' ; echo "${minor_keywords[*]}|${patch_keywords[*]}) ?(\(.*\))?!?")
  echo "^(${keywords}"
}

function get_commit_type() {
    # Try to determine what type of commit message was specified in the line
    # Return: type of commit message (major/minor/patch)
    local commit
    commit="${1%:*}"

    local type
    if [[ "${commit}" =~ !$ ]]; then
      type="major"
    else
      type=${commit% *}
      type=${type%(*}
    fi

    if [[ $(contains "${type}" "${minor_keywords[@]}") == 0 ]]; then
      type="minor"
    elif [[ $(contains "${type}" "${patch_keywords[@]}") == 0 ]]; then
      type="patch"
    fi

    echo "${type}"

    debug_msg "In commit ${1} (parsed to ${commit}) - found type - ${type}"
}

function usage_message() {
cat << EOF
Usage ${0}:
  -d|--debug-mode - Print debug message (usefully to determinate why script suggest given version)
  -b|--base-release [string] - Select base version for the release (usefully when it's first release) (expected format [major].[minor].[patch], example: 1.0.0)
  -h|--help - Display this message

EOF
}

####################################################################
#                           MAIN                                   #
####################################################################


verify_required_programs

set +o errexit
OPTS=$(getopt --name 'semver-releaser' --alternative --options 'dhb:' --long 'debug-mode,help,base-release:' -- "$@")
if [ $? -ne 0 ]; then
	usage_message
	exit 1
fi
set -o errexit

eval set -- "${OPTS}"

while :
do
    case "$1" in
        -d|--debug-mode)
            debug_mode='true'
            shift
            ;;
        -h|--help)
            usage_message
            exit 0
            ;;
        -b|--base-release)
            set_base_release_tag $2
            shift 2
            ;;
        --)
          shift
          break
          ;;
        \?)
          echo "Not implemented: $1" >&2
          usage
          exit 1
          ;;
    esac
done


latest_semver_tag=$(get_latest_semver_tag)
if [[ -z "${latest_semver_tag}" ]]; then
  debug_msg "Not found any semantic version tag"
  return_tag
  exit 0
else
  set_base_release_tag "${latest_semver_tag}"
fi

search_history_between="${latest_semver_tag}..$(git branch --show-current)"

debug_msg "Search history range - ${search_history_between}"

match_regex="$(build_match_regex)"
debug_msg "Regex to search the commit messages - ${match_regex}"

while read -r line; do
  if [[ ${line} =~ ${match_regex} ]]; then
    debug_msg "Found line to verify ${line}"
    commit_type=$(get_commit_type "${line[@]}")
    debug_msg "Received commit-type - ${commit_type}"
    case ${commit_type} in
      major)
        suggested_version_major=$((suggested_version_major + 1))
        suggested_version_minor=0
        suggested_version_patch=0
      ;;
      minor)
        suggested_version_minor=$((suggested_version_minor + 1))
        suggested_version_patch=0
      ;;
      patch)
        suggested_version_patch=$((suggested_version_patch + 1))
      ;;
    esac
  fi
done <<< "$(git --no-pager log --pretty=format:%s%n --reverse "${search_history_between}")"

return_tag
