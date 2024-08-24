#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

minor_keywords=("feat" "feature")
patch_keywords=("patch" "fix" "refactor")

###################################################################
# Don't modify this part of variables - it might break the script #
###################################################################

# Modified during runtime (
suggested_version_major=0
suggested_version_minor=0
suggested_version_patch=1

debug_mode='false'
single_release_bump='false'
create_git_tag='false'

create_git_tag_additional_comment=''
biggest_semver_type='nothing'

# Static variables
readonly REQUIRED_PACKAGES=(git tail getopt)
####################################################################
#                   Functions part                                 #
####################################################################

function build_tag() {
  printf "%d.%d.%d" "${suggested_version_major}" "${suggested_version_minor}" "${suggested_version_patch}"
}

function err_msg() {
  printf "\033[0;31mError\033[0m: %s \n" "${@}" >&2
  exit 2
}

function info_msg() {
  printf "\033[0;32mInfo\033[0m: %s \n" "${@}" >&2
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

function add_git_tag() {

  if [[ "${create_git_tag_additional_comment}" != '' ]]; then
      info_msg "Create annotated tag ($(build_tag)) with comment = ${create_git_tag_additional_comment}"
      git tag "$(build_tag)" --annotate --message "\"$(build_tag) - ${create_git_tag_additional_comment}\""
  else
      info_msg "Create unannotated tag ($(build_tag))"
      git tag "$(build_tag)"
  fi
}

function build_match_regex() {
  # GLOBAL VALUES IN USE
  # Take keywords and combine all to a regex form
  # Returns: Regex form
  echo "$(IFS='|' ; echo "^(${minor_keywords[*]}|${patch_keywords[*]}) ?(\(.*\))?!?")"
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

function bump_suggested_version() {
  # GLOBAL VALUES IN USE
  # Update suggested_version by the given commit type
  #   $1 - commit-type

  local commit_type
  commit_type="${1}"
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
}

function upgrade_biggest_semver_type() {
  # GLOBAL VALUES IN USE
  # Update the biggest_semver_type value to the biggest one value by the given commit type
  #   $1 - commit-type

  local commit_type
  commit_type="${1}"

  if [[ "${biggest_semver_type}" == "major" ]]; then
    return
  fi

  if [[ "${biggest_semver_type}" == "minor" && "${commit_type}" == "patch" ]]; then
    return
  fi

  debug_msg "Change biggest semver type from ${biggest_semver_type} -> ${commit_type}"
  biggest_semver_type="${commit_type}"
}


function usage_message() {
  local format
  format="$(IFS='|' ; echo "(${minor_keywords[*]}|${patch_keywords[*]}) [(scope)][!]")"


cat << EOF
Usage ${0}:

   Format: ${format}: [message]

   (scope is optional)
   (! - mark is used if you want to increment major number)

  -d|--debug-mode - Print debug message (usefully to determine why script suggests given version)
  -s|--single-release - Raise only by the single largest version, even if there were many commits along the way that should raise the version
  -b|--base-release [major:int].[minor:int].[patch:int] - Select the base version for the release (valid only when first release) (expected format [major].[minor].[patch], example: 1.0.0)
  -a|--add-git-tag - Instead of printing the release version tag - add the tag in the current git repository
  -c|--comment-git-tag [comment:string] - Add an annotated git tag with the given comment
  -h|--help - Display this message
EOF
}

####################################################################
#                           MAIN                                   #
####################################################################


verify_required_programs

set +o errexit
OPTS="$(
  getopt --name 'semver-releaser' \
  --alternative \
  --options 'ac:dshb:' \
  --long 'add-git-tag,single-release,debug-mode,help,comment-git-tag:,base-release:' \
  -- "$@"
)"

if [ $? -ne 0 ]; then
	usage_message
	exit 1
fi
set -o errexit

eval set -- "${OPTS}"

while :
do
    case "$1" in
        -a|--add-git-tag)
            create_git_tag='true'
            shift
            ;;
        -c|--comment-git-tag)
            echo "${1} - ${2}"
            create_git_tag='true'
            create_git_tag_additional_comment="${2}"
            shift 2
            ;;
        -d|--debug-mode)
            debug_mode='true'
            shift
            ;;
        -s|--single-release)
            single_release_bump=true
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


latest_semver_tag="$(get_latest_semver_tag)"
if [[ -z "${latest_semver_tag}" ]]; then
  debug_msg "Not found any semantic version tag"
  if [[ "${create_git_tag}" == "true" ]]; then
    add_git_tag
  else
    build_tag
  fi
  exit 0
fi

set_base_release_tag "${latest_semver_tag}"
search_history_between="${latest_semver_tag}..$(git branch --show-current)"

debug_msg "Search history range - ${search_history_between}"

match_regex="$(build_match_regex)"
debug_msg "Regex to search the commit messages - ${match_regex}"

while read -r line; do
  if [[ ${line} =~ ${match_regex} ]]; then

    debug_msg "Found line to verify ${line}"
    commit_type=$(get_commit_type "${line[@]}")
    debug_msg "Received commit-type - ${commit_type}"
    upgrade_biggest_semver_type "${commit_type}"
    bump_suggested_version "${commit_type}"
    debug_msg "Current biggest_semver_type = ${biggest_semver_type}"
    debug_msg "Current current suggested tag = $(build_tag)"
  fi
done <<< "$(git --no-pager log --pretty=format:%s%n --reverse "${search_history_between}")"

if [[ "${single_release_bump}" == 'true' ]]; then
  debug_msg "Overwriting the suggested tag to the latest semver tag, due to the single release switch"
  set_base_release_tag "${latest_semver_tag}"
  bump_suggested_version "${biggest_semver_type}"
fi


if [[ "${create_git_tag}" == "true" ]]; then
  add_git_tag
else
  build_tag
fi
