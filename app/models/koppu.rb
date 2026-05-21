class Koppu < ApplicationRecord
  belongs_to :koppurai

  has_one_attached :koppu
  before_create :generate_share_key
  validates :koppu, presence: true

  after_create :increase_stats
  after_destroy :decrease_stats

  private

  def increase_stats
    Stat.add_upload(byte_size: byte_size)
  end

  def decrease_stats
    Stat.remove_upload(byte_size: byte_size)
  end

  def generate_share_key
    self.share_key = SecureRandom.urlsafe_base64(10)
    self.downloads_count ||= 0
  end
end
