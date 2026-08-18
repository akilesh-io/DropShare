# Resumable uploads, see app/lib/tus.rb
Rails.application.config.to_prepare do
  # Chunks are staged here while an upload is in flight, then handed to Active Storage and
  # deleted. Keep it on the same volume as storage/.
  Tus.storage_path = Rails.root.join(Rails.env.test? ? "tmp/storage/tus" : "storage/tus")

  # How long someone has to come back and finish an upload. Abandoned ones are staged bytes
  # nobody will ever download, so this is shorter than a shared file's own life
  # (Rails.configuration.FILE_EXPIRY_DAYS). Tus.purge_expired sweeps them up, scheduled in
  # config/recurring.yml.
  Tus.uploads_expire_in = 1.day

  # Refuse a file that could never be saved as a Koppu anyway -- before it is uploaded,
  # rather than after 5GB has crossed the wire.
  Tus.max_size = Koppu::MAX_BYTE_SIZE
end
