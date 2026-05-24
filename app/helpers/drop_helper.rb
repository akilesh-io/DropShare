module DropHelper
  def attachment_icon(blob)
    extension = blob.filename.extension&.downcase

    icon = case extension
    when "mp3", "wav", "flac", "m4a", "aac", "ogg", "opus", "weba", "alac", "aiff", "ape", "wma", "mid", "midi"
      "icons/audio.svg"
    when "rb", "ts", "tsx", "jsx", "py", "java", "cpp", "c", "cs", "go", "php", "swift", "kt", "rs", "html", "scss",  "yml", "yaml"
      "icons/code.svg"
    when "doc", "docx", "txt", "rtf", "odt"
      "icons/document.svg"
    when "xls", "xlsx", "csv", "ods"
      "icons/spreadsheets.svg"
    when "jpg", "jpeg", "png", "gif", "webp", "svg", "avif", "heic"
      "icons/image.svg"
    when "mp4", "mov", "avi", "mkv", "webm", "m4v"
      "icons/video.svg"
    when "pdf"
      "icons/pdf-simple.svg"
    when "zip", "rar", "tar", "gz", "bz2", "xz", "7z"
      "icons/zip.svg"
    when nil , ""
      "icons/empty.svg"
    else
      "icons/#{extension}.svg"
    end
    asset_exists?(icon) ? icon : "icons/empty.svg"
  end


  private

  def asset_exists?(path)
    Rails.root.join("app/assets/images", path).exist?
  end
end
