#!/bin/bash
# Copyright 2020 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Add repository for the Google monitoring agent.
#
# This script configures the required apt or yum repository.
# The environment variable REPO_SUFFIX can be set to alter which repository is
# used. A dash (-) will be inserted prior to the supplied suffix. <REPO_SUFFIX>
# defaults to 'all' which contains all agent versions across different major versions.
# The full repository name is:
# "google-cloud-monitoring-<DISTRO>[-<ARCH>]-<REPO_SUFFIX>".
#
# Ignore the return code of command substitution in variables.
# shellcheck disable=SC2155
#
# Sample usage:
# 1. To add a specific repo by REPO_SUFFIX.
#     For instance, to add the repo that only includes 6.*.* versions of the agent to
#     avoid accidentally pulling in a new major version with breaking change, run:
#     $ REPO_SUFFIX=6 bash add-monitoring-agent-repo.sh
# 2. To add the repo that contains all agent versions, run:
#     $ bash add-monitoring-agent-repo.sh
# 3. To add the repo and also install the agent, run:
#     $ bash add-monitoring-agent-repo.sh --also-install --version=<AGENT_VERSION>
#    AGENT_VERSION options:
#    a) latest (default)
#    b) MAJOR_VERSION.*.*
#    c) MAJOR_VERSION.MINOR_VERSION.PATCH_VERSION
# 4. To uninstall the agent run:
#     $ bash add-monitoring-agent-repo.sh --uninstall
# 5. To uninstall the agent and remove the repo, run:
#     $ bash add-monitoring-agent-repo.sh --uninstall --remove-repo
# 6. To run the script with verbose logging, run:
#     $ bash add-monitoring-agent-repo.sh --also-install --verbose
# 7. To run the script in dry-run mode, run:
#     $ bash add-monitoring-agent-repo.sh --also-install --dry-run

# Initialize var used to notify config management tools of when a change is made.
CHANGED=0

fail() {
  echo >&2 "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"
  exit 1
}

# Parsing flag value.
declare -a ACTIONS=()
DRY_RUN=''
VERBOSE='false'
while getopts -- '-:' OPTCHAR; do
  case "${OPTCHAR}" in
    -)
      case "${OPTARG}" in
        # Note: Do not remove entries from this list when deprecating flags.
        # That would break user scripts that specify those flags. Instead,
        # leave the flag in place but make it a noop.
        also-install) ACTIONS+=('also-install') ;;
        version=*) AGENT_VERSION="${OPTARG#*=}" ;;
        uninstall) ACTIONS+=('uninstall') ;;
        remove-repo) ACTIONS+=('remove-repo') ;;
        dry-run) echo 'Starting dry run'; DRY_RUN='dryrun' ;;
        verbose) VERBOSE='true' ;;
        *) fail "Unknown option '${OPTARG}'." ;;
      esac
  esac
done
[[ "${ACTIONS[*]}" == *uninstall* || ( "${ACTIONS[*]}" == *remove-repo* && "${ACTIONS[*]}" != *also-install* )]] || \
  ACTIONS+=('add-repo')
# Sort the actions array for easier parsing.
readarray -t ACTIONS < <(printf '%s\n' "${ACTIONS[@]}" | sort)
readonly ACTIONS DRY_RUN VERBOSE

if [[ "${ACTIONS[*]}" == *also-install*uninstall* ]]; then
    fail "Received conflicting flags 'also-install' and 'uninstall'."
fi

if [[ "${VERBOSE}" == 'true' ]]; then
  echo 'Enable verbose logging.'
  set -x
fi

# Host that serves the repositories.
REPO_HOST='packages.cloud.google.com'

# URL for the monitoring agent documentation.
AGENT_DOCS_URL='https://cloud.google.com/monitoring/agent'

# URL documentation which lists supported platforms for running the monitoring agent.
AGENT_SUPPORTED_URL="${AGENT_DOCS_URL}/#supported_operating_systems"

# Packages to install.
AGENT_PACKAGE='stackdriver-agent'
declare -a ADDITIONAL_PACKAGES=()

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
fi

# If dry-run mode is enabled, echo VM state-changing commands instead of executing them.
dryrun() {
  # Needed for commands that use pipes.
  if [[ ! -t 0 ]]; then
    cat
  fi
  printf -v cmd_str '%q ' "$@"
  echo "DRY_RUN: Not executing '$cmd_str'"
}

refresh_failed() {
  local REPO_TYPE="$1"
  local OS_FAMILY="$2"
  fail "Could not refresh the google-cloud-monitoring ${REPO_TYPE} repositories.
Please check your network connectivity and make sure you are running a supported
${OS_FAMILY} distribution. See ${AGENT_SUPPORTED_URL}
for a list of supported platforms."
}

resolve_version() {
 if [[ "${AGENT_VERSION:-latest}" == 'latest' ]]; then
   AGENT_VERSION=''
 elif grep -qE '^[0-9]+\.\*\.\*$' <<<"${AGENT_VERSION}"; then
   REPO_SUFFIX="${REPO_SUFFIX:-"${AGENT_VERSION%%.*}"}"
 elif ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"${AGENT_VERSION}"; then
   fail "The agent version [${AGENT_VERSION}] is not allowed. Expected values: [latest],
or anything in the format of [MAJOR_VERSION.MINOR_VERSION.PATCH_VERSION] or [MAJOR_VERSION.*.*]."
 fi
}

handle_debian() {
  declare -a EXTRA_OPTS=()
  [[ "${VERBOSE}" == 'true' ]] && EXTRA_OPTS+=(-oDebug::pkgAcquire::Worker=1)

  add_repo() {
    [[ -n "${REPO_CODENAME:-}" ]] || lsb_release -v >/dev/null 2>&1 || { \
      apt-get update; apt-get -y install lsb-release; CHANGED=1;
    }
    [[ "$(dpkg -l apt-transport-https 2>&1 | grep -o '^[a-z][a-z]')" == 'ii' ]] || { \
      ${DRY_RUN} apt-get update; ${DRY_RUN} apt-get -y install apt-transport-https; CHANGED=1;
    }
    [[ "$(dpkg -l ca-certificates 2>&1 | grep -o '^[a-z][a-z]')" == 'ii' ]] || { \
      ${DRY_RUN} apt-get update; ${DRY_RUN} apt-get -y install ca-certificates; CHANGED=1;
    }
    local CODENAME="${REPO_CODENAME:-"$(lsb_release -sc)"}"
    local REPO_NAME="google-cloud-monitoring-${CODENAME}-${REPO_SUFFIX:-all}"
    local REPO_DATA="deb https://${REPO_HOST}/apt ${REPO_NAME} main"
    if ! cmp -s <<<"${REPO_DATA}" - /etc/apt/sources.list.d/google-cloud-monitoring.list; then
      echo "Adding agent repository for ${ID}."
      ${DRY_RUN} tee <<<"${REPO_DATA}" /etc/apt/sources.list.d/google-cloud-monitoring.list
      ${DRY_RUN} curl --connect-timeout 5 -s -f "https://${REPO_HOST}/apt/doc/apt-key.gpg" \
        | ${DRY_RUN} apt-key add -
      CHANGED=1
    fi
  }

  remove_repo() {
    if [[ -f /etc/apt/sources.list.d/google-cloud-monitoring.list ]]; then
      echo "Removing agent repository for ${ID}."
      ${DRY_RUN} rm /etc/apt/sources.list.d/google-cloud-monitoring.list
      CHANGED=1
    fi
  }

  expected_version_installed() {
    [[ "$(dpkg -l "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" 2>&1 | grep -o '^[a-z][a-z]' | sort -u)" == 'ii' ]] || \
      return
    if [[ -z "${AGENT_VERSION:-}" ]]; then
      apt-get --dry-run install "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" \
        | grep -qo '^0 upgraded, 0 newly installed'
    elif grep -qE '^[0-9]+\.\*\.\*$' <<<"${AGENT_VERSION}"; then
      dpkg -l "${AGENT_PACKAGE}" | grep -qE "$AGENT_PACKAGE $AGENT_VERSION" && \
        apt-get --dry-run install "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" \
        | grep -qo '^0 upgraded, 0 newly installed'
    else
      dpkg -l "${AGENT_PACKAGE}" | grep -qE "$AGENT_PACKAGE $AGENT_VERSION"
    fi
  }

  install_agent() {
    ${DRY_RUN} apt-get update || refresh_failed 'apt' "${ID}"
    expected_version_installed || { \
      [[ -n "${AGENT_VERSION:-}" ]] && AGENT_VERSION="=${AGENT_VERSION}*"
      ${DRY_RUN} apt-get -y --allow-downgrades "${EXTRA_OPTS[@]}" install "${AGENT_PACKAGE}${AGENT_VERSION}" \
        "${ADDITIONAL_PACKAGES[@]}" || fail "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} \
installation failed."
      echo "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} installation succeeded."
      CHANGED=1
    }
  }

  uninstall_agent() {
     # Return early unless at least one package is installed.
     dpkg -l "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" 2>&1 | grep -qo '^ii' || return
     ${DRY_RUN} apt-get -y "${EXTRA_OPTS[@]}" remove "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" || \
       fail "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} uninstallation failed."
     echo "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} uninstallation succeeded."
     CHANGED=1
  }
}

handle_rpm() {
  declare -a EXTRA_OPTS=()
  [[ "${VERBOSE}" == 'true' ]] && EXTRA_OPTS+=(-v)

  add_repo() {
    lsb_release -v >/dev/null 2>&1 || {
      yum -y install redhat-lsb-core; CHANGED=1;
    }
    local REPO_NAME="google-cloud-monitoring-${CODENAME}-\$basearch-${REPO_SUFFIX:-all}"
    local REPO_DATA="\
[google-cloud-monitoring]
name=Google Cloud Monitoring Agent Repository
baseurl=https://${REPO_HOST}/yum/repos/${REPO_NAME}
autorefresh=0
enabled=1
type=rpm-md
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://${REPO_HOST}/yum/doc/yum-key.gpg
       https://${REPO_HOST}/yum/doc/rpm-package-key.gpg"
    if ! cmp -s <<<"${REPO_DATA}" - /etc/yum.repos.d/google-cloud-monitoring.repo; then
      echo "Adding agent repository for ${ID}."
      ${DRY_RUN} tee <<<"${REPO_DATA}" /etc/yum.repos.d/google-cloud-monitoring.repo
      # After repo upgrades, CentOS7/RHEL7 won't pick up newly available packages
      # until the cache is cleared.
      ${DRY_RUN} rm -rf /var/cache/yum/*/*/google-cloud-monitoring/
      CHANGED=1
    fi
  }

  remove_repo() {
    if [[ -f /etc/yum.repos.d/google-cloud-monitoring.repo ]]; then
      echo "Removing agent repository for ${ID}."
      ${DRY_RUN} rm /etc/yum.repos.d/google-cloud-monitoring.repo
      CHANGED=1
    fi
  }

  expected_version_installed() {
    rpm -q "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" >/dev/null 2>&1 || return
    if [[ -z "${AGENT_VERSION:-}" ]]; then
      yum -y check-update "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" >/dev/null 2>&1
    elif grep -qE '^[0-9]+\.\*\.\*$' <<<"${AGENT_VERSION}"; then
      CURRENT_VERSION="$(rpm -q --queryformat '%{VERSION}' "${AGENT_PACKAGE}")"
      grep -qE "${AGENT_VERSION}" <<<"${CURRENT_VERSION}" && \
      yum -y check-update "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" >/dev/null 2>&1
    else
      CURRENT_VERSION="$(rpm -q --queryformat '%{VERSION}' "${AGENT_PACKAGE}")"
      [[ "${AGENT_VERSION}" == "${CURRENT_VERSION}" ]]
    fi
  }

  install_agent() {
    expected_version_installed || { \
      ${DRY_RUN} yum -y list updates || refresh_failed 'yum' "${ID}"
      local COMMAND='install'
      if [[ -n "${AGENT_VERSION:-}" ]]; then
        [[ -z "${CURRENT_VERSION:-}" ]] || \
        [[ "${AGENT_VERSION}" == "$(sort -rV <<<"${AGENT_VERSION}"$'\n'"${CURRENT_VERSION}" | head -1)" ]] || \
          COMMAND='downgrade'
        AGENT_VERSION="-${AGENT_VERSION}*"
      fi
      ${DRY_RUN} yum -y "${EXTRA_OPTS[@]}" "${COMMAND}" "${AGENT_PACKAGE}${AGENT_VERSION}" \
        "${ADDITIONAL_PACKAGES[@]}" || fail "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} \
installation failed."
      echo "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} installation succeeded."
      CHANGED=1
    }
  }

  uninstall_agent() {
     # Return early if none of the packages are installed.
     rpm -q "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" | grep -qvE 'is not installed$' || return
     ${DRY_RUN} yum -y "${EXTRA_OPTS[@]}" remove "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" || \
       fail "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} uninstallation failed."
     echo "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} uninstallation succeeded."
     CHANGED=1
  }
}

handle_redhat() {
  local MAJOR_VERSION="$(rpm --eval %{?rhel})"
  CODENAME="el${MAJOR_VERSION}"
  handle_rpm
}

handle_amazon_linux() {
  CODENAME='amzn'
  handle_rpm
}

handle_suse() {
  declare -a EXTRA_OPTS=()
  [[ "${VERBOSE}" == 'true' ]] && EXTRA_OPTS+=(-vv)

  add_repo() {
    local SUSE_VERSION=${VERSION_ID%%.*}
    local CODENAME="sles${SUSE_VERSION}"
    local REPO_NAME="google-cloud-monitoring-${CODENAME}-\$basearch-${REPO_SUFFIX:-all}"
    {
      ${DRY_RUN} zypper --non-interactive refresh || { \
        echo 'Could not refresh zypper repositories.'; \
        echo 'This is not necessarily a fatal error; proceeding...'; \
      }
    } | grep -qF 'Retrieving repository' || [[ -n "${DRY_RUN:-}" ]] && CHANGED=1
    local REPO_DATA="\
[google-cloud-monitoring]
name=Google Cloud Monitoring Agent Repository
baseurl=https://${REPO_HOST}/yum/repos/${REPO_NAME}
autorefresh=0
enabled=1
type=rpm-md
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://${REPO_HOST}/yum/doc/yum-key.gpg
       https://${REPO_HOST}/yum/doc/rpm-package-key.gpg"
    if ! cmp -s <<<"${REPO_DATA}" - /etc/zypp/repos.d/google-cloud-monitoring.repo; then
      echo "Adding agent repository for ${ID}."
      ${DRY_RUN} tee <<<"${REPO_DATA}" /etc/zypp/repos.d/google-cloud-monitoring.repo
      CHANGED=1
    fi
    {
      ${DRY_RUN} zypper --non-interactive --gpg-auto-import-keys refresh google-cloud-monitoring || \
        refresh_failed 'zypper' "${ID}"; \
    } | grep -qF 'Retrieving repository' || [[ -n "${DRY_RUN:-}" ]] && CHANGED=1
  }

  remove_repo() {
    if [[ -f /etc/zypp/repos.d/google-cloud-monitoring.repo ]]; then
      echo "Removing agent repository for ${ID}."
      ${DRY_RUN} rm /etc/zypp/repos.d/google-cloud-monitoring.repo
      CHANGED=1
    fi
  }

  expected_version_installed() {
    rpm -q "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" >/dev/null 2>&1 || return
    if [[ -z "${AGENT_VERSION:-}" ]]; then
      zypper --non-interactive update --dry-run "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" \
        | grep -qE '^Nothing to do.'
    elif grep -qE '^[0-9]+\.\*\.\*$' <<<"${AGENT_VERSION}"; then
      rpm -q --queryformat '%{VERSION}' "${AGENT_PACKAGE}" | grep -qE "${AGENT_VERSION}" && \
      zypper --non-interactive update --dry-run "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" \
        | grep -qE '^Nothing to do.'
    else
      [[ "${AGENT_VERSION}" == "$(rpm -q --queryformat '%{VERSION}' "${AGENT_PACKAGE}")" ]]
    fi
  }

  install_agent() {
    expected_version_installed || { \
      if [[ -n "${AGENT_VERSION:-}" ]]; then
        if grep -qE '^[0-9]+\.\*\.\*$' <<<"${AGENT_VERSION}"; then
          AGENT_VERSION="<$(( ${AGENT_VERSION%%.*} + 1 ))"
        else
          AGENT_VERSION="=${AGENT_VERSION}*"
        fi
      fi
      ${DRY_RUN} zypper --non-interactive "${EXTRA_OPTS[@]}" install --oldpackage "${AGENT_PACKAGE}${AGENT_VERSION}" \
        "${ADDITIONAL_PACKAGES[@]}" || fail "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} \
installation failed."
      echo "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} installation succeeded."
      CHANGED=1
    }
  }

  uninstall_agent() {
     # Return early if none of the packages are installed.
     rpm -q "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" | grep -qvE 'is not installed$' || return
     ${DRY_RUN} zypper --non-interactive "${EXTRA_OPTS[@]}" remove "${AGENT_PACKAGE}" "${ADDITIONAL_PACKAGES[@]}" || \
       fail "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} uninstallation failed."
     echo "${AGENT_PACKAGE} ${ADDITIONAL_PACKAGES[*]} uninstallation succeeded."
     CHANGED=1
  }
}

main() {
  case "${ID:-}" in
    amzn) handle_amazon_linux ;;
    debian|ubuntu) handle_debian ;;
    rhel|centos) handle_redhat ;;
    sles|opensuse-leap) handle_suse ;;
    *)
      # Fallback for systems lacking /etc/os-release.
      if [[ -f /etc/debian_version ]]; then
        ID='debian'
        handle_debian
      elif [[ -f /etc/redhat-release ]]; then
        ID='rhel'
        handle_redhat
      elif [[ -f /etc/SuSE-release ]]; then
        ID='sles'
        handle_suse
      else
        fail "Unidentifiable or unsupported platform. See
${AGENT_SUPPORTED_URL} for a list of supported platforms."
      fi
  esac

  if [[ "${ACTIONS[*]}" == *add-repo* ]]; then
    resolve_version
    add_repo
  fi
  if [[ "${ACTIONS[*]}" == *also-install* ]]; then
    install_agent
  elif [[ "${ACTIONS[*]}" == *uninstall* ]]; then
    uninstall_agent
  fi
  if [[ "${ACTIONS[*]}" == *remove-repo* ]]; then
    remove_repo
  fi

  if [[ "${CHANGED}" == 0 ]]; then
    echo 'No changes made.'
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo 'Finished dry run. This was only a simulation, remove the --dry-run flag
to perform an actual execution of the script.'
  fi
}

main "$@"
