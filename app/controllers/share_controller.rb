class ShareController < ApplicationController
  include ActionController::Live

  TEXT_PREVIEW_BYTES = 256.kilobytes

  before_action :set_koppurai, only: [:index, :download_folder]
  before_action :ensure_not_expired, only: [:index, :download_folder]

  def index
  end

  def download_koppu
    koppu = Koppu.find_by!(share_key: params[:share_key])
    return render plain: "Expired", status: :gone if koppu.koppurai.expired?

    koppu.increment!(:downloads_count)
    Koppurai.update_counters(koppu.koppurai_id, downloads_count: 1)
    Stat.instance.increment!(:total_downloads)

    redirect_to rails_blob_url(koppu.koppu, disposition: "attachment")
  rescue ActiveRecord::RecordNotFound
    render plain: "Page not found or link expired", status: :not_found
    # redirect_to root_path, alert: "Page not found or link expired"
  end

  def text_preview
    koppu = Koppu.find_by!(share_key: params[:share_key])
    return render plain: "Expired", status: :gone if koppu.koppurai.expired?

    blob = koppu.koppu.blob
    return render plain: "Preview not available", status: :unsupported_media_type unless helpers.text_previewable?(blob)

    response.set_header("X-Preview-Truncated", "1") if blob.byte_size > TEXT_PREVIEW_BYTES
    render plain: text_head(blob), content_type: "text/plain"
  end

  def download_folder
    koppus = @koppurai.koppus.select { |koppu| koppu.koppu.attached? }
    return render plain: "No files to download", status: :not_found if koppus.empty?

    Tempfile.create(["koppurai-#{@koppurai.id}-", ".zip"], binmode: true) do |zip|
      Zip::OutputStream.write_buffer(zip) { |zos| write_koppus(zos, koppus) }.rewind

      send_stream(filename: zip_filename, type: :zip) do |stream|
        stream.write(zip.read(64.kilobytes)) until zip.eof?
      end
      record_koppurai_download(koppus.size)
    end
  rescue IOError, Errno::EPIPE
    # visitor closed the connection mid-download - nothing left to do
  end

  private

  def set_koppurai
    @koppurai = Koppurai
      .includes(koppus: [koppu_attachment: :blob])
      .find_by(share_key: params[:share_key])
    redirect_to root_path, alert: "Page not found or link expired" if @koppurai.nil?
  end

  def ensure_not_expired
    render plain: "Expired", status: :gone if @koppurai&.expired?
  end

  def text_head(blob)
    bytes = +(blob.service.download_chunk(blob.key, 0...TEXT_PREVIEW_BYTES) || "")
    bytes.force_encoding(Encoding::UTF_8).scrub("�").delete_prefix("﻿")
  end

  # Streams every attachment into the archive, chunk by chunk, so a folder
  # never has to fit in memory.
  def write_koppus(zos, koppus)
    used_names = Hash.new(0)

    koppus.each do |koppu|
      zos.put_next_entry(unique_entry_name(koppu.koppu.filename.to_s, used_names))
      koppu.koppu.blob.download { |chunk| zos << chunk }
    end
  end

  def unique_entry_name(filename, used_names)
    name = File.basename(filename.to_s.tr("\\", "/"))
    name = "file" if name.blank? || name.match?(/\A\.\.?\z/)

    count = used_names[name]
    used_names[name] += 1
    return name if count.zero?

    ext = File.extname(name)
    "#{File.basename(name, ext)} (#{count})#{ext}"
  end

  def record_koppurai_download(file_count)
    @koppurai.koppus.update_all("downloads_count = downloads_count + 1")
    Koppurai.update_counters(@koppurai.id, downloads_count: 1)
    Stat.instance.increment!(:total_downloads, file_count)
  end

  # todo: Implement title for folder
  def zip_filename
    "#{(@koppurai.title.presence || "DropShare").gsub(/[^\w\-]/, "_")}.zip"
  end
end
