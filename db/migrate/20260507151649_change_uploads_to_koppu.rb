class ChangeUploadsToKoppu < ActiveRecord::Migration[8.1]
  def change
    rename_table :uploads, :koppukal
  end
end
