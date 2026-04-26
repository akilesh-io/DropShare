class Stat < ApplicationRecord
  def self.instance
    first_or_create!(
      current_uploads: 0,
      current_size: 0,
      total_downloads: 0,
      lifetime_uploads: 0,
      lifetime_size: 0
    )
  end
end
