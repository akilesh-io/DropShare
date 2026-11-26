const AXIS_LOCK = 10
const SWIPE_DISTANCE = 60
const CLOSE_DISTANCE = 110
const FLICK_VELOCITY = 0.4
const FLICK_DISTANCE = 40

const MAX_SCALE = 4
const DOUBLE_TAP_SCALE = 2.5
const DOUBLE_TAP_DELAY = 300
const DOUBLE_TAP_SLOP = 30

let overlay = null
let currentItems = []
let currentIndex = 0
let touch = null
let animating = false
let lastDragEnd = 0
let lastTap = null
let lastTouchAt = 0
let mousePan = null
let wheelTimer = null

// The image's zoom, as a scale and a pan offset (px) from its resting centre.
const zoom = { scale: 1, x: 0, y: 0 }

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
  el.addEventListener("wheel", onWheel, { passive: false })
  el.addEventListener("dblclick", onDoubleClick)
  el.addEventListener("mousedown", onMouseDown)
  document.body.appendChild(el)
  return el
}

function image() {
  return overlay.querySelector(".lightbox-image")
}

function isZoomed() {
  return zoom.scale > 1.01
}

// Backdrop darkness and control opacity, both as 0..1 of their resting value.
function setChrome(dim, chrome) {
  overlay.style.setProperty("--lightbox-dim", (0.92 * dim).toFixed(3))
  overlay.style.setProperty("--lightbox-chrome", chrome.toFixed(3))
}

// Inline styles are only ever used for dragging, zooming and transitions, so
// wiping them wholesale hands everything back to the stylesheet.
function resetDrag() {
  overlay.classList.remove("dragging", "zoomed")
  image().style.cssText = ""
  overlay.style.cssText = ""
  zoom.scale = 1
  zoom.x = 0
  zoom.y = 0
}

// ---- zoom ------------------------------------------------------------------

const clamp = (value, min, max) => Math.min(Math.max(value, min), max)

// The image sits centred in the overlay, so the overlay's centre is the
// transform origin every zoom calculation works from.
function centre() {
  return { x: overlay.clientWidth / 2, y: overlay.clientHeight / 2 }
}

// Keep a zoomed image's edges from pulling in past the screen's edges; an
// image still smaller than the screen on an axis stays centred on it.
function clampPan(scale, x, y) {
  const img = image()
  const maxX = Math.max(0, (img.offsetWidth * scale - overlay.clientWidth) / 2)
  const maxY = Math.max(0, (img.offsetHeight * scale - overlay.clientHeight) / 2)
  return { x: clamp(x, -maxX, maxX), y: clamp(y, -maxY, maxY) }
}

function setZoom(scale, x, y) {
  zoom.scale = clamp(scale, 1, MAX_SCALE)
  const pan = clampPan(zoom.scale, x, y)
  zoom.x = pan.x
  zoom.y = pan.y

  overlay.classList.toggle("zoomed", isZoomed())
  image().style.transform = isZoomed()
    ? `translate(${zoom.x}px, ${zoom.y}px) scale(${zoom.scale})`
    : ""
}

// Zoom to `scale`, keeping the image point under screen point (px, py) still.
function zoomAt(scale, px, py, from = zoom) {
  const c = centre()
  const next = clamp(scale, 1, MAX_SCALE)
  const ratio = next / from.scale
  setZoom(
    next,
    px - c.x - (px - c.x - from.x) * ratio,
    py - c.y - (py - c.y - from.y) * ratio
  )
}

function toggleZoom(px, py) {
  if (isZoomed()) setZoom(1, 0, 0)
  else zoomAt(DOUBLE_TAP_SCALE, px, py)
}

// ---- navigation ------------------------------------------------------------

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

// ---- touch -----------------------------------------------------------------
//
// touch.mode is one of:
//   "swipe"  one finger at rest zoom: swipe sideways to navigate, up/down to close
//   "pan"    one finger while zoomed: move the image around
//   "pinch"  two fingers: zoom around their midpoint, and pan with it

function midpoint(a, b) {
  return { x: (a.clientX + b.clientX) / 2, y: (a.clientY + b.clientY) / 2 }
}

function startPinch(touches) {
  // A second finger landing mid-swipe abandons the swipe.
  image().style.transition = "none"
  overlay.style.cssText = ""
  overlay.classList.add("dragging")

  const [a, b] = touches
  touch = {
    mode: "pinch",
    dist: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY),
    mid: midpoint(a, b),
    from: { ...zoom },
  }
}

function startOneFinger(t, onImage) {
  touch = isZoomed()
    ? { mode: "pan", x: t.clientX, y: t.clientY, from: { ...zoom }, moved: false, onImage }
    : { mode: "swipe", x: t.clientX, y: t.clientY, time: Date.now(), dx: 0, dy: 0, axis: null, onImage }
}

function onTouchStart(e) {
  lastTouchAt = Date.now()
  const onChrome = e.target.closest(".lightbox-close, .lightbox-download, .lightbox-prev, .lightbox-next")

  if (animating || onChrome) touch = null
  else if (e.touches.length === 2) startPinch(e.touches)
  else if (e.touches.length === 1) startOneFinger(e.touches[0], !!e.target.closest(".lightbox-image"))
  else touch = null
}

function onTouchMove(e) {
  if (!touch) return

  if (touch.mode === "pinch") {
    if (e.touches.length < 2) return
    e.preventDefault()
    const [a, b] = e.touches
    const dist = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY)
    const mid = midpoint(a, b)
    const scale = clamp(touch.from.scale * (dist / touch.dist), 1, MAX_SCALE)

    // Hold the image point first under the fingers' midpoint under where the
    // midpoint is now, which pans and zooms in one go.
    const c = centre()
    const ratio = scale / touch.from.scale
    setZoom(
      scale,
      mid.x - c.x - (touch.mid.x - c.x - touch.from.x) * ratio,
      mid.y - c.y - (touch.mid.y - c.y - touch.from.y) * ratio
    )
    return
  }

  if (e.touches.length !== 1) return onTouchCancel()

  if (touch.mode === "pan") {
    e.preventDefault()
    const dx = e.touches[0].clientX - touch.x
    const dy = e.touches[0].clientY - touch.y
    if (!touch.moved && Math.hypot(dx, dy) < AXIS_LOCK) return
    touch.moved = true
    overlay.classList.add("dragging")
    setZoom(touch.from.scale, touch.from.x + dx, touch.from.y + dy)
    return
  }

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

// A quick second tap near the first toggles zoom around the tapped point.
function handleTap(t) {
  const now = Date.now()
  const isDouble = lastTap
    && now - lastTap.time < DOUBLE_TAP_DELAY
    && Math.hypot(t.clientX - lastTap.x, t.clientY - lastTap.y) < DOUBLE_TAP_SLOP

  if (isDouble) {
    lastTap = null
    lastDragEnd = now // swallow the synthetic click
    toggleZoom(t.clientX, t.clientY)
  } else {
    lastTap = { time: now, x: t.clientX, y: t.clientY }
  }
}

function onTouchEnd(e) {
  if (!touch) return

  if (touch.mode === "pinch") {
    lastDragEnd = Date.now()
    lastTap = null
    overlay.classList.remove("dragging")
    image().style.transition = ""
    if (!isZoomed()) setZoom(1, 0, 0)

    // Lifting one finger of two carries on as a pan with the one left down.
    touch = null
    if (e.touches.length === 1 && isZoomed()) startOneFinger(e.touches[0], false)
    return
  }

  if (touch.mode === "pan") {
    const { moved, onImage } = touch
    touch = null
    overlay.classList.remove("dragging")
    if (moved) lastDragEnd = Date.now()
    else if (onImage) handleTap(e.changedTouches[0])
    return
  }

  const { axis, dx, dy, time, onImage } = touch
  const elapsed = Math.max(Date.now() - time, 1)
  const delta = axis === "x" ? dx : dy
  touch = null
  overlay.classList.remove("dragging")

  // No axis lock means the finger never really moved: let it count as a tap.
  if (!axis) {
    if (onImage) handleTap(e.changedTouches[0])
    return
  }
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
  const zoomGesture = touch.mode !== "swipe"
  touch = null

  if (zoomGesture) {
    // Keep whatever zoom the gesture reached rather than snapping back.
    overlay.classList.remove("dragging")
    image().style.transition = ""
  } else {
    resetDrag()
  }
}

// ---- mouse & trackpad ------------------------------------------------------

function onWheel(e) {
  if (animating) return
  e.preventDefault()

  // Trackpad pinches arrive as ctrl+wheel with small deltas.
  const speed = e.ctrlKey ? 0.01 : 0.002
  overlay.classList.add("dragging")
  zoomAt(zoom.scale * Math.exp(-e.deltaY * speed), e.clientX, e.clientY)

  clearTimeout(wheelTimer)
  wheelTimer = setTimeout(() => overlay.classList.remove("dragging"), 150)
}

function onDoubleClick(e) {
  // Touch double-taps are handled in handleTap; some browsers also fire a dblclick.
  if (Date.now() - lastTouchAt < 1000) return
  if (!e.target.closest(".lightbox-image")) return
  toggleZoom(e.clientX, e.clientY)
}

function onMouseDown(e) {
  if (e.button !== 0 || !isZoomed() || !e.target.closest(".lightbox-image")) return
  e.preventDefault()
  mousePan = { x: e.clientX, y: e.clientY, from: { ...zoom }, moved: false }
  overlay.classList.add("dragging", "panning")
}

window.addEventListener("mousemove", (e) => {
  if (!mousePan) return
  const dx = e.clientX - mousePan.x
  const dy = e.clientY - mousePan.y
  if (Math.hypot(dx, dy) > 3) mousePan.moved = true
  setZoom(mousePan.from.scale, mousePan.from.x + dx, mousePan.from.y + dy)
})

window.addEventListener("mouseup", () => {
  if (!mousePan) return
  if (mousePan.moved) lastDragEnd = Date.now()
  mousePan = null
  overlay.classList.remove("dragging", "panning")
})

// ---- clicks & keys ---------------------------------------------------------

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
  else if (e.key === "+" || e.key === "=") zoomAt(zoom.scale * 1.5, centre().x, centre().y)
  else if (e.key === "-") zoomAt(zoom.scale / 1.5, centre().x, centre().y)
  else if (e.key === "0") setZoom(1, 0, 0)
})
