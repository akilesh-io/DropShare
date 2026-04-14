class CleanupUploadJob < ApplicationJob
  queue_as :default

  def perform(*args)
    upload = Upload.find_by(id: id)
    return unless upload

    upload.file.purge if upload.file.attached?
    upload.destroy
  end
end
