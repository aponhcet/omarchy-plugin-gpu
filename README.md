# Desktop GPU

An Omarchy bar widget for a laptop with more than one GPU. It shows which GPU Hyprland is rendering on, and lets you choose Auto, Intel, NVIDIA, or AMD for the next login. AMD appears when that GPU is present.

Hyprland reads `AQ_DRM_DEVICES` once, as it starts. The first device is the desktop GPU. Plugging or unplugging a screen later does not move the desktop. Logging out and back in does.

Auto uses a discrete GPU when a screen is already plugged into it at login, and the integrated GPU when the laptop is on its own. On an Intel and NVIDIA laptop that means NVIDIA with an external screen, and Intel with the lid alone. A discrete AMD GPU follows the same rule. When the only GPU is an AMD integrated one, Auto uses that.

Intel, NVIDIA, or AMD keeps the desktop on that GPU. Choosing the integrated GPU leaves a discrete GPU free to idle.

An application can still pick another GPU. A game can render on NVIDIA while the desktop stays on Intel.

This is for muxless laptops. It does not use `supergfxd`, and it does not switch a hardware mux.

## Install

```bash
omarchy plugin add https://github.com/aponhcet/omarchy-plugin-gpu.git --enable
```

The widget appears on the right side of the bar. Move it with:

```bash
omarchy bar move aponhcet.gpu --section right
```

## Make the choice apply at login

The widget stores the choice in `~/.config/uwsm/gpu-mode` as `auto`, `intel`, `nvidia`, or `amd`. It does not edit any other file. Hyprland will keep its current startup GPU until `~/.config/uwsm/env-hyprland` exports `AQ_DRM_DEVICES`.

If that file already sets `AQ_DRM_DEVICES`, keep it and teach it to read `gpu-mode`. Otherwise create the file and paste this in. `AQ_DRM_DEVICES` splits on `:`, so the paths below are `/dev/dri/cardN` or a colon-free symlink such as `/dev/dri/nvidia-dgpu`. A pci by-path node cannot be used, because its name contains colons.

```sh
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
```

The value in `gpu-mode` is only compared as a prefix. It is never run as a command.

## Use

Left-click the bar label (`iGPU`, `NV`, or `AMD`) to open the panel. Right-click cycles the GPUs that are present, plus Auto. The label uses the accent color when the running desktop and the next login disagree.

The panel lists connected screens and, while it is open, which apps are drawing on Intel, NVIDIA, AMD, or more than one of those, plus NVIDIA load, power, and memory. The bar itself does not call `nvidia-smi` or inspect apps, because that work stays off the polling path that would wake the discrete GPU. AMD shows its PCI name in the open panel and has no power line.

The chevron on **Apps** opens a Desktop choice and one choice for each GPU that is present. A row of dots waves while that list, or the desktop GPU, is being read. Desktop follows the login choice. Intel, NVIDIA, or AMD is remembered by the widget and applied the next time that app starts from its menu. The app that is already open keeps its current GPU until you quit it. A program with no menu entry is still remembered, and the panel says so.

Choosing a mode writes `~/.config/uwsm/gpu-mode` and leaves the session running. When a logout would apply the new GPU, the panel shows **Log out to apply**. A second click asks **Log out now?** and then runs `omarchy system logout`, which closes your applications. Closing the panel disarms that button.

Keys, once the cursor is showing: arrows or `hjkl` move, `a` / `i` / `n` / `m` choose Auto, Intel, NVIDIA, or AMD, `r` refreshes, Enter applies, Escape closes. `m` is AMD.

From a terminal:

```bash
omarchy-shell aponhcet.gpu status
omarchy-shell aponhcet.gpu choose auto
omarchy-shell aponhcet.gpu choose intel
omarchy-shell aponhcet.gpu choose nvidia
omarchy-shell aponhcet.gpu choose amd
omarchy-shell aponhcet.gpu pin chromium intel
omarchy-shell aponhcet.gpu pin chromium amd
omarchy-shell aponhcet.gpu pin chromium desktop
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

It also leaves per-app choices in `~/.config/uwsm/gpu-apps`, the small launchers under `~/.local/share/aponhcet.gpu/bin/`, and menu entries in `~/.local/share/applications/` marked `X-AponhcetGpu=1`. Choose Desktop for those apps before removing the widget, or delete those files. A menu entry left behind points at a launcher that is gone.

## Dependencies

Omarchy with the Quickshell bar, `bash`, and `jq`. `hyprctl` marks which connector is showing the desktop. `lspci` (pciutils) supplies the Intel and AMD product names. `nvidia-smi` supplies the NVIDIA line in the open panel, and is skipped when it is missing. `node` is used only by the test suite.

## Test

```bash
bash test/qa.sh
```

The suite runs in temporary directories. It does not read or write your login GPU, your per-app choices, or the running session. It checks the manifest, the English catalog, plain-text rendering, animation timing, poisoned names, and the launcher files. On Omarchy it also runs `omarchy plugin validate`. GitHub runs the same suite on every push.

## Release

`manifest.json` is the version. `test/qa.sh` requires that same `major.minor.patch` value, and a `CHANGELOG.md` section with that heading.

1. Set the manifest, the assertion in `test/qa.sh`, and the changelog section to the new version.
2. Push to `main` and wait until the test workflow is green on that commit.
3. Tag that commit `vX.Y.Z` and push the tag.

The release workflow runs the same checks, refuses a tag that does not match the manifest, and publishes the GitHub release from the changelog section. It does not change the branch.

## License

MIT. See [LICENSE](LICENSE).
