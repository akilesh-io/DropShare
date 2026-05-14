import * as ActiveStorage from "@rails/activestorage"
import { DirectUpload } from "@rails/activestorage"

ActiveStorage.start()

const dz = document.querySelector("[data-dropzone]")
const input = document.getElementById("koppu")

// if (!dz || !input) return

dz.addEventListener("click", () => input.click())
dz.addEventListener("dragover", (e) => e.preventDefault())
dz.addEventListener("drop", (e) => {
  e.preventDefault()
  createFolder(e.dataTransfer.files)
})
input.addEventListener('change', (e) => {
  createFolder(input.files)
  // you might clear the selected files from the input
  input.value = null
})

// prevent browser opening file
;["dragenter", "dragover", "dragleave", "drop"].forEach(event => {
  document.addEventListener(event, (e) => e.preventDefault())
})

async function createFolder(files){
    const token = document.querySelector('meta[name="csrf-token"]').content
    const koppuraiRes = await fetch("/drop/new")
    const koppurai = await koppuraiRes.json()

    const uploads = Array.from(files).map(file => {
          return uploadFile(file, koppurai.id, token)
    })
    await Promise.all(uploads)
}

// UPLOAD FUNCTION
function uploadFile(file, koppuraiId, token) {
  const url = input.dataset.directUploadUrl
  const upload = new DirectUpload(file, url, {
    directUploadWillStoreFileWithXHR: (xhr) => {
      xhr.upload.addEventListener("progress", (event) => {
        const progress = (event.loaded / event.total) * 100
        console.log("Upload:", progress.toFixed(2) + "%")
      })
    }
  })

  upload.create((error, blob) => {
    if (error) {
      console.error(error)
    } else {
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
      .then(res => res.json())
      .then(data => {
        location.reload()
      })
      .finally(() => {
      })
    }
  })
}

// COPY BUTTON
document.addEventListener("click", (e) => {
  if (e.target.matches(".copy-btn")) {
    const link = e.target.dataset.link
    navigator.clipboard.writeText(link)

    e.target.textContent = "Copied!"
    setTimeout(() => (e.target.textContent = "Copy Link"), 1000)
  }
})
