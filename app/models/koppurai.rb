class Koppurai < ApplicationRecord
  has_many :koppus, dependent: :destroy

  before_create :generate_share_key
  validates :expires_at, presence: true
  # has_secure_password validations: false
  # after_create :schedule_cleanup
 
  def expired?
    expires_at < Time.current
  end
  # def expired?
  #   expires_at.present? && expires_at.past?
  # end
  private

  def generate_share_key
    self.share_key = SecureRandom.urlsafe_base64(10)
    self.downloads_count ||= 0
    self.total_size ||= 0
  end

  def schedule_cleanup
    # CleanupUploadJob.set(wait_until: expires_at).perform_later(id)
  end
end
