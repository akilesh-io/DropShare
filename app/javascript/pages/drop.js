import { TusUpload } from "components/tus_upload"

const dz = document.querySelector("[data-dropzone]")
const mainInput = document.getElementById("koppu")

if (mainInput) mainInput.multiple = true

let currentDragFolder = null

if (dz && mainInput) {
  dz.addEventListener("click", () => mainInput.click())
  dz.addEventListener("dragover", (e) => e.preventDefault())
  dz.addEventListener("drop", (e) => {
    e.preventDefault()
    createFolder(e.dataTransfer.files)
  })
  mainInput.addEventListener('change', () => {
    const files = Array.from(mainInput.files)
    mainInput.value = null
    createFolder(files)
  })
}

// folder-level drag/drop support
document.addEventListener("dragover", (event) => {
  const folder = event.target.closest('.folder')
  if (folder) {
    event.preventDefault()
    folder.classList.add('folder-drag-over')
    currentDragFolder = folder
  }
})

document.addEventListener('dragenter', (event) => {
  const folder = event.target.closest('.folder')
  if (!folder) return
  if (currentDragFolder && currentDragFolder !== folder) {
    currentDragFolder.classList.remove('folder-drag-over')
  }
  currentDragFolder = folder
  folder.classList.add('folder-drag-over')
})

document.addEventListener('dragleave', (event) => {
  const folder = event.target.closest('.folder')
  if (!folder) return
  const related = event.relatedTarget
  if (related && folder.contains(related)) return
  folder.classList.remove('folder-drag-over')
  if (currentDragFolder === folder) currentDragFolder = null
})

document.addEventListener("drop", (event) => {
  const folder = event.target.closest('.folder')
  if (!folder) return

  event.preventDefault()
  event.stopPropagation()
  folder.classList.remove('folder-drag-over')
  currentDragFolder = null

  const files = event.dataTransfer.files
  const koppuraiId = folder.dataset.folderId
  const token = document.querySelector('meta[name="csrf-token"]').content
  if (!files || !files.length || !koppuraiId) return

  uploadFilesToFolder(files, koppuraiId, token)
})

// prevent browser opening file on any drag/drop outside targets
;["dragenter", "dragover", "dragleave", "drop"].forEach(event => {
  document.addEventListener(event, (e) => e.preventDefault())
})

// PASTE TO UPLOAD
document.addEventListener("paste", (event) => {
  if (event.target.closest?.("input, textarea, [contenteditable]")) return

  const files = clipboardFiles(event.clipboardData)
  if (!files.length) return

  event.preventDefault()
  createFolder(files)
})

function clipboardFiles(clipboardData) {
  if (!clipboardData) return []

  const files = [
    ...Array.from(clipboardData.files || []),
    ...Array.from(clipboardData.items || [])
      .filter(item => item.kind === "file")
      .map(item => item.getAsFile())
      .filter(Boolean)
  ]

  const unique = new Map(files.map(file => [`${file.name}:${file.size}:${file.lastModified}`, file]))
  return [...unique.values()]
}

// Click handler for per-folder add buttons
document.addEventListener('click', (e) => {
  const btn = e.target.closest('.add-file-btn')
  if (!btn) return
  const id = btn.dataset.koppuraiId
  const fileInput = document.getElementById(`koppu-input-${id}`)
  if (fileInput) fileInput.click()
})

// Handle per-folder file input changes
document.addEventListener('change', (e) => {
  const el = e.target
  if (!el.classList || !el.classList.contains('koppu-input')) return
  const files = el.files
  const koppuraiId = el.dataset.koppuraiId
  if (!files || !files.length) return
  const token = document.querySelector('meta[name="csrf-token"]').content
  uploadFilesToFolder(files, koppuraiId, token)
  el.value = null
})

function ensureDrawer() {
  let drawer = document.getElementById('drawer-folders')
  if (drawer) return drawer

  drawer = document.createElement('aside')
  drawer.className = 'drawer'
  drawer.id = 'drawer-folders'
  drawer.innerHTML = '<h3 class="heading-xs">Share Files</h3>'

  const statsEl = document.querySelector('.stats')
  if (statsEl) {
    statsEl.replaceWith(drawer)
  } else {
    document.querySelector('.main').insertAdjacentElement('afterend', drawer)
  }

  return drawer
}

async function createFolder(files){
  const token = document.querySelector('meta[name="csrf-token"]').content

  // create new folder on server and receive rendered folder HTML
  const res = await fetch('/drop/new', {
    method: 'POST',
    headers: { 'Accept': 'text/html', 'X-CSRF-Token': token }
  })
  if (!res.ok) {
    console.error('Failed to create folder', res.status)
    return
  }
  const html = await res.text()
  if (!html || !html.trim()) {
    console.error('Empty folder HTML from server')
    return
  }

  // parse and insert the new folder element
  const temp = document.createElement('div')
  temp.innerHTML = html
  const folderEl = temp.firstElementChild
  const drawer = ensureDrawer()
  if (drawer && folderEl) {
    const existingFolder = drawer.querySelector('.folder')
    if (existingFolder) {
      drawer.insertBefore(folderEl, existingFolder)
    } else {
      drawer.appendChild(folderEl)
    }
  }

  const koppuraiId = folderEl && folderEl.dataset && folderEl.dataset.folderId
  if (!koppuraiId) {
    console.error('Could not determine new koppurai id')
    return
  }

  const uploads = Array.from(files).map(file => uploadFile(file, koppuraiId, token))
  try {
    await Promise.all(uploads)
  } catch (err) {
    console.error('One or more uploads failed', err)
  }
}

function uploadFilesToFolder(files, koppuraiId, token) {
  const uploads = Array.from(files).map(file => uploadFile(file, koppuraiId, token))
  return Promise.all(uploads)
}

// UPLOAD PROGRESS CARD
const RING = 2 * Math.PI * 48
const RING_LABELS = { processing: 'Saving', error: 'Failed' }

function humanFileSize(bytes) {
  if (!Number.isFinite(bytes)) return ""

  const units = ["Bytes", "KB", "MB", "GB", "TB"]
  let size = bytes, unit = 0
  while (size >= 1024 && unit < units.length - 1) { size /= 1024; unit += 1 }

  return `${unit === 0 ? size : size.toFixed(1)} ${units[unit]}`
}

function createUploadCard(file, koppuraiId) {
  const target = document.getElementById(`folder-${koppuraiId}-files`)
  if (!target) return null

  const card = document.createElement('div')
  card.className = 'file file-uploading'
  card.title = file.name
  card.innerHTML = `
    <div class="file-preview">
      <div class="upload-progress">
        <svg class="progress-ring" viewBox="0 0 120 120" aria-hidden="true">
          <circle class="progress-ring-bg" cx="60" cy="60" r="48"></circle>
          <circle class="progress-ring-bar" cx="60" cy="60" r="48"></circle>
        </svg>
        <span class="progress-label" role="progressbar" aria-valuemin="0" aria-valuemax="100"></span>
      </div>
    </div>
    <div class="file-meta"><p class="text-xs"></p><p class="text-xs"></p></div>`

  const [nameEl, sizeEl] = card.querySelectorAll('.file-meta p')
  nameEl.textContent = file.name
  sizeEl.textContent = humanFileSize(file.size)

  target.insertBefore(card, target.querySelector('.add-file-btn')) // null anchor appends
  setCardState(card, 'uploading', 0)
  return card
}

// uploading: arc fills to percent · processing: quarter arc, spun by CSS · error: full red ring
function setCardState(card, state, percent = 100) {
  if (!card) return

  const bar = card.querySelector('.progress-ring-bar')
  const label = card.querySelector('.progress-label')
  const value = Math.round(Math.max(0, Math.min(100, percent)))

  card.dataset.uploadState = state
  bar.style.strokeDasharray = state === 'processing' ? `${RING * 0.25} ${RING}` : RING
  bar.style.strokeDashoffset = state === 'uploading' ? RING * (1 - value / 100) : 0
  label.textContent = RING_LABELS[state] || `${value}%`
  if (state === 'uploading') label.setAttribute('aria-valuenow', value)
}

// UPLOAD FUNCTION
async function uploadFile(file, koppuraiId, token) {
  const card = createUploadCard(file, koppuraiId)

  const upload = new TusUpload(file, {
    headers: { "X-CSRF-Token": token },
    onProgress: ({ loaded, total }) => setCardState(card, 'uploading', (loaded / total) * 100)
  })

  try {
    const { signedId } = await upload.start()

    setCardState(card, 'processing')
    swapCardForFile(card, await attachToFolder(signedId, koppuraiId, token), koppuraiId)

    return { ok: true }
  } catch (error) {
    console.error('Upload failed for', file.name, error)
    setCardState(card, 'error')
    if (card) card.title = `${file.name} — ${error.message}`
    throw error
  }
}

// Hands the finished blob to the folder, which renders the file back to us.
async function attachToFolder(signedId, koppuraiId, token) {
  const res = await fetch("/drop", {
    method: "POST",
    headers: { "X-CSRF-Token": token, "Content-Type": "application/json" },
    body: JSON.stringify({ blob_signed_id: signedId, koppurai_id: koppuraiId })
  })

  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    throw new Error(data.error || `Upload failed (${res.status})`)
  }

  return res.text()
}

// Swap the progress card for the rendered file, keeping its position.
function swapCardForFile(card, html, koppuraiId) {
  const anchor = card && card.isConnected
    ? card
    : document.querySelector(`#folder-${koppuraiId}-files .add-file-btn`)

  if (html.trim() && anchor) anchor.insertAdjacentHTML('beforebegin', html)
  if (card) card.remove()
}

// COPY BUTTON
document.addEventListener("click", (e) => {
  if (e.target.matches(".copy-btn")) {
    const link = e.target.dataset.link
    navigator.clipboard.writeText(link)

    e.target.textContent = "Copied"
    setTimeout(() => (e.target.textContent = "Copy"), 1000)
  }
})
