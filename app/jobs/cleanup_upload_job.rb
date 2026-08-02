class CleanupUploadJob < ApplicationJob
  queue_as :default

  def perform(id)
    Rails.logger.info("DEBUG :: id #{id}")
    upload = Koppu.find_by(id: id)
    Rails.logger.info("DEBUG :: #{upload} :: #{id}")
    return unless upload

    size = upload.koppu.blob.byte_size

    upload.koppu.purge if upload.koppu.attached?
    upload.destroy
  end
end

