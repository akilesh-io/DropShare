class AddPathToUploads < ActiveRecord::Migration[8.1]
  def change
    add_column :uploads, :path, :string
  end
end
