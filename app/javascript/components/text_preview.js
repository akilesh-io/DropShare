const cache = new Map()

let overlay = null
let ticket = 0
let currentText = ""
let copyTimer = null

function buildOverlay() {
  const el = document.createElement("div")
  el.className = "text-preview-overlay"
  el.innerHTML = `
    <div class="text-preview-panel" role="dialog" aria-modal="true" aria-label="File preview">
      <div class="text-preview-header">
        <span class="text-preview-name"></span>
        <button type="button" class="text-preview-copy" aria-label="Copy text" hidden>
          <svg class="icon-copy" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor"
               stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <rect x="9" y="9" width="13" height="13" rx="2" /><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
          </svg>
          <svg class="icon-copied" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor"
               stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="m20 6-11 11-5-5" />
          </svg>
        </button>
        <a class="text-preview-download" aria-label="Download" download>
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor"
               stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><path d="m7 10 5 5 5-5" /><path d="M12 15V3" />
          </svg>
        </a>
        <button type="button" class="text-preview-close" aria-label="Close">&times;</button>
      </div>
      <pre class="text-preview-body" tabindex="0"></pre>
      <div class="text-preview-note" hidden>
        Showing the first part of this file - download it to read the rest.
      </div>
    </div>
  `
  document.body.appendChild(el)
  return el
}

function setBody(text, placeholder) {
  const body = overlay.querySelector(".text-preview-body")
  body.textContent = text
  body.classList.toggle("placeholder", Boolean(placeholder))
  body.scrollTop = 0
  body.scrollLeft = 0

  // A message standing in for the file is not worth copying.
  currentText = placeholder ? "" : text
  overlay.querySelector(".text-preview-copy").hidden = !currentText
  showCopied(false)
}

function showCopied(copied) {
  clearTimeout(copyTimer)
  const button = overlay.querySelector(".text-preview-copy")
  button.classList.toggle("copied", copied)
  button.setAttribute("aria-label", copied ? "Copied" : "Copy text")
  if (copied) copyTimer = setTimeout(() => showCopied(false), 1500)
}

async function copyText() {
  if (!currentText) return

  try {
    await navigator.clipboard.writeText(currentText)
  } catch {
    // A LAN address served over http has no clipboard API; select and copy instead.
    const area = document.createElement("textarea")
    area.value = currentText
    area.style.cssText = "position:fixed;left:-9999px"
    document.body.appendChild(area)
    area.select()
    const copied = document.execCommand("copy")
    area.remove()
    if (!copied) return
  }

  showCopied(true)
}

async function fetchText(url) {
  if (cache.has(url)) return cache.get(url)

  const response = await fetch(url, { headers: { Accept: "text/plain" } })
  if (!response.ok) throw new Error(`Preview failed with ${response.status}`)

  const result = {
    text: await response.text(),
    truncated: response.headers.get("X-Preview-Truncated") === "1"
  }
  cache.set(url, result)
  return result
}

async function openPreview(trigger) {
  if (!overlay) overlay = buildOverlay()

  const filename = trigger.dataset.filename || ""
  const download = overlay.querySelector(".text-preview-download")
  download.href = trigger.dataset.download || ""
  download.download = filename
  download.hidden = !trigger.dataset.download

  overlay.querySelector(".text-preview-name").textContent = filename
  overlay.querySelector(".text-preview-note").hidden = true
  overlay.classList.add("open")
  document.body.classList.add("text-preview-locked")
  setBody("Loading...", true)

  const mine = ++ticket
  try {
    const { text, truncated } = await fetchText(trigger.dataset.preview)
    if (mine !== ticket) return

    setBody(text.length ? text : "This file is empty.", !text.length)
    overlay.querySelector(".text-preview-note").hidden = !truncated
  } catch {
    if (mine !== ticket) return
    setBody("This file could not be previewed. Download it instead.", true)
  }
}

function closePreview() {
  if (!overlay || !overlay.classList.contains("open")) return

  ticket++ // discard whatever is still in flight
  overlay.classList.remove("open")
  document.body.classList.remove("text-preview-locked")
  setBody("", true) // let a large file go before the next one loads
}

document.addEventListener("click", (e) => {
  const trigger = e.target.closest(".text-preview-item")
  if (trigger) return openPreview(trigger)

  if (!overlay || !overlay.classList.contains("open")) return
  if (e.target.closest(".text-preview-copy")) return copyText()

  // The download link navigates on its own; keep the reader open behind it.
  if (e.target.closest(".text-preview-download")) return

  if (e.target.closest(".text-preview-close") || !e.target.closest(".text-preview-panel")) {
    closePreview()
  }
})

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") closePreview()
})
