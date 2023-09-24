#!/bin/bash
# vim: softtabstop=2 shiftwidth=2 expandtab

# Generate a new package list with, e.g.,
#
# git diff-tree -r --no-renames --name-only \
#     --diff-filter=AM master HEAD -- srcpkgs/*/template | \
#     cut -d/ -f2 | xargs ./xbps-src sort-dependencies
#
# or follow the README.

get_local_version() {
  PKG="${1?must specify a package}"
  ARCH="${2?must specify a target arch}"

  shift 2

  for REPO in "$@"; do
    REPO=$(realpath -e "${REPO}") || continue
    QUERY=( "-R" "--repo=${REPO}" )

    # Figure out whether the desired repository holds the package
    LOC=$(XBPS_TARGET_ARCH="${ARCH}" xbps-query "${QUERY[@]}" -p repository "${PKG}") || continue

    LOC=$(realpath -e "${LOC}") || continue
    [ "${LOC}" = "${REPO}" ] || continue

    # Find the pkgver for the package in the repository
    PKGVER=$(XBPS_TARGET_ARCH="${ARCH}" xbps-query "${QUERY[@]}" -p pkgver "${PKG}") || continue

    if [ -n "${PKGVER}" ]; then
      echo "${PKGVER}"
      return 0
    fi
  done

  return 1
}

get_needed_version() {
  PKG="${1?must specify a package}"
  PKGVER=$(./xbps-src show -p pkgver "${PKG}" | awk '/pkgver:/{print $2}') || return 1

  [ -n "${PKGVER}" ] || return 1
  echo "${PKGVER}"
}

usage() {
  cat <<-EOF
	USAGE: $0 [options...] <pkglist>
	
	Build all packages in the given list not already in a local repo
	
	OPTIONS
	
	-h
	   Display this help message and exit
	
	-a <arch>
	   Build packages for the specified arch
	   (default: x86_64)
	
	-m <masterdir>
	   Use the specified masterdir
	   (default: /tmp/masterdir.\${ARCH})
	
	-r <repo>
	   Look in the named repo for existing packages
	   (default: xbps-src default for current branch)
	
	-n <repo>
	   Look in the named repo for existing non-free packages
	   (default: \${REPO}/nonfree)
	
	-v <void-packages>
	   Use the given void-packages repository
	   (default: \$(xdistdir) if possible, otherwise \$PWD)
	
	-x
	   Fail on package failure instead of marking broken
	
	-S
	   Do not sort package list; build in order listed in file
	EOF
}

PRESORTED_PKGS=
while getopts "ha:m:r:n:v:xS" opt; do
  case "${opt}" in
    a)
      REPO_ARCH="${OPTARG}"
      ;;
    m)
      MASTERDIR="${OPTARG}"
      ;;
    r)
      REPO="${OPTARG}"
      ;;
    n)
      REPO_NONFREE="${OPTARG}"
      ;;
    v)
      XBPS_DISTDIR="${OPTARG}"
      ;;
    x)
      PYBUMP_ERRORS_FAIL="yes"
      ;;
    S)
      PRESORTED_PKGS="yes"
      ;;
    h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

shift "$((OPTIND - 1))"

if [ ! -d "${XBPS_DISTDIR}" ]; then
  # Try to find a default void-packages repository
  XBPS_DISTDIR=$(xdistdir 2>/dev/null) || XBPS_DISTDIR=""
  [ -d "${XBPS_DISTDIR}" ] || XBPS_DISTDIR="${PWD}"
fi

# Always run from $XBPS_DISTDIR
cd "${XBPS_DISTDIR}" || exit 1
if ! command -v ./xbps-src >/dev/null 2>&1; then
  echo "ERROR: failed to find xbps-src"
  exit 1
fi

if [ -z "${REPO}" ]; then
  if ! BRANCH="$(git rev-parse --abbrev-ref HEAD)"; then
    echo "ERROR: failed to determine branch"
    exit 1
  fi

  case "${BRANCH}" in
    master) REPO="${PWD}/hostdir/binpkgs" ;;
    *) REPO="${PWD}/hostdir/binpkgs/${BRANCH}" ;;
  esac
fi

[ -n "${REPO_ARCH}" ] || REPO_ARCH=x86_64
[ -n "${REPO_NONFREE}" ] || REPO_NONFREE="${REPO}/nonfree"

PKGLIST="${1?specify a package list}"
[ -r "${PKGLIST}" ] || exit 1

case "${REPO_ARCH}" in
  i686) ROOT_ARCH="i686" ;;
  i686-musl) ROOT_ARCH="i686-musl" ;;
  *-musl) ROOT_ARCH="x86_64-musl" ;;
  *) ROOT_ARCH="x86_64" ;;
esac

[ -n "${MASTERDIR}" ] || MASTERDIR=/tmp/masterdir.${ROOT_ARCH}

./xbps-src -m "${MASTERDIR}" binary-bootstrap "${ROOT_ARCH}"
./xbps-src -m "${MASTERDIR}" bootstrap-update

case "${REPO_ARCH}" in
  i686*|x86_64*) ARCH_OPT=() ;;
  *) ARCH_OPT=( "-a" "${REPO_ARCH}" ) ;;
esac

PACKAGES=
if [ -n "${PRESORTED_PKGS}" ]; then
  PACKAGES=$(cat "${PKGLIST}")
else
  PACKAGES=$(xargs ./xbps-src sort-dependencies < "${PKGLIST}")
fi

while read -r pkg; do
  # Try to find the package in the local repos
  if HAVE_PKGVER=$(get_local_version "${pkg}" "${REPO_ARCH}" "${REPO}" "${REPO_NONFREE}"); then
    if NEED_PKGVER=$(get_needed_version "${pkg}"); then
      if xbps-uhelper cmpver "${HAVE_PKGVER}" "${NEED_PKGVER}"; then
        echo "SKIPPING ${pkg}, VERSION ${NEED_PKGVER} already exists" && continue
      fi
    fi
  fi

  ./xbps-src -m "${MASTERDIR}" clean
  ./xbps-src -m "${MASTERDIR}" "${ARCH_OPT[@]}" -f pkg "${pkg}"

  ret=$?
  case "$ret" in
    0) ;;
    2) ;;
    *)
      if [ -n "${PYBUMP_ERRORS_FAIL}" ]; then
        echo "ERROR: failed to build ${pkg}"
        exit $ret
      else
        sed -i '/checksum=/i broken="pybump temporary break"' "srcpkgs/${pkg}/template"
      fi
      ;;
  esac
done <<< "${PACKAGES}"
