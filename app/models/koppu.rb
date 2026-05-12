class Koppu < ApplicationRecord
  belongs_to :koppurai
  has_one_attached :koppu
end
