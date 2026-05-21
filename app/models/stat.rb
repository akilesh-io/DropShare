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

  def self.add_upload(byte_size:, count: 1)
    stats = instance

    stats.update!(
      current_uploads: stats.current_uploads + count,
      lifetime_uploads: stats.lifetime_uploads + count,
      current_size: stats.current_size + byte_size,
      lifetime_size: stats.lifetime_size + byte_size
    )
  end

  def self.remove_upload(byte_size:, count: 1)
    stats = instance

    stats.update!(
      current_uploads: [
        stats.current_uploads - count,
        0
      ].max,

      current_size: [
        stats.current_size - byte_size,
        0
      ].max
    )
  end

  def estimated_co2_kg
    gb_transferred = self.lifetime_size.to_f / 1.gigabyte
    energy_intensity = 0.06
    carbon_intensity = 442

    estimated_co2_grams = gb_transferred * energy_intensity * carbon_intensity
    (estimated_co2_grams / 1000.0).round(2)
  end
end
