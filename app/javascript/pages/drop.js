import * as ActiveStorage from "@rails/activestorage"
import { DirectUpload } from "@rails/activestorage"

ActiveStorage.start()

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
  mainInput.addEventListener('change', (e) => {
    createFolder(mainInput.files)
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

  uploadFilesToKoppurai(files, koppuraiId, token)
})

// prevent browser opening file on any drag/drop outside targets
;["dragenter", "dragleave"].forEach(event => {
  document.addEventListener(event, (e) => e.preventDefault())
})

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
  uploadFilesToKoppurai(files, koppuraiId, token)
  el.value = null
})

async function createFolder(files){
  const token = document.querySelector('meta[name="csrf-token"]').content

  // create new folder on server and receive rendered folder HTML
  const res = await fetch('/drop/new', { headers: { 'Accept': 'text/html' } })
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
  const drawer = document.getElementById('drawer-folders') || document.querySelector('.drawer')
  if (drawer && folderEl) {
    const firstChild = drawer.firstElementChild
    if (firstChild) {
      drawer.insertBefore(folderEl, firstChild)
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

function uploadFilesToKoppurai(files, koppuraiId, token) {
  const uploads = Array.from(files).map(file => uploadFile(file, koppuraiId, token))
  return Promise.all(uploads)
}

// UPLOAD FUNCTION
function uploadFile(file, koppuraiId, token) {
  const url = mainInput ? mainInput.dataset.directUploadUrl : null
  if (!url) return Promise.reject(new Error('Direct upload URL not found'))

  return new Promise((resolve, reject) => {
    const upload = new DirectUpload(file, url, {
      directUploadWillStoreFileWithXHR: (xhr) => {
        xhr.upload.addEventListener("progress", (event) => {
          if (!event.lengthComputable) return
          const progress = (event.loaded / event.total) * 100
          console.log(file.name, "Upload:", progress.toFixed(2) + "%")
        })
      }
    })

    upload.create((error, blob) => {
      if (error) {
        console.error('Direct upload error for', file.name, error)
        return reject(error)
      }

      fetch("/drop", {
        method: "POST",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          blob_signed_id: blob.signed_id,
          koppurai_id: koppuraiId
        })
      })
      .then(res => res.text())
      .then(html => {
        const target = document.getElementById(`folder-${koppuraiId}-files`)
        const addBtn = target ? target.querySelector('.add-file-btn') : null
        if (target && html.trim()) {
          if (addBtn) {
            addBtn.insertAdjacentHTML('beforebegin', html)
          } else {
            target.insertAdjacentHTML('beforeend', html)
          }
        }
        resolve({ ok: true })
      })
      .catch(err => {
        console.error('Server error for', file.name, err)
        reject(err)
      })
    })
  })
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
