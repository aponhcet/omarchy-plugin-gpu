# aponhcet.gpu login
# Desktop GPU for the next Hyprland login. The bar widget writes
# ~/.config/uwsm/gpu-mode as auto, intel, nvidia, or amd. A missing file means auto.
gpu_nv_card=
gpu_ig_card=
gpu_amd_card=
gpu_amd_boot=0
if [ -e /dev/dri/nvidia-dgpu ]; then
	gpu_nv_card=/dev/dri/nvidia-dgpu
fi
if [ -e /dev/dri/intel-igpu ]; then
	gpu_ig_card=/dev/dri/intel-igpu
fi
for gpu_sys in /sys/class/drm/card[0-9]*; do
	[ -r "$gpu_sys/device/vendor" ] || continue
	gpu_base=$(basename "$gpu_sys")
	case $gpu_base in
		card[0-9] | card[0-9][0-9]) ;;
		*) continue ;;
	esac
	gpu_vendor=$(tr 'A-F' 'a-f' <"$gpu_sys/device/vendor" | tr -d '[:space:]' || true)
	case $gpu_vendor in
		0x10de)
			[ -n "$gpu_nv_card" ] || gpu_nv_card=/dev/dri/$gpu_base
			;;
		0x8086)
			[ -n "$gpu_ig_card" ] || gpu_ig_card=/dev/dri/$gpu_base
			;;
		0x1002)
			if [ -z "$gpu_amd_card" ]; then
				gpu_amd_card=/dev/dri/$gpu_base
				if [ -r "$gpu_sys/device/boot_vga" ] && [ "$(tr -d '[:space:]' <"$gpu_sys/device/boot_vga" 2>/dev/null || true)" = 1 ]; then
					gpu_amd_boot=1
				fi
			fi
			;;
	esac
done

gpu_nv_connected=0
if [ -n "$gpu_nv_card" ] && [ -e "$gpu_nv_card" ]; then
	gpu_nv_name=$(basename "$(readlink -f "$gpu_nv_card")")
	for gpu_status in /sys/class/drm/"$gpu_nv_name"-*/status; do
		[ -f "$gpu_status" ] || continue
		case "$(basename "$(dirname "$gpu_status")")" in
			*riteback*) continue ;;
		esac
		if [ "$(cat "$gpu_status" 2>/dev/null || true)" = connected ]; then
			gpu_nv_connected=1
			break
		fi
	done
fi

gpu_amd_connected=0
if [ "$gpu_amd_boot" != 1 ] && [ -n "$gpu_amd_card" ] && [ -e "$gpu_amd_card" ]; then
	gpu_amd_name=$(basename "$(readlink -f "$gpu_amd_card")")
	for gpu_status in /sys/class/drm/"$gpu_amd_name"-*/status; do
		[ -f "$gpu_status" ] || continue
		case "$(basename "$(dirname "$gpu_status")")" in
			*riteback*) continue ;;
		esac
		if [ "$(cat "$gpu_status" 2>/dev/null || true)" = connected ]; then
			gpu_amd_connected=1
			break
		fi
	done
fi

gpu_mode=auto
gpu_config_home=${XDG_CONFIG_HOME:-$HOME/.config}
gpu_mode_file=$gpu_config_home/uwsm/gpu-mode
if [ -f "$gpu_mode_file" ]; then
	gpu_mode_raw=$(head -c 16 "$gpu_mode_file" 2>/dev/null || true)
	case $gpu_mode_raw in
		intel*) gpu_mode=intel ;;
		nvidia*) gpu_mode=nvidia ;;
		amd*) gpu_mode=amd ;;
		auto*) gpu_mode=auto ;;
	esac
fi

gpu_primary=
case $gpu_mode in
	intel) gpu_primary=$gpu_ig_card ;;
	nvidia) gpu_primary=$gpu_nv_card ;;
	amd) gpu_primary=$gpu_amd_card ;;
esac
if [ -z "$gpu_primary" ]; then
	if [ "$gpu_nv_connected" -eq 1 ]; then
		gpu_primary=$gpu_nv_card
	elif [ "$gpu_amd_connected" -eq 1 ]; then
		gpu_primary=$gpu_amd_card
	elif [ -n "$gpu_ig_card" ]; then
		gpu_primary=$gpu_ig_card
	elif [ -n "$gpu_amd_card" ]; then
		gpu_primary=$gpu_amd_card
	elif [ -n "$gpu_nv_card" ]; then
		gpu_primary=$gpu_nv_card
	fi
fi

gpu_devices=
gpu_remember() {
	[ -n "$1" ] || return 0
	case ":$gpu_devices:" in
		*":$1:"*) return 0 ;;
	esac
	if [ -z "$gpu_devices" ]; then
		gpu_devices=$1
	else
		gpu_devices=$gpu_devices:$1
	fi
}
gpu_remember "$gpu_primary"
gpu_remember "$gpu_ig_card"
gpu_remember "$gpu_nv_card"
gpu_remember "$gpu_amd_card"
if [ -n "$gpu_devices" ]; then
	export AQ_DRM_DEVICES="$gpu_devices"
fi
unset -f gpu_remember
unset gpu_nv_card gpu_ig_card gpu_amd_card gpu_amd_boot gpu_sys gpu_base gpu_vendor
unset gpu_nv_connected gpu_nv_name gpu_amd_connected gpu_amd_name gpu_status
unset gpu_mode gpu_mode_raw gpu_config_home gpu_mode_file gpu_primary gpu_devices
# aponhcet.gpu login end
