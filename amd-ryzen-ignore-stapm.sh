#!/bin/sh -e

waitForPerformanceProfile()
{
  (
    udevadm monitor -k -s platform-profile |
      while read -r _; do
        if test "$(powerprofilesctl get)" = 'performance'; then
            pipe_ppid=$(sh -ec 'printf "%s\n" "$PPID"')
            pkill -P "$(ps -o ppid:1= "$pipe_ppid")"
        fi
      done
  ) 2>/dev/null || true
}

getSlowLimit()
{
  od -fw20 /sys/kernel/ryzen_smu_drv/pm_table | head -n1 | sed -r 's/^.* ([^\.]+)(\.[^\.]+)?$/\1/'
}

printU32LE()
(
  for arg; do printf '%08x' "$arg" | sed -r 's/(..)(..)(..)(..)/\4\3\2\1/'; done | xxd -p -r
)

smuCommand()
(
  opcode="$1"
  argument="$2"

  printU32LE "$argument" 0 0 0 0 0 >/sys/kernel/ryzen_smu_drv/smu_args
  printU32LE "$opcode"             >/sys/kernel/ryzen_smu_drv/mp1_smu_cmd
  result=$(xxd -p /sys/kernel/ryzen_smu_drv/mp1_smu_cmd)
  test "$result" = '01000000' || {
    printf 'error: failed to send smu command to ryzen smu driver\n' >&2
    exit 1
  }
)

applyLimits()
(
  apu_skin_temp="$1"
  slow_limit="$2"
  fast_limit="$3"

  smuCommand 21 "$fast_limit"
  smuCommand 22 "$slow_limit"
  smuCommand 20 "$slow_limit" # stapm_limit
  smuCommand 51 "$((256 * apu_skin_temp))"
)

previous_power_profile=''
while true; do
  current_power_profile=$(powerprofilesctl get)
  if test "$current_power_profile" != "$previous_power_profile"; then
    previous_power_profile="$current_power_profile"

    if test "$current_power_profile" = 'performance'; then
      printf 'performance power profile is enabled, monitoring...\n'
    else
      printf 'performance power profile is disabled, sleeping...\n'
      waitForPerformanceProfile
    fi
  elif test "$(getSlowLimit)" != '43'; then
    printf 'reapplying limits\n'
    applyLimits 50 43000 53000
  else
    sleep 5
  fi
done
