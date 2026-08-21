// Client for the tus resumable upload protocol: https://tus.io
//
// Sends a file to /tus one chunk at a time, and picks up where it left off whenever a chunk
// fails: after a network error it asks the server how many bytes it holds and continues
// from there. The upload's URL is remembered in local storage, so choosing the same file
// again after a reload resumes rather than starts over.
//
//   const upload = new TusUpload(file, {
//     headers: { "X-CSRF-Token": token },
//     onProgress: ({ loaded, total }) => console.log(loaded / total)
//   })
//
//   const { signedId } = await upload.start()
//
// signedId is the Active Storage blob the finished upload became, ready to be posted to
// the server the same way a direct upload's signed ID was.

const ENDPOINT = "/tus"
const PROTOCOL_VERSION = "1.0.0"
const OFFSET_CONTENT_TYPE = "application/offset+octet-stream"
const SIGNED_ID_HEADER = "Active-Storage-Signed-Id"
const DEFAULT_CHUNK_SIZE = 5 * 1024 * 1024
const DEFAULT_RETRY_DELAYS = [1000, 3000, 7000, 15000]
const STORAGE_PREFIX = "tus:"

// A conflicting offset, a busy upload, a corrupted chunk, or a server that fell over.
const RETRIABLE = new Set([409, 423, 460, 500, 502, 503, 504])
const GONE = new Set([403, 404, 410])

const MESSAGES = {
  412: "The server speaks a different version of the upload protocol",
  413: "The file is larger than this server accepts",
  415: "The server refused the chunk's content type",
  422: "The server refused the upload"
}

export class TusUpload {
  constructor(file, {
    headers = {},
    metadata = { filename: file.name, filetype: file.type },
    chunkSize = DEFAULT_CHUNK_SIZE,
    retryDelays = DEFAULT_RETRY_DELAYS,
    onProgress = null,
    remember = true,
    verifyChunks = true
  } = {}) {
    this.file = file
    this.headers = headers
    this.metadata = metadata
    this.chunkSize = chunkSize
    this.retryDelays = retryDelays
    this.onProgress = onProgress
    this.remember = remember
    this.verifyChunks = verifyChunks

    this.uploadUrl = null
    this.offset = 0
    this.signedId = null
    this.attempt = 0
    this.restarted = false
    this.aborted = false
  }

  // Uploads the file, resuming an earlier attempt at it when there is one, and resolves
  // with the signed ID of the blob it became.
  async start() {
    this.aborted = false

    await this.resolveUpload()

    while (this.offset < this.file.size) {
      if (this.aborted) throw new Error("Upload aborted")
      await this.attemptChunk()
    }

    while (!this.signedId) {
      if (this.aborted) throw new Error("Upload aborted")
      await this.attemptSignedId()
    }

    this.forget()

    return { signedId: this.signedId, uploadUrl: this.uploadUrl }
  }

  // Stops the upload. The bytes the server holds stay there, so a later start() for the
  // same file continues from them -- unless terminate throws them away as well.
  async abort({ terminate = false } = {}) {
    this.aborted = true
    this.request?.abort()

    if (terminate) await this.terminate()
  }

  async terminate() {
    const url = this.uploadUrl
    this.forget()

    if (url) await this.send("DELETE", url)
  }

  // Private

  async resolveUpload() {
    const resumed = await this.resumeRemembered()

    if (!resumed) await this.createUpload()
  }

  // Picks up where an earlier visit left off, when local storage remembers an upload of
  // this file and the server still holds it.
  async resumeRemembered() {
    const url = this.rememberedUrl()
    if (!url) return false

    const upload = await this.head(url)

    if (!upload) {
      this.forget()
      return false
    }

    this.uploadUrl = url
    this.adopt(upload)

    return true
  }

  async createUpload() {
    const response = await this.send("POST", ENDPOINT, null, {
      "Upload-Length": this.file.size,
      "Upload-Metadata": encodeMetadata(this.metadata)
    })

    if (response.status !== 201) throw errorFor(response, this.file)

    const location = response.header("Location")
    if (!location) throw new Error("The server created an upload without a Location")

    this.uploadUrl = new URL(location, window.location.href).toString()
    this.rememberUrl()
    this.adopt(uploadFrom(response))
  }

  // Resolves with null when the server holds none of the upload, which is how an expired or
  // terminated one answers.
  async head(url) {
    const response = await this.send("HEAD", url)

    if (response.ok) return uploadFrom(response)
    if (GONE.has(response.status)) return null

    throw errorFor(response, this.file)
  }

  // Takes the server's word for where the upload stands.
  adopt({ offset, signedId }) {
    this.offset = offset
    this.signedId = signedId
    this.notifyProgress()
  }

  async attemptChunk() {
    try {
      await this.uploadChunk()
      this.attempt = 0
    } catch (error) {
      await this.retryAfter(error)
    }
  }

  // Every byte is on the server and only the blob is missing, which is worth asking about
  // again: a server too busy to finish a large file now may well manage a moment later.
  async attemptSignedId() {
    try {
      await this.ensureSignedId()
    } catch (error) {
      await this.backOff(error)
    }
  }

  // Spends one rung of the ladder, then asks where the server actually got to, since a
  // failed chunk says nothing about how much of it landed. A resync that fails the same way
  // isn't fatal either: the offset stays put and the next attempt asks again.
  async retryAfter(error) {
    await this.backOff(error)

    try {
      await this.resync()
    } catch (resyncError) {
      if (!this.worthRetrying(resyncError)) throw resyncError
    }
  }

  // Waits out one rung of the backoff ladder. An error not worth another go, or one that
  // arrives with no rungs left, is rethrown to the caller instead.
  async backOff(error) {
    const delay = this.retryDelays[this.attempt]
    if (delay === undefined || !this.worthRetrying(error)) throw error

    this.attempt++
    await wait(delay)
  }

  worthRetrying(error) {
    return !this.aborted && error.retriable
  }

  async uploadChunk() {
    const start = this.offset
    const end = Math.min(start + this.chunkSize, this.file.size)
    const chunk = this.file.slice(start, end)

    const response = await this.send("PATCH", this.uploadUrl, chunk, {
      "Upload-Offset": start,
      "Content-Type": OFFSET_CONTENT_TYPE,
      "Upload-Checksum": await this.checksumFor(chunk)
    }, loaded => this.notifyProgress(start + loaded))

    if (response.status === 204) {
      const { offset, signedId } = uploadFrom(response, end)
      this.adopt({ offset, signedId: signedId || this.signedId })
    } else if (GONE.has(response.status)) {
      await this.restart()
    } else {
      throw errorFor(response, this.file)
    }
  }

  async resync() {
    const upload = await this.head(this.uploadUrl)

    if (upload) {
      this.adopt(upload)
    } else {
      await this.restart()
    }
  }

  // The upload expired or was deleted while we were sending it. Start a fresh one, but only
  // once, so a server that keeps losing uploads doesn't get the file forever.
  async restart() {
    if (this.restarted) throw new Error(`Error uploading ${this.file.name}: the upload is no longer on the server`)

    this.restarted = true
    this.forget()
    this.uploadUrl = null
    this.offset = 0

    await this.createUpload()
  }

  // A finished upload answers with the signed ID of the blob it became. Missing it means
  // either a response went astray or every byte landed without a blob coming out of them,
  // so ask once more, then ask the server to finish what it already holds.
  async ensureSignedId() {
    if (this.signedId) return

    const upload = await this.head(this.uploadUrl)
    if (!upload) throw new Error(`${this.file.name} was uploaded, but the server no longer holds it`)

    this.signedId = upload.signedId || await this.finalize(upload.offset)
    if (!this.signedId) throw new Error(`${this.file.name} was uploaded, but the server saved no file`)
  }

  // A PATCH with nothing left to append, which is what turns an upload the server holds
  // every byte of into a blob when the request that should have made one didn't.
  async finalize(offset) {
    const response = await this.send("PATCH", this.uploadUrl, null, {
      "Upload-Offset": offset,
      "Content-Type": OFFSET_CONTENT_TYPE
    })

    if (response.status !== 204) throw errorFor(response, this.file)

    return response.header(SIGNED_ID_HEADER)
  }

  // Needs crypto.subtle, which browsers only expose over HTTPS and on localhost; without it
  // the upload simply goes unverified.
  async checksumFor(chunk) {
    if (!this.verifyChunks || !window.crypto?.subtle) return null

    const digest = await crypto.subtle.digest("SHA-256", await chunk.arrayBuffer())
    return `sha256 ${base64(new Uint8Array(digest))}`
  }

  send(method, url, body = null, headers = {}, onProgress = null) {
    return new Promise((resolve, reject) => {
      const request = new XMLHttpRequest
      const lost = () => reject(networkError(this.file))

      this.request = request
      request.open(method, url, true)
      setHeaders(request, { ...this.headers, ...headers, "Tus-Resumable": PROTOCOL_VERSION })

      if (onProgress) {
        request.upload.addEventListener("progress", event => {
          if (event.lengthComputable) onProgress(event.loaded)
        })
      }

      request.addEventListener("load", () => resolve(responseFrom(request)))
      request.addEventListener("error", lost)
      request.addEventListener("timeout", lost)
      request.addEventListener("abort", () => reject(new Error("Upload aborted")))

      request.send(body)
    })
  }

  notifyProgress(loaded = this.offset) {
    this.onProgress?.({ loaded, total: this.file.size })
  }

  get storageKey() {
    const { name, size, type, lastModified } = this.file
    return `${STORAGE_PREFIX}${ENDPOINT}:${name}:${size}:${type}:${lastModified}`
  }

  rememberedUrl() {
    return this.remember ? storage()?.getItem(this.storageKey) : null
  }

  rememberUrl() {
    if (this.remember) storage()?.setItem(this.storageKey, this.uploadUrl)
  }

  forget() {
    storage()?.removeItem(this.storageKey)
  }
}

function setHeaders(request, headers) {
  for (const [name, value] of Object.entries(headers)) {
    if (value !== null && value !== undefined && value !== "") request.setRequestHeader(name, value)
  }
}

function responseFrom(request) {
  return {
    status: request.status,
    ok: request.status >= 200 && request.status < 300,
    header: name => request.getResponseHeader(name)
  }
}

// What the server just said about the upload: how much of it it holds, and the blob it
// became once the last byte is in.
function uploadFrom(response, fallbackOffset = 0) {
  return {
    offset: integerHeader(response, "Upload-Offset", fallbackOffset),
    signedId: response.header(SIGNED_ID_HEADER)
  }
}

function integerHeader(response, name, fallback) {
  const value = parseInt(response.header(name), 10)
  return Number.isNaN(value) ? fallback : value
}

function networkError(file) {
  const error = new Error(`Lost the connection while uploading ${file.name}`)
  error.retriable = true
  return error
}

function errorFor(response, file) {
  const error = new Error(MESSAGES[response.status] || `Error uploading ${file.name} (${response.status})`)
  error.status = response.status
  error.retriable = RETRIABLE.has(response.status)
  return error
}

// "filename aG9saWRheS5tcDQ=,filetype dmlkZW8vbXA0"
function encodeMetadata(metadata) {
  return Object.entries(metadata)
    .filter(([_key, value]) => value)
    .map(([key, value]) => `${key} ${base64(new TextEncoder().encode(String(value)))}`)
    .join(",")
}

function base64(bytes) {
  return btoa(String.fromCharCode(...bytes))
}

function wait(delay) {
  return new Promise(resolve => setTimeout(resolve, delay))
}

// Local storage throws rather than degrades when it is turned off, and resuming across page
// loads is a nicety, so do without it when it isn't there.
function storage() {
  try {
    return window.localStorage
  } catch {
    return null
  }
}
