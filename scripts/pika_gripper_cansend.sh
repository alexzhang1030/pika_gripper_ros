#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  pika_gripper_cansend.sh [global-options] <command> [command-options]

Global options:
  --iface can0           CAN interface (default: can0)
  --id 0x159             Command CAN ID (default: 0x159)
  --force 1000           Force in mN, range [0,5000] (default: 1000)

Commands:
  enable                 status=0x01 (enable, width mode)
  enable-clear           status=0x03 (enable + clear faults, width mode)
  disable                status=0x00 (disable)
  open                   move to max position (default 0.08 m)
  close                  move to min position (default 0.00 m)
  move --pos-m <value>   move to given meters, e.g. 0.025
  enable-angle           status=0x05 (enable, angle mode)
  enable-clear-angle     status=0x07 (enable + clear, angle mode)
  move-deg --pos-deg <v> move to given degrees, e.g. 45.0
  set-zero               set current position as zero (set_zero=0xAE)
  monitor [--fb-id 0x2A8]
                         sniff gripper feedback frames with candump

Examples:
  ./scripts/pika_gripper_cansend.sh --iface can0 enable-clear
  ./scripts/pika_gripper_cansend.sh --iface can0 move --pos-m 0.03
  ./scripts/pika_gripper_cansend.sh --iface can0 monitor --fb-id 0x2A8
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

to_hex_id() {
  local raw="$1"
  local dec
  dec=$((raw))
  printf "%03X" "$dec"
}

to_u32_hex_be() {
  local value="$1"
  printf "%08X" "$value"
}

to_u16_hex_be() {
  local value="$1"
  printf "%04X" "$value"
}

meters_to_counts() {
  local meters="$1"
  awk -v v="$meters" 'BEGIN { printf "%d", (v * 1000000.0) + 0.5 }'
}

degrees_to_counts() {
  local degrees="$1"
  awk -v v="$degrees" 'BEGIN { printf "%d", (v * 1000.0) + 0.5 }'
}

send_frame() {
  local can_iface="$1"
  local can_id="$2"
  local pos_counts="$3"
  local force_mn="$4"
  local status_code="$5"
  local set_zero="$6"

  local angle_hex force_hex status_hex zero_hex payload frame
  angle_hex=$(to_u32_hex_be "$pos_counts")
  force_hex=$(to_u16_hex_be "$force_mn")
  status_hex=$(printf "%02X" "$status_code")
  zero_hex=$(printf "%02X" "$set_zero")
  payload="${angle_hex}${force_hex}${status_hex}${zero_hex}"
  frame="$(to_hex_id "$can_id")#${payload}"
  echo "cansend $can_iface $frame"
  cansend "$can_iface" "$frame"
}

iface="can0"
can_id="0x159"
force_mn=1000

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface) iface="$2"; shift 2 ;;
    --id) can_id="$2"; shift 2 ;;
    --force) force_mn="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

require_cmd awk

if (( force_mn < 0 || force_mn > 5000 )); then
  echo "--force out of range [0,5000]: $force_mn" >&2
  exit 1
fi

command_name="$1"
shift

case "$command_name" in
  enable)
    require_cmd cansend
    send_frame "$iface" "$can_id" 0 "$force_mn" 0x01 0x00
    ;;
  enable-clear)
    require_cmd cansend
    send_frame "$iface" "$can_id" 0 "$force_mn" 0x03 0x00
    ;;
  disable)
    require_cmd cansend
    send_frame "$iface" "$can_id" 0 "$force_mn" 0x00 0x00
    ;;
  open)
    require_cmd cansend
    send_frame "$iface" "$can_id" "$(meters_to_counts 0.08)" "$force_mn" 0x01 0x00
    ;;
  close)
    require_cmd cansend
    send_frame "$iface" "$can_id" "$(meters_to_counts 0.0)" "$force_mn" 0x01 0x00
    ;;
  move)
    require_cmd cansend
    if [[ $# -lt 2 || "$1" != "--pos-m" ]]; then
      echo "move requires --pos-m <meters>" >&2
      exit 1
    fi
    pos_m="$2"
    shift 2
    send_frame "$iface" "$can_id" "$(meters_to_counts "$pos_m")" "$force_mn" 0x01 0x00
    ;;
  enable-angle)
    require_cmd cansend
    send_frame "$iface" "$can_id" 0 "$force_mn" 0x05 0x00
    ;;
  enable-clear-angle)
    require_cmd cansend
    send_frame "$iface" "$can_id" 0 "$force_mn" 0x07 0x00
    ;;
  move-deg)
    require_cmd cansend
    if [[ $# -lt 2 || "$1" != "--pos-deg" ]]; then
      echo "move-deg requires --pos-deg <degrees>" >&2
      exit 1
    fi
    pos_deg="$2"
    shift 2
    send_frame "$iface" "$can_id" "$(degrees_to_counts "$pos_deg")" "$force_mn" 0x05 0x00
    ;;
  set-zero)
    require_cmd cansend
    send_frame "$iface" "$can_id" 0 "$force_mn" 0x00 0xAE
    ;;
  monitor)
    require_cmd candump
    fb_id="0x2A8"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --fb-id) fb_id="$2"; shift 2 ;;
        *) echo "Unknown monitor option: $1" >&2; exit 1 ;;
      esac
    done
    fb_hex=$(to_hex_id "$fb_id")
    echo "candump ${iface},${fb_hex}:7FF"
    candump "${iface},${fb_hex}:7FF"
    ;;
  *)
    echo "Unknown command: $command_name" >&2
    usage
    exit 1
    ;;
esac
