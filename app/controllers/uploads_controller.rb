class UploadsController < ApplicationController
  before_action :set_session

  def index
    @uploads = Upload.with_attached_file.where(session_id: session[:user_id]).order(created_at: :desc)

    @stats = Stat.instance
  end

  def new
  end

  def create
    return render json: { error: "No file" }, status: 400 unless params[:blob_signed_id]
    
    upload = Upload.new(
      expires_at: Rails.configuration.FILE_EXPIRY_DAYS.days.from_now,
      session_id: session[:user_id]
    )

    upload.file.attach(params[:blob_signed_id])

    if upload.save
      file_size = upload.file.blob.byte_size

      stats = Stat.instance
      stats.increment!(:current_uploads)
      stats.increment!(:lifetime_uploads)
      stats.update!(
        current_size: stats.current_size + file_size,
        lifetime_size: stats.lifetime_size + file_size
      )

      render json: {
        link: file_url(upload.token),
        id: upload.id
      }
    else
      render json: { error: "Upload failed" }, status: 422
    end
  end

  def show
    upload = Upload.find_by!(token: params[:token])
    return render plain: "Expired", status: 410 if upload.expired?

    upload.increment!(:downloads)
    Stat.instance.increment!(:total_downloads)

    redirect_to rails_blob_url(upload.file, disposition: "attachment")
  end

  private

  def set_session
    session[:user_id] ||= SecureRandom.uuid
  end

  def file_url(token)
    "#{request.base_url}/f/#{token}"
  end
end
