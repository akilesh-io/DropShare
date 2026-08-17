class Koppurai < ApplicationRecord
  has_many :koppus, dependent: :destroy

  before_create :generate_share_key
  validates :expires_at, presence: true

  def expired?
    expires_at < Time.current
  end

  private

  def generate_share_key
    self.share_key = SecureRandom.urlsafe_base64(4)
    self.downloads_count ||= 0
    self.total_size ||= 0
  end
end
