module DropHelper
  TEXT_CONTENT_TYPES = %w[
    application/json application/ld+json application/xml application/javascript
    application/x-javascript application/typescript application/x-httpd-php
    application/x-ruby application/x-python application/x-perl application/x-sh
    application/x-shellscript application/sql application/graphql
    application/yaml application/x-yaml application/toml application/x-latex
  ].freeze

  TEXT_EXTENSIONS = %w[
    txt text log md markdown rst adoc tex srt vtt csv tsv diff patch
    json jsonl ndjson xml yml yaml toml ini conf cfg config properties env lock sql graphql gql proto
    rb rake ru gemspec erb haml slim py js mjs cjs jsx ts tsx vue svelte
    java kt kts scala go rs c h cpp cc hpp cs m mm swift dart php pl lua r ex exs elm clj hs
    sh bash zsh fish ps1 bat cmd
    html htm css scss sass less styl
  ].freeze

  TEXT_FILENAMES = %w[
    dockerfile dockerignore makefile rakefile gemfile procfile brewfile
    license readme changelog authors notice gitignore gitattributes editorconfig npmrc
  ].freeze

  def text_previewable?(blob)
    extension = blob.filename.extension.to_s.downcase
    return true if TEXT_EXTENSIONS.include?(extension)
    return true if extension.blank? && TEXT_FILENAMES.include?(blob.filename.base.to_s.downcase.delete_prefix("."))

    content_type = blob.content_type.to_s
    content_type.start_with?("text/") || TEXT_CONTENT_TYPES.include?(content_type)
  end

  def attachment_icon(blob)
    extension = blob.filename.extension&.downcase&.strip
    icon = case extension
    when "mp3", "wav", "flac", "m4a", "aac", "ogg", "opus", "weba", "alac", "aiff", "ape", "wma", "mid", "midi"
      "icons/audio.svg"
    when "rb", "ts", "tsx", "jsx", "py", "java", "cpp", "c", "cs", "go", "php", "swift", "kt", "rs", "html", "scss",  "yml", "yaml",
         "rake", "ru", "gemspec", "erb", "mjs", "cjs", "vue", "svelte", "scala", "h", "cc", "hpp", "m", "mm", "dart", "pl", "lua",
         "r", "ex", "exs", "elm", "clj", "hs", "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "sass", "less", "styl", "htm",
         "toml", "ini", "conf", "cfg", "config", "properties", "env", "lock", "graphql", "gql", "proto", "jsonl", "ndjson", "diff", "patch"
      "icons/code.svg"
    when "doc", "docx", "txt", "rtf", "odt", "md", "markdown", "log", "text", "rst", "adoc", "tex", "srt", "vtt"
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
