# Server side of the tus resumable upload protocol, version 1.0.0: https://tus.io
#
# A direct upload sends a whole file in one request, so a connection that drops at 90%
# starts again at 0%. Here a client creates an upload (POST), sends it a chunk at a time
# (PATCH), and asks how many bytes we hold whenever it needs to pick up again (HEAD).
#
# Chunks are staged under Tus.storage_path while the upload is in flight. When the last one
# arrives the file becomes an Active Storage blob, and its signed ID comes back in the
# Active-Storage-Signed-Id response header, which is what DropController#create takes.
#
# Served by TusUploadsController at /tus. Uploaded by app/javascript/components/tus_upload.js.
module Tus
  PROTOCOL_VERSION = "1.0.0"
  CONTENT_TYPE = "application/offset+octet-stream"
  SIGNED_ID_HEADER = "Active-Storage-Signed-Id"

  # Advertised in Tus-Extension. Concatenation and deferred lengths are part of the protocol
  # too, but nothing here uploads that way.
  EXTENSIONS = %w[ creation expiration checksum termination ].freeze

  # All three are configured in config/initializers/tus.rb.
  mattr_accessor :storage_path
  mattr_accessor :max_size
  mattr_accessor :uploads_expire_in, default: 1.day

  # Each error carries the status the protocol prescribes for it, which is the one
  # TusUploadsController answers with.
  class Error < StandardError
    class_attribute :status, default: :bad_request
  end

  class BadRequest           < Error; end
  class NotFound             < Error; self.status = :not_found;              end
  class Expired              < Error; self.status = :gone;                   end
  class Locked               < Error; self.status = :conflict;               end
  class OffsetMismatch       < Error; self.status = :conflict;               end
  class UnsupportedMediaType < Error; self.status = :unsupported_media_type; end
  class TooLarge             < Error; self.status = 413;                     end
  class ChecksumMismatch     < Error; self.status = 460;                     end

  def self.expires_at
    uploads_expire_in&.from_now&.utc
  end

  # Sweeps up the uploads nobody came back to finish, and returns how many went. Scheduled
  # in config/recurring.yml.
  def self.purge_expired
    Upload.expired.each(&:delete).size
  end
end
