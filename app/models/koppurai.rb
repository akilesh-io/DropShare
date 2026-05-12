class Koppurai < ApplicationRecord
  has_many :koppus, dependent: :destroy
end
