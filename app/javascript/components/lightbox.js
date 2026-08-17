const AXIS_LOCK = 10
const SWIPE_DISTANCE = 60
const CLOSE_DISTANCE = 110
const FLICK_VELOCITY = 0.4
const FLICK_DISTANCE = 40

let overlay = null
let currentItems = []
let currentIndex = 0
let touch = null
let animating = false
let lastDragEnd = 0

function buildOverlay() {
  const el = document.createElement("div")
  el.className = "lightbox-overlay"
  el.innerHTML = `
    <button type="button" class="lightbox-close" aria-label="Close">&times;</button>
    <a class="lightbox-download" aria-label="Download" download>
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor"
           stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M12 3v12" /><path d="m7 12 5 5 5-5" /><path d="M5 21h14" />
      </svg>
    </a>
    <button type="button" class="lightbox-prev" aria-label="Previous">&#10094;</button>
    <button type="button" class="lightbox-next" aria-label="Next">&#10095;</button>
    <div class="lightbox-content">
      <img class="lightbox-image" alt="">
    </div>
    <div class="lightbox-caption"></div>
  `
  el.addEventListener("touchstart", onTouchStart, { passive: true })
  el.addEventListener("touchmove", onTouchMove, { passive: false })
  el.addEventListener("touchend", onTouchEnd)
  el.addEventListener("touchcancel", onTouchCancel)
  document.body.appendChild(el)
  return el
}

function image() {
  return overlay.querySelector(".lightbox-image")
}

// Backdrop darkness and control opacity, both as 0..1 of their resting value.
function setChrome(dim, chrome) {
  overlay.style.setProperty("--lightbox-dim", (0.92 * dim).toFixed(3))
  overlay.style.setProperty("--lightbox-chrome", chrome.toFixed(3))
}

// Inline styles are only ever used for dragging and transitions, so wiping
// them wholesale hands everything back to the stylesheet.
function resetDrag() {
  overlay.classList.remove("dragging")
  image().style.cssText = ""
  overlay.style.cssText = ""
}

function showImage(index) {
  currentIndex = (index + currentItems.length) % currentItems.length
  const item = currentItems[currentIndex]
  const filename = item.dataset.filename || ""

  resetDrag()

  const img = image()
  img.classList.remove("loaded")
  img.src = item.href
  img.alt = filename
  img.onload = () => img.classList.add("loaded")

  overlay.querySelector(".lightbox-caption").textContent = filename

  // Points at the original upload, not the resized preview being displayed.
  const download = overlay.querySelector(".lightbox-download")
  download.href = item.dataset.download || ""
  download.download = filename
  download.style.display = item.dataset.download ? "" : "none"

  const multiple = currentItems.length > 1
  overlay.querySelector(".lightbox-prev").style.display = multiple ? "" : "none"
  overlay.querySelector(".lightbox-next").style.display = multiple ? "" : "none"
}

// direction: 1 moves to the next image, -1 to the previous one. The outgoing
// image slides away and the incoming one slides in from the opposite edge.
function navigate(direction) {
  if (animating) return
  if (currentItems.length < 2) return resetDrag()
  animating = true

  const distance = Math.max(window.innerWidth * 0.5, 250)
  image().style.cssText = `transform: translateX(${-direction * distance}px); opacity: 0`

  setTimeout(() => {
    showImage(currentIndex + direction)
    image().style.cssText = `transition: none; transform: translateX(${direction * distance}px)`
    requestAnimationFrame(() => {
      image().style.cssText = ""
      animating = false
    })
  }, 160)
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
  resetDrag()
}

// Fling the image off the top or bottom edge, then tear the overlay down.
function dismiss(dy) {
  animating = true
  const offset = dy > 0 ? window.innerHeight : -window.innerHeight
  image().style.cssText = `transform: translateY(${offset}px) scale(0.7); opacity: 0`
  setChrome(0, 0)

  setTimeout(() => {
    closeLightbox()
    animating = false
  }, 200)
}

function onTouchStart(e) {
  const onChrome = e.target.closest(".lightbox-close, .lightbox-download, .lightbox-prev, .lightbox-next")
  const t = e.touches[0]
  touch = animating || onChrome || e.touches.length !== 1
    ? null
    : { x: t.clientX, y: t.clientY, time: Date.now(), dx: 0, dy: 0, axis: null }
}

function onTouchMove(e) {
  if (!touch) return
  if (e.touches.length !== 1) return onTouchCancel()

  touch.dx = e.touches[0].clientX - touch.x
  touch.dy = e.touches[0].clientY - touch.y

  // Lock onto whichever direction the finger commits to first, so a slightly
  // diagonal swipe still does one thing rather than both.
  if (!touch.axis) {
    if (Math.hypot(touch.dx, touch.dy) < AXIS_LOCK) return
    touch.axis = Math.abs(touch.dx) > Math.abs(touch.dy) ? "x" : "y"
    overlay.classList.add("dragging")
  }

  e.preventDefault()

  if (touch.axis === "x") {
    // A lone image has nowhere to go, so its drag gets heavy resistance.
    image().style.transform = `translateX(${touch.dx * (currentItems.length > 1 ? 1 : 0.3)}px)`
  } else {
    const progress = Math.min(Math.abs(touch.dy) / (window.innerHeight * 0.6), 1)
    image().style.transform = `translateY(${touch.dy}px) scale(${1 - progress * 0.25})`
    setChrome(1 - progress * 0.7, 1 - progress)
  }
}

function onTouchEnd() {
  if (!touch) return

  const { axis, dx, dy, time } = touch
  const elapsed = Math.max(Date.now() - time, 1)
  const delta = axis === "x" ? dx : dy
  touch = null
  overlay.classList.remove("dragging")

  // No axis lock means the finger never really moved: let it count as a tap.
  if (!axis) return
  lastDragEnd = Date.now()

  // Commit on a long drag or on a short, fast flick; otherwise spring back.
  const far = Math.abs(delta) > (axis === "x" ? SWIPE_DISTANCE : CLOSE_DISTANCE)
  const flick = Math.abs(delta) > FLICK_DISTANCE && Math.abs(delta) / elapsed > FLICK_VELOCITY

  if (!(far || flick)) resetDrag()
  else if (axis === "x") navigate(dx < 0 ? 1 : -1)
  else dismiss(dy)
}

function onTouchCancel() {
  if (!touch) return // nothing was dragging; don't wipe a running animation
  touch = null
  resetDrag()
}

document.addEventListener("click", (e) => {
  // Touch swipes emit a synthetic click on release; ignore it so a dismiss
  // gesture does not immediately reopen whatever sat under the overlay.
  if (Date.now() - lastDragEnd < 400) return

  const link = e.target.closest("a.lightbox-item")
  if (link) {
    e.preventDefault()
    const gallery = link.closest(".file-group")
    const items = Array.from(gallery ? gallery.querySelectorAll("a.lightbox-item") : [link])
    openLightbox(items, items.indexOf(link))
    return
  }

  if (!overlay || !overlay.classList.contains("open")) return

  // Let the download link navigate, and keep the lightbox open behind it.
  if (e.target.closest(".lightbox-download")) return

  if (e.target.closest(".lightbox-close")) {
    closeLightbox()
  } else if (e.target.closest(".lightbox-prev")) {
    navigate(-1)
  } else if (e.target.closest(".lightbox-next")) {
    navigate(1)
  } else if (!e.target.closest(".lightbox-image")) {
    closeLightbox()
  }
})

document.addEventListener("keydown", (e) => {
  if (!overlay || !overlay.classList.contains("open")) return

  if (e.key === "Escape") closeLightbox()
  else if (e.key === "ArrowLeft") navigate(-1)
  else if (e.key === "ArrowRight") navigate(1)
})
