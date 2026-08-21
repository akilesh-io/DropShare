require "fileutils"

# An upload in flight: how many bytes we hold, how many we expect, what the client told us
# about the file, and -- once it's whole -- the Active Storage blob it became.
#
# Each upload owns three files under Tus.storage_path, sharded by the first four characters
# of its ID the way Active Storage shards blob keys:
#
#   storage/tus/ab/cd/abcd...        the bytes received so far
#   storage/tus/ab/cd/abcd....info   this record, as JSON
#   storage/tus/ab/cd/abcd....lock   held while a request appends, so two can't interleave
#
# The ID doubles as the upload's URL, so whoever created it is the only one who can resume
# or delete it. It is also the only thing ever joined onto the storage path, and path_for
# checks it before it is.
class Tus::Upload
  ID_LENGTH = 32
  ID_FORMAT = /\A[a-z0-9]{#{ID_LENGTH}}\z/
  BUFFER_SIZE = 5.megabytes

  FILENAME_KEYS = %w[ filename name ].freeze
  CONTENT_TYPE_KEYS = %w[ filetype content_type type ].freeze
  CONTENT_TYPE_FORMAT = %r{\A[-\w.+]+/[-\w.+]+\z}

  attr_reader :id, :metadata, :created_at
  attr_accessor :offset, :length, :expires_at, :blob_id

  class << self
    def create(length:, metadata: {})
      upload = new(id: SecureRandom.base36(ID_LENGTH), length: length, metadata: metadata, expires_at: Tus.expires_at)

      FileUtils.mkdir_p File.dirname(upload.info_path)
      FileUtils.touch [ upload.data_path, upload.lock_path ]

      upload.save
    end

    def find(id)
      return nil unless valid_id?(id)

      attributes = JSON.parse(File.read(path_for(id, ".info"))).symbolize_keys

      new(**attributes.slice(:id, :length, :offset, :metadata, :blob_id),
        created_at: time(attributes[:created_at]), expires_at: time(attributes[:expires_at]))
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end

    def all
      Dir.glob(File.join(root, "*", "*", "*.info")).filter_map { |path| find File.basename(path, ".info") }
    end

    def expired = all.select(&:expired?)

    def root = Tus.storage_path.to_s

    def valid_id?(id) = id.to_s.match?(ID_FORMAT)

    def path_for(id, suffix)
      raise Tus::NotFound, "Invalid upload ID #{id.inspect}" unless valid_id?(id)

      File.join(root, id[0, 2], id[2, 2], "#{id}#{suffix}")
    end

    private
      def time(value)
        Time.iso8601(value).utc if value.present?
      end
  end

  def initialize(id:, length:, offset: 0, metadata: {}, created_at: nil, expires_at: nil, blob_id: nil)
    @id = id
    @length = length
    @offset = offset
    @metadata = metadata || {}
    @created_at = created_at || Time.now.utc
    @expires_at = expires_at
    @blob_id = blob_id
  end

  def complete? = offset >= length
  def expired? = expires_at.present? && expires_at < Time.now.utc
  def finalized? = blob_id.present?

  def data_path = self.class.path_for(id, "")
  def info_path = self.class.path_for(id, ".info")
  def lock_path = self.class.path_for(id, ".lock")

  # Appends io at offset and returns the upload as it now stands. The offset is checked
  # while the lock is held, so two requests can't both think they're writing at the end.
  def write(io, offset:, checksum: nil)
    with_lock do
      current = self.class.find(id) or raise Tus::NotFound, "Upload #{id} is gone"

      raise Tus::Expired, "Upload #{id} has expired" if current.expired?
      raise Tus::OffsetMismatch, "Expected offset #{current.offset}, got #{offset}" unless current.offset == offset
      raise Tus::BadRequest, "Upload #{id} is already complete" if current.complete?

      current.offset += current.append(io, checksum: checksum)
      current.expires_at = Tus.expires_at
      current.save
    end
  end

  # Hands the staged file to Active Storage. Running it twice returns the same blob rather
  # than storing the file again.
  def finalize!
    return blob if finalized?

    @blob = movable? ? move_into_storage : upload_into_storage
    self.blob_id = @blob.id
    save

    @blob
  end

  def save
    temporary_path = "#{info_path}.#{SecureRandom.hex(8)}.tmp"

    File.binwrite temporary_path, JSON.generate(as_json)
    File.rename temporary_path, info_path

    self
  end

  def delete
    FileUtils.rm_f [ data_path, info_path, lock_path ]
  end

  def open(&block)
    File.open(data_path, "rb", &block)
  rescue Errno::ENOENT
    raise Tus::NotFound, "Upload #{id} has no staged data"
  end

  def blob
    @blob ||= ActiveStorage::Blob.find_by(id: blob_id) if blob_id
  end

  # Falls back, so a client that sends no metadata still ends up with a usable blob.
  def filename
    metadata.values_at(*FILENAME_KEYS).compact_blank.first || "file"
  end

  # nil when the client didn't say, or said something that isn't a media type, in which case
  # Active Storage works it out from the file itself.
  def content_type
    type = metadata.values_at(*CONTENT_TYPE_KEYS).compact_blank.first
    type if type&.match?(CONTENT_TYPE_FORMAT)
  end

  def as_json(*)
    { id: id, length: length, offset: offset, metadata: metadata, blob_id: blob_id,
      created_at: created_at.utc.iso8601, expires_at: expires_at&.utc&.iso8601 }
  end

  protected
    # Writes the body out at the current offset and returns how many bytes landed. A chunk
    # that overruns the length, or fails its checksum, is rolled back whole: the file goes
    # back to where this request found it and the offset doesn't move.
    def append(io, checksum: nil)
      written = 0

      File.open(data_path, File::WRONLY, binmode: true) do |file|
        file.truncate offset # drop anything an interrupted request left past the agreed offset
        file.seek offset

        each_chunk(io) do |chunk|
          raise Tus::TooLarge, "Upload #{id} would exceed its length of #{length}" if offset + written + chunk.bytesize > length

          file.write chunk
          checksum&.update chunk
          written += chunk.bytesize
        end

        file.flush
      end

      checksum&.verify!

      written
    rescue Errno::ENOENT
      raise Tus::NotFound, "Upload #{id} has no staged data"
    rescue Tus::Error
      rollback
      raise
    end

  private
    def movable?
      ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::DiskService)
    end

    # The disk service keeps its files on the volume the chunks were staged on, so the
    # finished upload is moved into the blob's place rather than streamed into it: one pass
    # to checksum it and a rename, instead of a read and a write whose cost grows with the
    # file. For a few gigabytes that is the difference between seconds and minutes, and the
    # request has to answer before the proxy in front of it gives up.
    def move_into_storage
      blob = ActiveStorage::Blob.create_before_direct_upload!(
        filename: filename, byte_size: length, checksum: staged_checksum, content_type: content_type)

      destination = blob.service.path_for(blob.key)
      FileUtils.mkdir_p File.dirname(destination)
      FileUtils.mv data_path, destination

      # Sniffing the first bytes only works once the file is in place, and is only wanted
      # when the client didn't tell us the type -- the way identify: false means below.
      content_type.present? ? blob.update!(identified: true) : blob.identify

      blob
    end

    # Every other service has to be handed the bytes.
    def upload_into_storage
      blob = open do |file|
        ActiveStorage::Blob.create_and_upload! io: file, filename: filename, content_type: content_type,
          identify: content_type.blank?
      end

      FileUtils.rm_f data_path
      blob
    end

    # The MD5 Active Storage stores for a blob, computed the way it computes it.
    def staged_checksum
      digest = OpenSSL::Digest::MD5.new
      buffer = "".b

      open do |file|
        while chunk = file.read(BUFFER_SIZE, buffer)
          digest << chunk
        end
      end

      digest.base64digest
    end

    # Stops at the first failed read: a connection that drops mid-chunk still leaves behind
    # the bytes that did arrive, which is the entire point of the protocol.
    def each_chunk(io)
      buffer = "".b

      while chunk = read_chunk(io, buffer)
        yield chunk
      end
    end

    def read_chunk(io, buffer)
      io.read BUFFER_SIZE, buffer
    rescue IOError, SystemCallError
      nil
    end

    def rollback
      File.truncate data_path, offset
    rescue Errno::ENOENT
      # Already gone
    end

    def with_lock
      File.open(lock_path, File::RDWR | File::CREAT, 0600) do |lock|
        raise Tus::Locked, "Another request is writing to upload #{id}" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        yield # closing the file releases the lock
      end
    rescue Errno::ENOENT
      raise Tus::NotFound, "Upload #{id} is gone"
    end
end
