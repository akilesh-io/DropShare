class HardenKoppuraiAndKoppuSchema < ActiveRecord::Migration[8.1]
  def change
    remove_column :koppurais, :password_digest, :string
    remove_column :koppus, :path, :string

    change_column_null :koppurais, :share_key, false
    change_column_null :koppus, :share_key, false

    change_column :koppurais, :total_size, :bigint
    change_column :koppus, :byte_size, :bigint
    change_column :stats, :current_size, :bigint
    change_column :stats, :lifetime_size, :bigint

    remove_index :koppurais, :share_key
    remove_index :koppus, :share_key
    add_index :koppurais, :share_key, unique: true
    add_index :koppus, :share_key, unique: true
  end
end
