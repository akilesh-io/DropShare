class Upload < ApplicationRecord
  has_one_attached :file

  before_create :generate_token
  after_create :schedule_cleanup

  validates :file, presence: true

  def generate_token
    self.token = SecureRandom.urlsafe_base64(10)
    self.downloads ||= 0
  end

  def expired?
    expires_at && expires_at < Time.current
  end

  private

  def schedule_cleanup
    CleanupUploadJob.set(wait_until: expires_at).perform_later(id)
  end
end
