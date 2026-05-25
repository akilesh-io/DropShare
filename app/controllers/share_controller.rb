class ShareController < ApplicationController
  before_action :file_exist, only: [:index]
  # def index
  #   @koppukal = Koppu
  #     .with_attached_koppu
  #     .joins(:koppurai)
  #     .where(koppurais: { share_key: params[:share_key] })
  #     .order(created_at: :desc)
  # end

  def index
    @koppurai = Koppurai.find_by!(
      share_key: params[:share_key]
    )

    @koppukal = @koppurai
      .koppus
      .with_attached_koppu
      .order(created_at: :desc)
  end

  def download_koppu
    koppu = Koppu.find_by!(share_key: params[:share_key])
    return render plain: "Expired", status: 410 if koppu.koppurai.expired?

    koppu.increment!(:downloads_count)
    Stat.instance.increment!(:total_downloads)

    redirect_to rails_blob_url(koppu.koppu, disposition: "attachment")
  end

  def download_koppurai
    render plain: "ZIP download coming soon"
  end

  private
  def file_exist
    @koppurai = Koppurai.find_by(
      share_key: params[:share_key]
    )

    render plain: "Page not found or link expired" if @koppurai.nil?
    # redirect_to root_path, alert: "Page not found or link expired" if @koppurai.nil?
  end
end
