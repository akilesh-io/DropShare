function download(url) {
  const a = document.createElement("a")
  a.href = url
  a.download = ""
  a.click()
}

document.addEventListener("click", (e) => {
  const btn = e.target.closest(".download-all-btn")
  if (!btn) return

  const urls = JSON.parse(
    btn.closest(".folder").dataset.downloadUrls
  )

  urls.forEach((url, i) => {
    setTimeout(() => download(url), i * 250)
  })
})

