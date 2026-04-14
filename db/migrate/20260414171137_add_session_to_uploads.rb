class AddSessionToUploads < ActiveRecord::Migration[8.1]
  def change
    add_column :uploads, :session_id, :string
  end
end
