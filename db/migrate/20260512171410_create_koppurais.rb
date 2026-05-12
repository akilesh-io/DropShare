class CreateKoppurais < ActiveRecord::Migration[8.1]
  def change
    create_table :koppurais do |t|
      t.string :share_key
      t.string :session_id
      t.string :title
      t.string :password_digest
      t.integer :downloads_count
      t.integer :total_size
      t.datetime :expires_at

      t.timestamps
    end
    add_index :koppurais, :share_key
    add_index :koppurais, :session_id
  end
end
