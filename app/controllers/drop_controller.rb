class DropController < ApplicationController
  before_action :set_session

  def index
    @koppurai = Koppurai
      .includes(koppus: [koppu_attachment: :blob])
      # .joins(koppus: :koppu_attachment)
      .where(session_id: session[:user_id])
      .order(created_at: :desc)
    @stats = Stat.instance
  end

  def new
    koppurai = Koppurai.create!(
      expires_at: Rails.configuration.FILE_EXPIRY_DAYS.days.from_now,
      session_id: session[:user_id]
    )

    render json: {
      id: koppurai.id,
      share_key: koppurai.share_key,
      url: share_url(koppurai.share_key)
    }
  end

  def create
    return render json: { error: "No file" }, status: 400 unless params[:blob_signed_id]

    koppurai = Koppurai.find(params[:koppurai_id])
    blob = ActiveStorage::Blob.find_signed!(params[:blob_signed_id])
    koppukal = koppurai.koppus.new(
      byte_size: blob.byte_size,
      content_type: blob.content_type,
      checksum: blob.checksum
    )
    koppukal.koppu.attach(blob)

    if koppukal.save
      koppurai.increment!(:total_size, blob.byte_size)
      stats = Stat.instance
      stats.increment!(:current_uploads)
      stats.increment!(:lifetime_uploads)
      stats.update!(
        current_size: stats.current_size + blob.byte_size,
        lifetime_size: stats.lifetime_size + blob.byte_size
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
