import * as ActiveStorage from "@rails/activestorage"
import { DirectUpload } from "@rails/activestorage"

ActiveStorage.start()

document.addEventListener("turbo:load", () => {

  const dz = document.getElementById("dropzone")
  const input = document.getElementById("fileInput")
  const linkBox = document.getElementById("linkBox")
  const globalDrop = document.getElementById("globalDrop")

  if (!dz || !input) return

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

  // --------------------------
  // GLOBAL DRAG (FULL SCREEN)
  // --------------------------

  // prevent browser opening file
  ;["dragenter", "dragover", "dragleave", "drop"].forEach(event => {
    document.addEventListener(event, (e) => e.preventDefault())
  })

  document.addEventListener("dragenter", () => {
    dragCounter++
    globalDrop?.classList.add("active")
  })

  document.addEventListener("dragleave", () => {
    dragCounter--
    if (dragCounter === 0) {
      globalDrop?.classList.remove("active")
    }
  })

  document.addEventListener("drop", (e) => {
    dragCounter = 0
    globalDrop?.classList.remove("active")

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
    globalDrop?.classList.add("active")
    globalDrop?.classList.add("uploading")

    upload.create((error, blob) => {
      if (error) {
        console.error(error)
        globalDrop?.classList.remove("uploading")
      } else {
        fetch("/uploads", {
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
          linkBox.innerHTML =
            `<input value="${data.link}" style="width:100%" />`
          location.reload()
        })
        .finally(() => {
          globalDrop?.classList.remove("uploading")
        })
      }
    })
  }
})
