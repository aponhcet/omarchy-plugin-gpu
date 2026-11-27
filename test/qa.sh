#!/bin/bash
# Hermetic checks for this plugin. Does not read or write the login GPU,
# the per-app choices, or the running session.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

fail() {
  echo "qa: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v node >/dev/null 2>&1 || fail "node is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

bash -n gpu-status
bash -n gpu-launch
[[ -x gpu-status && -x gpu-launch ]] || fail "gpu-status and gpu-launch must be executable"

link=$(find . -name .git -prune -o -type l -print -quit)
[[ -z $link ]] || fail "symlink inside the plugin: $link"

jq -e '.schemaVersion == 1 and .id == "aponhcet.gpu" and .version == "1.5.0"' manifest.json >/dev/null \
  || fail "manifest id, schema, or version"
version=$(jq -r .version manifest.json)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be major.minor.patch"
grep -qx "## $version" CHANGELOG.md || fail "CHANGELOG.md has no section for $version"
jq -e '(.kinds | index("bar-widget")) != null and .entryPoints.barWidget == "Panel.qml"' manifest.json >/dev/null \
  || fail "manifest must load Panel.qml as a bar widget"
[[ -f LICENSE && -f README.md && -f preview.png ]] || fail "missing LICENSE, README, or preview.png"
grep -q '^## Install' README.md || fail "README needs an Install section"
grep -q '^## Remove' README.md || fail "README needs a Remove section"

python3 - "$root" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
panel = (root / "Panel.qml").read_text() + "\n" + (root / "DotWave.qml").read_text()
catalog = json.loads((root / "i18n" / "en.json").read_text())
if not isinstance(catalog, dict) or not catalog:
    raise SystemExit("qa: en.json must be a flat catalog")
for key, value in catalog.items():
    if not isinstance(key, str) or not isinstance(value, str) or not value.strip():
        raise SystemExit(f"qa: en.json entry {key!r} must be a non-empty string")
    if re.search(r"[<>&]", value):
        raise SystemExit(f"qa: en.json {key} contains markup characters")

used = set(re.findall(r'strings\.t\("([^"]+)"\)', panel))
used.update(("gpu.outputDesktop", "gpu.outputConnected"))
missing = sorted(used - catalog.keys())
if missing:
    raise SystemExit("qa: Panel.qml uses unknown strings: " + ", ".join(missing))

lines = panel.splitlines()
for index, line in enumerate(lines):
    if "duration:" in line and "Style.duration(" not in line:
        raise SystemExit("qa: animation duration must use Style.duration: " + line.strip())
    if re.search(r"Easing\.In", line):
        raise SystemExit("qa: ease-in is not used: " + line.strip())
    match = re.search(r"Style\.duration\((\d+)", line)
    if not match:
        continue
    ms = int(match.group(1))
    window = "\n".join(lines[max(0, index - 4):index + 8])
    # Entrances stay under 300ms. The loading wave is a linear spinner.
    if "Easing.Linear" in window:
        if ms > 1200:
            raise SystemExit("qa: spinner longer than 1200ms: " + line.strip())
    elif ms > 300:
        raise SystemExit("qa: animation longer than 300ms: " + line.strip())

if "property bool appsAdvanced: false" not in panel:
    raise SystemExit("qa: per-app choices must start hidden")
if 'strings.t("gpu.advanced")' not in panel or 'strings.t("gpu.appDesktopTip")' not in panel:
    raise SystemExit("qa: Advanced button or Desktop note is missing")
if re.search(r'property: "scale"\s*\n\s*from: 0(?:\.0+)?\s*$', panel, re.M):
    raise SystemExit("qa: scale must not start at 0")

# Untrusted text has to stay PlainText. Walk Text blocks by braces.
depth = 0
block = None
start_depth = None
for raw in panel.splitlines(True):
    if block is None and re.search(r"\bText\s*\{", raw):
        block = [raw]
        start_depth = depth + raw.count("{") - raw.count("}")
        depth += raw.count("{") - raw.count("}")
        if depth < start_depth:
            block = None
        continue
    depth += raw.count("{") - raw.count("}")
    if block is not None:
        block.append(raw)
        if depth < start_depth:
            body = "".join(block)
            untrusted = any(token in body for token in (
                "modelData", "root.error", "root.mark", "intelName", "nvidiaName", "nvidiaUtil"))
            if untrusted and "textFormat: Text.PlainText" not in body:
                raise SystemExit("qa: untrusted text is not PlainText:\n" + body[:400])
            block = None
PY

bash gpu-status --self-test

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$root"
fi

echo "qa ok"
