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

PKGLIST="${1?specify a package list}"
[ -r "${PKGLIST}" ] || exit 1

: ${REPO:=hostdir/binpkgs/py311}
: ${REPO_NONFREE:=${REPO}/nonfree}

: ${REPO_ARCH:=x86_64}

case "${REPO_ARCH}" in
  i686) ROOT_ARCH="i686" ;;
  i686-musl) ROOT_ARCH="i686-musl" ;;
  *-musl) ROOT_ARCH="x86_64-musl" ;;
  *) ROOT_ARCH="x86_64" ;;
esac

case "${REPO_ARCH}" in
  i686*|x86_64*) ARCH_OPT=() ;;
  *) ARCH_OPT=( "-a" "${REPO_ARCH}" ) ;;
esac

: ${MASTERDIR:=/tmp/masterdir.${ROOT_ARCH}}
./xbps-src -m "${MASTERDIR}" binary-bootstrap "${ROOT_ARCH}"
./xbps-src -m "${MASTERDIR}" bootstrap-update

while read -r pkg; do
  # Try to find the package in the local repos
  if HAVE_PKGVER=$(get_local_version "${pkg}" "${REPO_ARCH}" "${REPO}" "${REPO_NONFREE}"); then
    if NEED_PKGVER=$(get_needed_version "${pkg}"); then
      if xbps-uhelper cmpver "${HAVE_PKGVER}" "${NEED_PKGVER}"; then
        echo "SKIPPING $pkg, VERSION ${NEED_PKGVER} already exists" && continue
      fi
    fi
  fi

  ./xbps-src -m "${MASTERDIR}" clean
  ./xbps-src -m "${MASTERDIR}" "${ARCH_OPT[@]}" -f pkg $pkg

  ret=$?
  case "$ret" in
    0) ;;
    2) ;;
    *)
      sed -i '/checksum=/i broken="python3.11 temporary break"' srcpkgs/${pkg}/template
      ;;
  esac
done < "${PKGLIST}"
