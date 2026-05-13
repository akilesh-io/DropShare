class DeleteTableKoppukal < ActiveRecord::Migration[8.1]
  def change
    drop_table :koppukal
  end
end

