# Desktop GPU

An Omarchy bar widget for a laptop with Intel graphics and an NVIDIA GPU. It shows which GPU Hyprland is rendering on, and lets you choose Auto, Intel, or NVIDIA for the next login.

Hyprland reads `AQ_DRM_DEVICES` once, as it starts. The first device is the desktop GPU. Plugging or unplugging a screen later does not move the desktop. Logging out and back in does.

Auto uses NVIDIA when a screen is already plugged into it at login, and Intel when the laptop is on its own. Intel keeps the desktop on the integrated GPU, so the NVIDIA GPU can idle. NVIDIA renders the desktop on the NVIDIA GPU even with no external screen.

An application can still pick the other GPU. A game can render on NVIDIA while the desktop stays on Intel.

This is for muxless Intel + NVIDIA laptops. It does not use `supergfxd`, and it does not switch an AMD GPU or a hardware mux.

## Install

```bash
omarchy plugin add https://github.com/aponhcet/omarchy-plugin-gpu.git --enable
```

The widget appears on the right side of the bar. Move it with:

```bash
omarchy bar move aponhcet.gpu --section right
```

## Make the choice apply at login

The widget stores the choice in `~/.config/uwsm/gpu-mode`. It does not edit any other file. Hyprland will keep its current startup GPU until `~/.config/uwsm/env-hyprland` exports `AQ_DRM_DEVICES`.

If that file already sets `AQ_DRM_DEVICES`, keep it and teach it to read `gpu-mode`. Otherwise create the file and paste this in. `AQ_DRM_DEVICES` splits on `:`, so the paths below are `/dev/dri/cardN` or a colon-free symlink such as `/dev/dri/nvidia-dgpu`. A pci by-path node cannot be used, because its name contains colons.

```sh
# Desktop GPU for the next Hyprland login. The bar widget writes
# ~/.config/uwsm/gpu-mode as auto, intel, or nvidia. A missing file means auto.
gpu_nv_card=
gpu_ig_card=
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

gpu_mode=auto
gpu_config_home=${XDG_CONFIG_HOME:-$HOME/.config}
gpu_mode_file=$gpu_config_home/uwsm/gpu-mode
if [ -f "$gpu_mode_file" ]; then
	gpu_mode_raw=$(head -c 16 "$gpu_mode_file" 2>/dev/null || true)
	case $gpu_mode_raw in
		intel*) gpu_mode=intel ;;
		nvidia*) gpu_mode=nvidia ;;
		auto*) gpu_mode=auto ;;
	esac
fi

if [ -n "$gpu_nv_card" ] && [ -n "$gpu_ig_card" ]; then
	if [ "$gpu_mode" = intel ]; then
		export AQ_DRM_DEVICES="$gpu_ig_card:$gpu_nv_card"
	elif [ "$gpu_mode" = nvidia ]; then
		export AQ_DRM_DEVICES="$gpu_nv_card:$gpu_ig_card"
	elif [ "$gpu_nv_connected" -eq 1 ]; then
		export AQ_DRM_DEVICES="$gpu_nv_card:$gpu_ig_card"
	else
		export AQ_DRM_DEVICES="$gpu_ig_card:$gpu_nv_card"
	fi
fi
unset gpu_nv_card gpu_ig_card gpu_sys gpu_base gpu_vendor gpu_nv_connected gpu_nv_name gpu_status
unset gpu_mode gpu_mode_raw gpu_config_home gpu_mode_file
```

The value in `gpu-mode` is only compared as a prefix. It is never run as a command.

## Use

Left-click the bar label (`iGPU` or `NV`) to open the panel. Right-click cycles Auto, Intel, and NVIDIA. The label uses the accent color when the running desktop and the next login disagree.

The panel lists connected screens, and, while it is open, NVIDIA load, power, and memory. The bar itself does not call `nvidia-smi`, because that wakes the discrete GPU.

Choosing a mode writes `~/.config/uwsm/gpu-mode` and leaves the session running. When a logout would apply the new GPU, the panel shows **Log out to apply**. A second click asks **Log out now?** and then runs `omarchy system logout`, which closes your applications. Closing the panel disarms that button.

Keys, once the cursor is showing: arrows or `hjkl` move, `a` / `i` / `n` choose a mode, `r` refreshes, Enter applies, Escape closes.

From a terminal:

```bash
omarchy-shell aponhcet.gpu status
omarchy-shell aponhcet.gpu choose auto
omarchy-shell aponhcet.gpu choose intel
omarchy-shell aponhcet.gpu choose nvidia
```

## Update

```bash
omarchy plugin update aponhcet.gpu
```

## Remove

```bash
omarchy plugin remove aponhcet.gpu
```

Removing the widget leaves `~/.config/uwsm/gpu-mode` and `~/.config/uwsm/env-hyprland` in place. Delete the mode file to return the login rule to Auto, and remove the snippet above if you no longer want it to set `AQ_DRM_DEVICES`.

## Dependencies

Omarchy with the Quickshell bar, `bash`, and `jq`. `hyprctl` marks which connector is showing the desktop. `lspci` (pciutils) supplies the Intel product name. `nvidia-smi` supplies the NVIDIA line in the open panel, and is skipped when it is missing. `node` is used only by `bash gpu-status --self-test`.

## License

MIT. See [LICENSE](LICENSE).
