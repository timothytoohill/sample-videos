#!/usr/bin/env bash
set -euo pipefail

DEFAULT_VIDEO_FILE="people-detection.mp4"
VIDEO_FILE="${1:-$DEFAULT_VIDEO_FILE}"

usage() {
  echo "Usage: $0 [video-file]" >&2
}

install_ffmpeg() {
  local install_cmd=""

  if command -v apt-get >/dev/null 2>&1; then
    install_cmd="sudo apt-get update && sudo apt-get install -y ffmpeg"
  elif command -v dnf >/dev/null 2>&1; then
    install_cmd="sudo dnf install -y ffmpeg"
  elif command -v yum >/dev/null 2>&1; then
    install_cmd="sudo yum install -y ffmpeg"
  elif command -v pacman >/dev/null 2>&1; then
    install_cmd="sudo pacman -Sy --noconfirm ffmpeg"
  elif command -v zypper >/dev/null 2>&1; then
    install_cmd="sudo zypper install -y ffmpeg"
  elif command -v brew >/dev/null 2>&1; then
    install_cmd="brew install ffmpeg"
  fi

  if [[ -z "$install_cmd" ]]; then
    echo "ffmpeg is not installed and no supported package manager was detected." >&2
    echo "Please install ffmpeg manually and re-run the script." >&2
    exit 1
  fi

  read -r -p "ffmpeg is not installed. Install it now? [Y/n] " reply
  reply="${reply:-Y}"

  if [[ ! "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "ffmpeg is required to run this script." >&2
    exit 1
  fi

  bash -lc "$install_cmd"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  install_ffmpeg
fi

if [[ ! -f "$VIDEO_FILE" ]]; then
  echo "Video file not found: $VIDEO_FILE" >&2
  usage
  exit 1
fi

get_lan_ipv4_address() {
  ip -o -4 addr show up scope global 2>/dev/null | awk '
    function is_private(ip) {
      return ip ~ /^10\./ || ip ~ /^192\.168\./ || ip ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./
    }
    {
      split($4, parts, "/")
      ip = parts[1]
      if (is_private(ip)) {
        print ip
        exit
      }
      if (!fallback) {
        fallback = ip
      }
    }
    END {
      if (fallback) {
        print fallback
      }
    }
  '
}

HOST_IP_ADDRESS="${HOST_IP_ADDRESS:-$(get_lan_ipv4_address)}"

if [[ -z "${HOST_IP_ADDRESS}" ]]; then
  HOST_IP_ADDRESS="$(
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{
      for (i = 1; i <= NF; i++) {
        if ($i == "src") {
          print $(i + 1)
          exit
        }
      }
    }'
  )"
fi

if [[ -z "${HOST_IP_ADDRESS}" ]]; then
  echo "Could not determine host IP address." >&2
  exit 1
fi

exec ffmpeg \
  -re \
  -stream_loop -1 \
  -fflags +genpts \
  -probesize 50M \
  -analyzeduration 100M \
  -i "$VIDEO_FILE" \
  -map 0:v \
  -map 0:d \
  -c:v copy \
  -c:d copy \
  -f mpegts \
  "srt://${HOST_IP_ADDRESS}:40052?mode=listener&latency=200000"
