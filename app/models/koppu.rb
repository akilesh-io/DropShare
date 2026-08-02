class Koppu < ApplicationRecord
  MAX_BYTE_SIZE = 5.gigabytes
  MAX_PER_KOPPURAI = 100

  belongs_to :koppurai

  has_one_attached :koppu
  before_create :generate_share_key
  validates :koppu, presence: true
  validates :byte_size, numericality: { less_than: MAX_BYTE_SIZE }
  validate :koppurai_not_at_capacity, on: :create

  after_create :increase_stats
  after_destroy :decrease_stats

  private

  def koppurai_not_at_capacity
    return unless koppurai
    return if koppurai.koppus.count < MAX_PER_KOPPURAI

    errors.add(:base, "Folder is full (max #{MAX_PER_KOPPURAI} files)")
  end

  def increase_stats
    Stat.add_upload(byte_size: byte_size)
    Koppurai.update_counters(koppurai_id, total_size: byte_size)
  end

  def decrease_stats
    Stat.remove_upload(byte_size: byte_size)
    Koppurai.update_counters(koppurai_id, total_size: -byte_size)
  end

  def generate_share_key
    self.share_key = SecureRandom.urlsafe_base64(10)
    self.downloads_count ||= 0
  end
end
