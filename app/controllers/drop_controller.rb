class DropController < ApplicationController
  before_action :set_session

  def index
    @koppurai = Koppurai
      .includes(koppus: [koppu_attachment: :blob])
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

      # render json: {
      #   link: share_url(koppukal.share_key),
      #   id: koppukal.id
      # }
      render partial: "components/file_item", locals: { koppu: koppukal }, layout: false
    else
      render json: { error: "Upload failed" }, status: 422
    end
  end

  def destroy_koppurai
    koppurai = Koppurai.find(params[:id])
    return head :forbidden unless koppurai.session_id == session[:user_id]

    koppurai.koppus.each do |koppu|
      koppu.koppu.purge
    end
    koppurai.destroy

    redirect_to root_path, notice: "Folder deleted"
  end

  def destroy_koppu
    koppu = Koppu.find(params[:id])
    return head :forbidden unless koppu.koppurai.session_id == session[:user_id]
    
    koppu.koppu.purge
    koppu.destroy

    redirect_to root_path, notice: "File deleted"
  end

  private

  def set_session
    session[:user_id] ||= SecureRandom.uuid
  end
end
