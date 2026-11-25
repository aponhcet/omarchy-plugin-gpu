// Names from lspci and nvidia-smi are untrusted. plain() strips the
// characters that would start markup, because a shared tooltip or a Text
// left on AutoText can fetch a remote image from a string like
// <img src="https://example.invalid/tracker">.

function plain(value) {
  var text = String(value == null ? "" : value)
  text = text.replace(/[<>&]/g, "")
  if (text.length > 96) text = text.slice(0, 96)
  return text
}

function allowedMode(mode) {
  return mode === "auto" || mode === "intel" || mode === "nvidia"
}

function allowedGpu(gpu) {
  return gpu === "intel" || gpu === "nvidia" || gpu === "other" || gpu === "unknown"
}
