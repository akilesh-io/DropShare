function formatTime(seconds) {
  if (!seconds || isNaN(seconds)) return "0:00"

  const m = Math.floor(seconds / 60)
  const s = Math.floor(seconds % 60)

  return `${m}:${String(s).padStart(2, "0")}`
}

function initAudioPlayers() {
  document.querySelectorAll("[data-audio-player]").forEach(player => {
    if (player.dataset.initialized) return
    player.dataset.initialized = "true"

    const audio = player.querySelector("audio")
    const btn = player.querySelector(".audio-btn")
    const progress = player.querySelector(".wheel-progress")
    const wheel = player.querySelector(".audio-wheel")
    const time = player.querySelector(".audio-time")

    const circumference = 314.16

    btn.addEventListener("click", () => {
      if (audio.paused) {
        // pause all other players
        document.querySelectorAll("[data-audio-player] audio").forEach(other => {
          if (other !== audio) {
            other.pause()

            const otherPlayer = other.closest("[data-audio-player]")
            otherPlayer.querySelector(".audio-btn").textContent = "▶"
          }
        })

        audio.play()
        btn.textContent = "❚❚"
      } else {
        audio.pause()
        btn.textContent = "▶"
      }
    })

    audio.addEventListener("timeupdate", () => {
      if (!audio.duration) return

      const percent = audio.currentTime / audio.duration

      progress.style.strokeDashoffset =
        circumference * (1 - percent)

      time.textContent = formatTime(audio.currentTime)
    })

    audio.addEventListener("loadedmetadata", () => {
      time.textContent = formatTime(audio.duration)
    })

    audio.addEventListener("ended", () => {
      btn.textContent = "▶"
      progress.style.strokeDashoffset = circumference
    })

    wheel.addEventListener("click", e => {
      const rect = wheel.getBoundingClientRect()

      const x = e.clientX - rect.left - rect.width / 2
      const y = e.clientY - rect.top - rect.height / 2

      let angle = Math.atan2(y, x) * 180 / Math.PI + 90

      if (angle < 0) angle += 360

      const percent = angle / 360

      if (audio.duration) {
        audio.currentTime = percent * audio.duration
      }
    })
  })
}

document.addEventListener("turbo:load", initAudioPlayers)

