# Serves the tus resumable upload protocol at /tus, so that a 4GB upload over a phone
# connection picks up where it left off instead of starting over. See Tus for the shape of
# it, and https://tus.io for the protocol itself.
#
#   POST    /tus           create an upload, told how many bytes to expect
#   HEAD    /tus/:token    how many of them we hold
#   PATCH   /tus/:token    send the next ones, from a given offset
#   DELETE  /tus/:token    throw the upload away
#   OPTIONS /tus           what this server supports
#
# The last PATCH answers with the signed ID of the blob the upload became, in the
# Active-Storage-Signed-Id header, which the browser posts to DropController#create the
# same way a direct upload's signed ID was posted before.
class TusUploadsController < ApplicationController
  # Creating an upload is a form request like any other, so it keeps CSRF protection. The
  # requests that follow are addressed by an unguessable upload token, which is what
  # authorizes them.
  skip_forgery_protection only: %i[ show update destroy protocol_options ]

  before_action :set_protocol_headers
  before_action :require_supported_version, except: :protocol_options
  before_action :set_upload, only: %i[ show update destroy ]

  rescue_from Tus::Error do |error|
    logger.info "[tus] #{error.class}: #{error.message}"

    head error.status
  end

  def protocol_options
    response.headers["Tus-Version"] = Tus::PROTOCOL_VERSION
    response.headers["Tus-Extension"] = Tus::EXTENSIONS.join(",")
    response.headers["Tus-Checksum-Algorithm"] = Tus::Checksum::ALGORITHMS.join(",")
    response.headers["Tus-Max-Size"] = Tus.max_size.to_s if Tus.max_size

    head :no_content
  end

  def create
    length = required_header("Upload-Length")
    raise Tus::TooLarge, "#{length} exceeds the maximum of #{Tus.max_size}" if Tus.max_size && length > Tus.max_size

    upload = Tus::Upload.create(length: length, metadata: requested_metadata)
    upload.finalize! if upload.complete? # an empty file has nothing to send

    response.headers["Location"] = tus_upload_path(upload.id)
    write_upload_headers upload

    head :created
  end

  # HEAD, which is how a client finds out where to resume from.
  def show
    response.headers["Cache-Control"] = "no-store"
    response.headers["Upload-Length"] = @upload.length.to_s
    response.headers["Upload-Metadata"] = Tus::Metadata.encode(@upload.metadata) if @upload.metadata.present?
    write_upload_headers @upload

    head :ok
  end

  def update
    raise Tus::UnsupportedMediaType unless request.media_type == Tus::CONTENT_TYPE

    offset = required_header("Upload-Offset")
    raise Tus::OffsetMismatch, "Expected offset #{@upload.offset}, got #{offset}" unless offset == @upload.offset

    # An upload already holding every byte has nothing left to append, so a PATCH arriving
    # at the end of one is answered from where it stands. That is how an upload whose bytes
    # landed but whose blob didn't gets finished rather than refused.
    @upload = @upload.write(request.body, offset: offset, checksum: requested_checksum) unless @upload.complete?
    @upload.finalize! if @upload.complete?

    write_upload_headers @upload

    head :no_content
  end

  def destroy
    @upload.delete

    head :no_content
  end

  private
    def set_protocol_headers
      response.headers["Tus-Resumable"] = Tus::PROTOCOL_VERSION
    end

    def require_supported_version
      return if request.headers["Tus-Resumable"] == Tus::PROTOCOL_VERSION

      response.headers["Tus-Version"] = Tus::PROTOCOL_VERSION
      head :precondition_failed
    end

    def set_upload
      @upload = Tus::Upload.find(params[:token])

      raise Tus::NotFound, "No upload #{params[:token].inspect}" if @upload.nil?
      raise Tus::Expired, "Upload #{@upload.id} has expired" if @upload.expired?
    end

    def write_upload_headers(upload)
      response.headers["Upload-Offset"] = upload.offset.to_s
      response.headers["Upload-Expires"] = upload.expires_at.httpdate if upload.expires_at
      response.headers[Tus::SIGNED_ID_HEADER] = upload.blob.signed_id if upload.finalized? && upload.blob
    end

    def requested_metadata
      Tus::Metadata.decode request.headers["Upload-Metadata"]
    end

    def requested_checksum
      Tus::Checksum.parse request.headers["Upload-Checksum"]
    end

    def required_header(name)
      integer_header(name) or raise Tus::BadRequest, "#{name} is required"
    end

    def integer_header(name)
      value = request.headers[name].presence
      return nil if value.nil?

      raise Tus::BadRequest, "#{name} must be a non-negative integer" unless value.match?(/\A\d+\z/)

      value.to_i
    end
end
