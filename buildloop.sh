#!/bin/bash
# vim: softtabstop=2 shiftwidth=2 expandtab

# Generate a new package list with, e.g.,
#
# git diff-tree -r --no-renames --name-only \
#     --diff-filter=AM master HEAD -- srcpkgs/*/template | \
#     cut -d/ -f2 | xargs ./xbps-src sort-dependencies
#
# or follow the README.

PKGLIST="${1?specify a package list}"
[ -r "${PKGLIST}" ] || exit 1

: ${REPO:=hostdir/binpkgs/python3.10}
: ${REPO_ARCH:=x86_64}

mkdir -p "${REPO}"
REALREPO=$(realpath -e "${REPO}") || exit 1

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
  if repo=$(XBPS_TARGET_ARCH="${REPO_ARCH}" xbps-query -Rp repository --repo=$REPO $pkg); then
    [ "$repo" = "$REALREPO" ] && echo "SKIPPING $pkg, already exists" && continue
  fi

  ./xbps-src -m "${MASTERDIR}" clean
  ./xbps-src -m "${MASTERDIR}" "${ARCH_OPT[@]}" -f pkg $pkg

  ret=$?
  case "$ret" in
    0) ;;
    2) ;;
    *)
      sed -i '/checksum=/i broken="python3.10 temporary break"' srcpkgs/${pkg}/template
      ;;
  esac
done < "${PKGLIST}"
