require "test_helper"

class TusUploadsControllerTest < ActionDispatch::IntegrationTest
  OFFSET_TYPE = "application/offset+octet-stream"

  setup do
    @storage_path = Tus.storage_path
    Tus.storage_path = Dir.mktmpdir
  end

  teardown do
    FileUtils.rm_rf Tus.storage_path
    Tus.storage_path = @storage_path
  end

  test "advertising what the server supports" do
    process :options, tus_uploads_path

    assert_response :no_content
    assert_equal "1.0.0", response.headers["Tus-Version"]
    assert_equal "1.0.0", response.headers["Tus-Resumable"]
    assert_equal "creation,expiration,checksum,termination", response.headers["Tus-Extension"]
    assert_equal Koppu::MAX_BYTE_SIZE.to_s, response.headers["Tus-Max-Size"]
  end

  test "refusing a version we don't speak" do
    post tus_uploads_path, headers: { "Tus-Resumable" => "0.2.2", "Upload-Length" => "5" }

    assert_response :precondition_failed
    assert_equal "1.0.0", response.headers["Tus-Version"]
  end

  test "refusing a request without a version" do
    post tus_uploads_path, headers: { "Upload-Length" => "5" }

    assert_response :precondition_failed
  end

  test "creating an upload" do
    post tus_uploads_path, headers: tus("Upload-Length" => "11")

    assert_response :created
    assert_match %r{\A/tus/[a-z0-9]{32}\z}, response.headers["Location"]
    assert_equal "0", response.headers["Upload-Offset"]
    assert response.headers["Upload-Expires"].present?
  end

  test "refusing an upload without a length" do
    post tus_uploads_path, headers: tus

    assert_response :bad_request
  end

  test "refusing an upload larger than a Koppu can be" do
    post tus_uploads_path, headers: tus("Upload-Length" => (Koppu::MAX_BYTE_SIZE + 1).to_s)

    assert_response 413
  end

  test "reporting how much of an upload we hold" do
    url = create_upload length: 11, metadata: { filename: "hello.txt", filetype: "text/plain" }

    head url, headers: tus

    assert_response :ok
    assert_equal "0", response.headers["Upload-Offset"]
    assert_equal "11", response.headers["Upload-Length"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal({ "filename" => "hello.txt", "filetype" => "text/plain" },
      Tus::Metadata.decode(response.headers["Upload-Metadata"]))
  end

  test "reporting an unknown or malformed upload as not found" do
    head "/tus/#{"a" * 32}", headers: tus
    assert_response :not_found

    head "/tus/nonsense", headers: tus
    assert_response :not_found
  end

  test "uploading a file in chunks" do
    url = create_upload length: 11, metadata: { filename: "hello.txt", filetype: "text/plain" }

    patch url, params: "hello", headers: tus("Upload-Offset" => "0", "Content-Type" => OFFSET_TYPE)

    assert_response :no_content
    assert_equal "5", response.headers["Upload-Offset"]
    assert_nil response.headers[Tus::SIGNED_ID_HEADER], "no blob until the last byte is in"

    patch url, params: " world", headers: tus("Upload-Offset" => "5", "Content-Type" => OFFSET_TYPE)

    assert_response :no_content
    assert_equal "11", response.headers["Upload-Offset"]

    blob = blob_from_response
    assert_equal "hello world", blob.download
    assert_equal "hello.txt", blob.filename.to_s
    assert_equal "text/plain", blob.content_type
    assert_equal 11, blob.byte_size
  end

  test "refusing a chunk sent to the wrong offset" do
    url = create_upload length: 11

    patch url, params: "hello", headers: tus("Upload-Offset" => "3", "Content-Type" => OFFSET_TYPE)

    assert_response :conflict
    assert_equal "0", offset_of(url)
  end

  test "refusing a chunk without the offset content type" do
    url = create_upload length: 11

    patch url, params: "hello", headers: tus("Upload-Offset" => "0", "Content-Type" => "text/plain")

    assert_response :unsupported_media_type
  end

  test "refusing a chunk that overruns the upload" do
    url = create_upload length: 5

    patch url, params: "hello world", headers: tus("Upload-Offset" => "0", "Content-Type" => OFFSET_TYPE)

    assert_response 413
    assert_equal "0", offset_of(url)
  end

  test "answering for an upload that is already finished" do
    url = create_upload length: 5, metadata: { filename: "hello.txt" }
    patch url, params: "hello", headers: tus("Upload-Offset" => "0", "Content-Type" => OFFSET_TYPE)
    signed_id = response.headers[Tus::SIGNED_ID_HEADER]

    head url, headers: tus

    assert_response :ok
    assert_equal "5", response.headers["Upload-Offset"]
    assert_equal signed_id, response.headers[Tus::SIGNED_ID_HEADER]
  end

  test "creating an empty file" do
    post tus_uploads_path, headers: tus("Upload-Length" => "0", "Upload-Metadata" => encode(filename: "empty.txt"))

    assert_response :created
    assert_equal 0, blob_from_response.byte_size
  end

  test "verifying the checksum of a chunk" do
    url = create_upload length: 11

    patch url, params: "hello world", headers: tus("Upload-Offset" => "0", "Content-Type" => OFFSET_TYPE,
      "Upload-Checksum" => "sha256 #{OpenSSL::Digest::SHA256.base64digest("hello world")}")

    assert_response :no_content
    assert_equal "11", response.headers["Upload-Offset"]
  end

  test "throwing away a chunk that arrived corrupted" do
    url = create_upload length: 11

    patch url, params: "hello world", headers: tus("Upload-Offset" => "0", "Content-Type" => OFFSET_TYPE,
      "Upload-Checksum" => "sha256 #{OpenSSL::Digest::SHA256.base64digest("hello mars")}")

    # 460 is the checksum extension's own status, which assert_response doesn't know.
    assert_equal 460, response.status
    assert_equal "0", offset_of(url), "the chunk is discarded so the client can send it again"
  end

  test "refusing a checksum algorithm we don't have" do
    url = create_upload length: 11

    patch url, params: "hello world", headers: tus("Upload-Offset" => "0", "Content-Type" => OFFSET_TYPE,
      "Upload-Checksum" => "crc32 #{Base64.strict_encode64("nope")}")

    assert_response :bad_request
  end

  test "terminating an upload" do
    url = create_upload length: 5

    delete url, headers: tus
    assert_response :no_content

    head url, headers: tus
    assert_response :not_found
  end

  test "reporting an expired upload as gone, and purging it" do
    url = create_upload length: 5
    upload = Tus::Upload.find(File.basename(url))
    upload.expires_at = 1.hour.ago
    upload.save

    head url, headers: tus
    assert_response :gone

    Tus.purge_expired

    head url, headers: tus
    assert_response :not_found
  end

  test "leaving unexpired uploads alone" do
    url = create_upload length: 5

    Tus.purge_expired

    head url, headers: tus
    assert_response :ok
  end

  test "uploading a file into a folder, from the first request to the last" do
    post new_drop_path, headers: { "Accept" => "text/html" }
    assert_response :success
    koppurai = Koppurai.order(:created_at).last

    url = create_upload length: 11, metadata: { filename: "hello.txt", filetype: "text/plain" }
    patch url, params: "hello", headers: tus("Upload-Offset" => "0", "Content-Type" => OFFSET_TYPE)
    patch url, params: " world", headers: tus("Upload-Offset" => "5", "Content-Type" => OFFSET_TYPE)

    assert_difference -> { koppurai.koppus.count }, 1 do
      post drop_index_path, as: :json,
        params: { blob_signed_id: response.headers[Tus::SIGNED_ID_HEADER], koppurai_id: koppurai.id }
    end

    assert_response :success

    koppu = koppurai.koppus.last
    assert_equal "hello world", koppu.koppu.download
    assert_equal "hello.txt", koppu.koppu.filename.to_s
    assert_equal 11, koppu.byte_size
    assert_equal "text/plain", koppu.content_type
  end

  private
    def tus(headers = {})
      { "Tus-Resumable" => "1.0.0" }.merge(headers)
    end

    def encode(metadata)
      Tus::Metadata.encode(metadata.transform_keys(&:to_s))
    end

    def create_upload(length:, metadata: nil)
      headers = tus("Upload-Length" => length.to_s)
      headers["Upload-Metadata"] = encode(metadata) if metadata

      post tus_uploads_path, headers: headers
      assert_response :created

      response.headers["Location"]
    end

    def offset_of(url)
      head url, headers: tus
      response.headers["Upload-Offset"]
    end

    def blob_from_response
      ActiveStorage::Blob.find_signed! response.headers[Tus::SIGNED_ID_HEADER]
    end
end
