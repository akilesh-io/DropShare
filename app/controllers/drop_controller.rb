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

    render partial: "components/folder", formats: [:html], locals: { koppurai: koppurai, is_owner: true }, layout: false
  end

  def create
    return render json: { error: "No file" }, status: :bad_request unless params[:blob_signed_id]

    koppurai = Koppurai.find_by!(id: params[:koppurai_id], session_id: session[:user_id])
    blob = ActiveStorage::Blob.find_signed!(params[:blob_signed_id])

    koppu = koppurai.koppus.new(
      byte_size: blob.byte_size,
      content_type: blob.content_type,
      checksum: blob.checksum
    )
    koppu.koppu.attach(blob)

    if koppu.save
      render partial: "components/file_item", formats: [:html], locals: { koppu: koppu, is_owner: true }, layout: false
    else
      render json: { error: koppu.errors.full_messages.to_sentence.presence || "Upload failed" }, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature
    render json: { error: "Upload failed" }, status: :not_found
  end

  def destroy_koppurai
    koppurai = Koppurai.find(params[:id])
    return head :forbidden unless koppurai.session_id == session[:user_id]

    koppurai.destroy

    redirect_to root_path, notice: "Folder deleted"
  end

  def destroy_koppu
    koppu = Koppu.find(params[:id])
    return head :forbidden unless koppu.koppurai.session_id == session[:user_id]

    koppu.destroy

    redirect_to root_path, notice: "File deleted"
  end

  private

  def set_session
    session[:user_id] ||= SecureRandom.uuid
  end
end
