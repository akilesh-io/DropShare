class UploadsController < ApplicationController
  before_action :set_session

  def index
    @uploads = Upload.where(session_id: session[:user_id]).order(created_at: :desc)
  end

  def new; end

  def create
    return render json: { error: "No file" }, status: 400 unless params[:file]

    upload = Upload.new(
      expires_at: 2.days.from_now,
      session_id: session[:user_id]
    )

    upload.file.attach(params[:file])

    if upload.save
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
