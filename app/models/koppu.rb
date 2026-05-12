class Koppu < ApplicationRecord
  belongs_to :koppurai

  has_one_attached :koppu
  before_create :generate_share_key
  validates :koppu, presence: true

  private

  def generate_share_key
    self.share_key = SecureRandom.urlsafe_base64(10)
    self.downloads_count ||= 0
  end
end
