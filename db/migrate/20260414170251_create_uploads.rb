class CreateUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :uploads do |t|
      t.string :token
      t.datetime :expires_at
      t.integer :downloads

      t.timestamps
    end
  end
end
