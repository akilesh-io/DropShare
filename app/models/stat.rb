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

  def estimated_co2_grams
    gb_transferred = self.lifetime_size.to_f / 1.gigabyte

    energy_intensity = 0.06
    carbon_intensity = 442

    gb_transferred * energy_intensity * carbon_intensity
  end

  def estimated_co2_kg
    (estimated_co2_grams / 1000.0).round(2)
  end
end
