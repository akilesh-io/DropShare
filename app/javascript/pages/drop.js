import * as ActiveStorage from "@rails/activestorage"
import { DirectUpload } from "@rails/activestorage"

ActiveStorage.start()

const dz = document.querySelector("[data-dropzone]")
const mainInput = document.getElementById("koppu")

if (mainInput) mainInput.multiple = true

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

// prevent browser opening file
;["dragenter", "dragover", "dragleave", "drop"].forEach(event => {
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
  const koppuraiRes = await fetch("/drop/new")
  const koppurai = await koppuraiRes.json()

  const uploads = Array.from(files).map(file => uploadFile(file, koppurai.id, token))
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
