class CleanupUploadJob < ApplicationJob
  queue_as :default

  def perform(*args)
    upload = Upload.find_by(id: id)
    return unless upload

    size = upload.file.blob.byte_size
    stats = Stat.instance
    stats.update!(
      current_uploads: stats.current_uploads - 1,
      current_size: stats.current_size - size
    )

    upload.file.purge if upload.file.attached?
    upload.destroy
  end
end
