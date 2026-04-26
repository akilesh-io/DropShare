class CreateStats < ActiveRecord::Migration[8.1]
  def change
    create_table :stats do |t|
      t.integer :current_uploads
      t.integer :current_size
      t.integer :total_downloads
      t.integer :lifetime_uploads
      t.integer :lifetime_size

      t.timestamps
    end
  end
end
