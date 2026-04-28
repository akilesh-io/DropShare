class ShareController < ApplicationController
  def index
    @uploads = Upload.with_attached_file.where(token: params[:token]).order(created_at: :desc)
  end

  def download
    upload = Upload.find_by!(token: params[:token])
    return render plain: "Expired", status: 410 if upload.expired?

    upload.increment!(:downloads)
    Stat.instance.increment!(:total_downloads)

    redirect_to rails_blob_url(upload.file, disposition: "attachment")
  end
end
