class DropController < ApplicationController
  before_action :set_session

  def index
    @koppurai = Koppurai
      .includes(koppus: [koppu_attachment: :blob])
      .joins(koppus: :koppu_attachment)
      .where(session_id: session[:user_id])
      .order(created_at: :desc)
    @stats = Stat.instance
  end

  def new
  end

  def create
    return render json: { error: "No file" }, status: 400 unless params[:blob_signed_id]

    blob = ActiveStorage::Blob.find_signed!(params[:blob_signed_id])
    koppurai = Koppurai.create!(
      expires_at: Rails.configuration.FILE_EXPIRY_DAYS.days.from_now,
      session_id: session[:user_id]
    )
    koppukal = koppurai.koppus.new(
      byte_size: blob.byte_size,
      content_type: blob.content_type,
      checksum: blob.checksum
    )
    koppukal.koppu.attach(blob)

    if koppukal.save
      # koppurai.update!(
      #   files_count: koppurai.koppus.count,
      #   total_size: koppurai.koppus.sum(:byte_size)
      # )

      # koppurai.increment!(:files_count)
      koppurai.increment!(:total_size, blob.byte_size)

      file_size = koppukal.koppu.blob.byte_size

      stats = Stat.instance
      stats.increment!(:current_uploads)
      stats.increment!(:lifetime_uploads)
      stats.update!(
        current_size: stats.current_size + file_size,
        lifetime_size: stats.lifetime_size + file_size
      )

      render json: {
        link: share_url(koppukal.share_key),
        id: koppukal.id
      }
    else
      render json: { error: "Upload failed" }, status: 422
    end
  end

  private

  def set_session
    session[:user_id] ||= SecureRandom.uuid
  end
end
