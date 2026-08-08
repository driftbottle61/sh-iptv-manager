#!/usr/bin/env bash
set -euo pipefail

VERSION="1.1.1"
REPOSITORY="driftbottle61/sh-iptv-manager"
ARCHIVE="sh-iptv-spider-installer-${VERSION}-linux-amd64.tar.gz"
ARCHIVE_URL="https://github.com/${REPOSITORY}/releases/download/v${VERSION}/${ARCHIVE}"
ARCHIVE_SHA256="817aaa04219b86b5f292d0b0839f8ca9d8383cfb78d89fb07bb2fceef09be5e5"

if [ "$(uname -m)" != "x86_64" ]; then
  echo "Only Linux amd64 is supported." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required. Install it first: apt-get update && apt-get install -y curl" >&2
  exit 1
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "sha256sum is required." >&2
  exit 1
fi

WORK_DIR=$(mktemp -d /tmp/iptv-spider-install.XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Downloading IPTV Spider ${VERSION}..."
curl -fL --retry 3 --retry-delay 2 -o "${WORK_DIR}/${ARCHIVE}" "$ARCHIVE_URL"
echo "${ARCHIVE_SHA256}  ${WORK_DIR}/${ARCHIVE}" | sha256sum -c -

tar -xzf "${WORK_DIR}/${ARCHIVE}" -C "$WORK_DIR"
INSTALL_DIR="${WORK_DIR}/sh-iptv-spider-installer"

if [ ! -x "${INSTALL_DIR}/install.sh" ]; then
  echo "The downloaded archive does not contain install.sh." >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  exec bash "${INSTALL_DIR}/install.sh"
fi

exec sudo bash "${INSTALL_DIR}/install.sh"
