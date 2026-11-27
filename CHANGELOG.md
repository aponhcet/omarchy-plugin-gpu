# Changelog

## 1.5.0

AMD is now a desktop choice and a per-app choice, beside Intel and NVIDIA.

Auto is unchanged on an Intel and NVIDIA laptop: a screen plugged into NVIDIA still selects NVIDIA for the next login, and the laptop on its own stays on Intel. A discrete AMD GPU follows that same rule when a screen is plugged into it. When the only GPU is an AMD integrated one, Auto uses that.

The panel lists a GPU button only when that GPU is present, so an Intel and NVIDIA machine does not grow an empty AMD control. The bar reads AMD while the desktop is on an AMD GPU, and the open panel shows that GPU's PCI name.

An app pinned to AMD starts on AMD. Chromium is given that render node with `--render-node-override`. Other programs use Mesa's AMD Vulkan driver and `DRI_PRIME` for the same device. The login snippet accepts `amd` in `~/.config/uwsm/gpu-mode`.

## 1.4.0

- The app list shows a traveling row of dots until the first read finishes. A shorter row waves beside the desktop GPU, and beside Apps, only while a later refresh is in flight.
- Each app's Desktop, Intel, or NVIDIA choice opens from a chevron on Apps.
- The project preview shows the compact list and the open choices.

## 1.3.0

- The open panel lists the GPU each app is drawing on.
- Desktop, Intel, or NVIDIA for an app is remembered and applied the next time that app starts. The choice stays hidden until it is opened.
- `test/qa.sh` checks the manifest, catalog, plain text, motion, and launcher files. GitHub runs the same suite.

## 1.0.0

- The bar shows the GPU Hyprland is rendering on, and stores Auto, Intel, or NVIDIA for the next login.
