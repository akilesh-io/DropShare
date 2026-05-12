class CreateKoppus < ActiveRecord::Migration[8.1]
  def change
    create_table :koppus do |t|
      t.references :koppurai, null: false, foreign_key: true
      t.string :share_key
      t.string :path
      t.integer :byte_size
      t.integer :downloads_count
      t.string :content_type
      t.string :checksum

      t.timestamps
    end
    add_index :koppus, :share_key
  end
end
