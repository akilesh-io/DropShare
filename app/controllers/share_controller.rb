class ShareController < ApplicationController
  before_action :set_koppurai, only: [:index]
  before_action :ensure_not_expired, only: [:index]

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
  end

  private

  def set_koppurai
    @koppurai = Koppurai
      .includes(koppus: [koppu_attachment: :blob])
      .find_by(share_key: params[:share_key])
    render plain: "Page not found or link expired", status: :not_found if @koppurai.nil?
  end

  def ensure_not_expired
    render plain: "Expired", status: :gone if @koppurai&.expired?
  end
end
