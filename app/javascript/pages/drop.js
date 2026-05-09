import * as ActiveStorage from "@rails/activestorage"
import { DirectUpload } from "@rails/activestorage"

ActiveStorage.start()

const dz = document.querySelector("[data-dropzone]")
const input = document.getElementById("koppu_attachment")

// if (!dz || !input) return

let dragCounter = 0

// --------------------------
// CLICK UPLOAD
// --------------------------
dz.addEventListener("click", () => input.click())

input.addEventListener("change", () => {
  const file = input.files[0]
  if (file) upload(file)
})

// --------------------------
// LOCAL DROPZONE
// --------------------------
dz.addEventListener("dragover", (e) => e.preventDefault())

dz.addEventListener("drop", (e) => {
  e.preventDefault()
  const file = e.dataTransfer.files[0]
  if (file) upload(file)
})

// prevent browser opening file
;["dragenter", "dragover", "dragleave", "drop"].forEach(event => {
  document.addEventListener(event, (e) => e.preventDefault())
})

document.addEventListener("dragenter", () => {
  dragCounter++
})

document.addEventListener("dragleave", () => {
  dragCounter--
  if (dragCounter === 0) {
  }
})

document.addEventListener("drop", (e) => {
  dragCounter = 0

  const file = e.dataTransfer.files[0]
  if (file) upload(file)
})

// --------------------------
// COPY BUTTON
// --------------------------
document.addEventListener("click", (e) => {
  if (e.target.matches(".copy-btn")) {
    const link = e.target.dataset.link
    navigator.clipboard.writeText(link)

    e.target.textContent = "Copied!"
    setTimeout(() => (e.target.textContent = "Copy Link"), 1000)
  }
})

// --------------------------
// UPLOAD FUNCTION
// --------------------------
function upload(file) {
  const url = input.dataset.directUploadUrl
  const upload = new DirectUpload(file, url)
  // const upload = new DirectUpload(file, url, {
  //   directUploadWillStoreFileWithXHR: (xhr) => {
  //     xhr.upload.addEventListener("progress", (event) => {
  //       const progress = (event.loaded / event.total) * 100
  //       console.log("Upload:", progress.toFixed(2) + "%")
  //     })
  //   }
  // })

  upload.create((error, blob) => {
    if (error) {
      console.error(error)
    } else {
      fetch("/drop", {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          blob_signed_id: blob.signed_id
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
