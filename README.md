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

That command is the whole install. The first time the widget loads, it writes the login rule into `~/.config/uwsm/env-hyprland`, unless that file already exports `AQ_DRM_DEVICES`.

The widget appears on the right side of the bar. Move it with:

```bash
omarchy bar move aponhcet.gpu --section right
```

## Make the choice apply at login

The widget stores the choice in `~/.config/uwsm/gpu-mode` as `auto`, `intel`, `nvidia`, or `amd`. The first time it loads, it copies `login.sh` into `~/.config/uwsm/env-hyprland`, between `# aponhcet.gpu login` and `# aponhcet.gpu login end`.

A file that already exports `AQ_DRM_DEVICES` is left as it is. A block this widget already wrote is replaced with the current `login.sh`, and the lines around that block stay. Logging out is what moves the desktop. Hyprland reads `AQ_DRM_DEVICES` only while it is starting.

The value in `gpu-mode` is only compared as a prefix. It is never run as a command. `AQ_DRM_DEVICES` splits on `:`, so the login rule uses `/dev/dri/cardN` or a colon-free symlink such as `/dev/dri/nvidia-dgpu`. A pci by-path node cannot be used, because its name contains colons.

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

Removing the widget leaves `~/.config/uwsm/gpu-mode` and the marked block in `~/.config/uwsm/env-hyprland` in place. Delete the mode file to return to Auto. Delete the lines between `# aponhcet.gpu login` and `# aponhcet.gpu login end` to stop setting `AQ_DRM_DEVICES`.

It also leaves per-app choices in `~/.config/uwsm/gpu-apps`, the small launchers under `~/.local/share/aponhcet.gpu/bin/`, and menu entries in `~/.local/share/applications/` marked `X-AponhcetGpu=1`. Choose Desktop for those apps before removing the widget, or delete those files. A menu entry left behind points at a launcher that is gone.

## Dependencies

Omarchy with the Quickshell bar, `bash`, and `jq`. `hyprctl` marks which connector is showing the desktop. `lspci` (pciutils) supplies the Intel and AMD product names. `nvidia-smi` supplies the NVIDIA line in the open panel, and is skipped when it is missing. `node` is used only by the test suite.

## Test

```bash
bash test/qa.sh
```

The suite runs in temporary directories. It does not read or write your login GPU, your per-app choices, or the running session. It checks the manifest, the English catalog, plain-text rendering, animation timing, poisoned names, the launcher files, and the login installer. On Omarchy it also runs `omarchy plugin validate`. GitHub runs the same suite on every push.

## Release

`manifest.json` is the version. `test/qa.sh` requires that same `major.minor.patch` value, and a `CHANGELOG.md` section with that heading.

1. Set the manifest, the assertion in `test/qa.sh`, and the changelog section to the new version.
2. Push to `main` and wait until the test workflow is green on that commit.
3. Tag that commit `vX.Y.Z` and push the tag.

The release workflow runs the same checks, refuses a tag that does not match the manifest, and publishes the GitHub release from the changelog section. It does not change the branch.

## License

MIT. See [LICENSE](LICENSE).
