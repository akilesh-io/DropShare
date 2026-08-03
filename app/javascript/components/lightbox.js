let overlay = null
let currentItems = []
let currentIndex = 0

function buildOverlay() {
  const el = document.createElement("div")
  el.className = "lightbox-overlay"
  el.innerHTML = `
    <button type="button" class="lightbox-close" aria-label="Close">&times;</button>
    <button type="button" class="lightbox-prev" aria-label="Previous">&#10094;</button>
    <button type="button" class="lightbox-next" aria-label="Next">&#10095;</button>
    <div class="lightbox-content">
      <img class="lightbox-image" alt="">
    </div>
    <div class="lightbox-caption"></div>
  `
  document.body.appendChild(el)
  return el
}

function showImage(index) {
  currentIndex = (index + currentItems.length) % currentItems.length
  const item = currentItems[currentIndex]

  const img = overlay.querySelector(".lightbox-image")
  img.classList.remove("loaded")
  img.src = item.href
  img.alt = item.dataset.filename || ""
  img.onload = () => img.classList.add("loaded")

  overlay.querySelector(".lightbox-caption").textContent = item.dataset.filename || ""

  const multiple = currentItems.length > 1
  overlay.querySelector(".lightbox-prev").style.display = multiple ? "" : "none"
  overlay.querySelector(".lightbox-next").style.display = multiple ? "" : "none"
}

function openLightbox(items, index) {
  currentItems = items
  if (!overlay) overlay = buildOverlay()
  overlay.classList.add("open")
  document.body.classList.add("lightbox-locked")
  showImage(index)
}

function closeLightbox() {
  if (!overlay) return
  overlay.classList.remove("open")
  document.body.classList.remove("lightbox-locked")
}

document.addEventListener("click", (e) => {
  const link = e.target.closest("a.lightbox-item")
  if (link) {
    e.preventDefault()
    const gallery = link.closest(".file-group")
    const items = Array.from(gallery ? gallery.querySelectorAll("a.lightbox-item") : [link])
    openLightbox(items, items.indexOf(link))
    return
  }

  if (!overlay || !overlay.classList.contains("open")) return

  if (e.target.closest(".lightbox-close")) {
    closeLightbox()
  } else if (e.target.closest(".lightbox-prev")) {
    showImage(currentIndex - 1)
  } else if (e.target.closest(".lightbox-next")) {
    showImage(currentIndex + 1)
  } else if (!e.target.closest(".lightbox-image")) {
    closeLightbox()
  }
})

document.addEventListener("keydown", (e) => {
  if (!overlay || !overlay.classList.contains("open")) return

  if (e.key === "Escape") closeLightbox()
  else if (e.key === "ArrowLeft") showImage(currentIndex - 1)
  else if (e.key === "ArrowRight") showImage(currentIndex + 1)
})
