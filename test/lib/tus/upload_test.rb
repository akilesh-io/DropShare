require "test_helper"

# An upload in flight, staged on disk. Everything here is about what happens between the
# first byte and the last: where the bytes are kept, what happens to a chunk that doesn't
# fit or doesn't match, and what is left behind when nobody comes back to finish.
class Tus::UploadTest < ActiveSupport::TestCase
  setup do
    @storage_path = Tus.storage_path
    Tus.storage_path = Dir.mktmpdir
  end

  teardown do
    FileUtils.rm_rf Tus.storage_path
    Tus.storage_path = @storage_path
  end

  test "creating an upload stages the three files it needs" do
    upload = Tus::Upload.create length: 11

    assert File.exist?(upload.data_path), "the bytes received so far"
    assert File.exist?(upload.info_path), "the record of the upload"
    assert File.exist?(upload.lock_path), "the lock a request holds while it appends"
    assert_equal 0, File.size(upload.data_path)
  end

  test "a new upload holds nothing and expects what it was told" do
    upload = Tus::Upload.create length: 11

    assert_equal 0, upload.offset
    assert_equal 11, upload.length
    assert_not upload.complete?
    assert_not upload.finalized?
  end

  test "an upload is given an ID that can't be guessed, and expires" do
    upload = Tus::Upload.create length: 11

    assert_match Tus::Upload::ID_FORMAT, upload.id
    assert_in_delta Tus.uploads_expire_in.from_now, upload.expires_at, 5.seconds
  end

  test "uploads are spread over directories rather than piled into one" do
    upload = Tus::Upload.create length: 11
    id = upload.id

    assert_equal File.join(Tus.storage_path.to_s, id[0, 2], id[2, 2], id), upload.data_path
  end

  test "finding an upload again gives back everything it was told" do
    created = Tus::Upload.create length: 11, metadata: { "filename" => "hello.txt" }

    found = Tus::Upload.find(created.id)

    assert_equal created.id, found.id
    assert_equal 11, found.length
    assert_equal 0, found.offset
    assert_equal({ "filename" => "hello.txt" }, found.metadata)
    assert_in_delta created.expires_at, found.expires_at, 1.second
  end

  test "an upload nobody created isn't found" do
    assert_nil Tus::Upload.find("a" * Tus::Upload::ID_LENGTH)
    assert_nil Tus::Upload.find("nonsense")
    assert_nil Tus::Upload.find(nil)
  end

  test "an ID is never joined onto the storage path without being checked first" do
    assert_raises(Tus::NotFound) { Tus::Upload.path_for("../../etc/passwd", "") }
    assert_not Tus::Upload.valid_id?("../../etc/passwd")
    assert_nil Tus::Upload.find("../../etc/passwd")
  end

  test "an upload whose record was left half written isn't found" do
    upload = Tus::Upload.create length: 11
    File.binwrite upload.info_path, "{ not json"

    assert_nil Tus::Upload.find(upload.id)
  end

  test "sending the bytes of a file, a chunk at a time" do
    upload = Tus::Upload.create length: 11

    upload = upload.write StringIO.new("hello"), offset: 0
    assert_equal 5, upload.offset
    assert_not upload.complete?

    upload = upload.write StringIO.new(" world"), offset: 5
    assert_equal 11, upload.offset
    assert upload.complete?

    assert_equal "hello world", File.binread(upload.data_path)
  end

  test "how much we hold is remembered between requests" do
    upload = Tus::Upload.create length: 11
    upload.write StringIO.new("hello"), offset: 0

    assert_equal 5, Tus::Upload.find(upload.id).offset
  end

  test "sending a chunk buys the upload more time" do
    upload = Tus::Upload.create length: 11
    upload.expires_at = 1.minute.from_now
    upload.save

    upload = upload.write StringIO.new("hello"), offset: 0

    assert_in_delta Tus.uploads_expire_in.from_now, upload.expires_at, 5.seconds
  end

  test "refusing a chunk sent to anywhere but the end of what we hold" do
    upload = Tus::Upload.create length: 11
    upload.write StringIO.new("hello"), offset: 0

    assert_raises(Tus::OffsetMismatch) { upload.write StringIO.new("!"), offset: 0 }
    assert_raises(Tus::OffsetMismatch) { upload.write StringIO.new("!"), offset: 9 }
    assert_equal 5, Tus::Upload.find(upload.id).offset
  end

  test "a chunk that would overrun the file is thrown away whole" do
    upload = Tus::Upload.create length: 5

    assert_raises(Tus::TooLarge) { upload.write StringIO.new("hello world"), offset: 0 }

    assert_equal 0, Tus::Upload.find(upload.id).offset
    assert_equal 0, File.size(upload.data_path), "the partial chunk is rolled back, not left behind"
  end

  test "a chunk that arrived corrupted is thrown away whole" do
    upload = Tus::Upload.create length: 11
    checksum = Tus::Checksum.parse "sha256 #{OpenSSL::Digest::SHA256.base64digest("hello mars")}"

    assert_raises(Tus::ChecksumMismatch) { upload.write StringIO.new("hello world"), offset: 0, checksum: checksum }

    assert_equal 0, Tus::Upload.find(upload.id).offset
    assert_equal 0, File.size(upload.data_path), "so the client can send the chunk again"
  end

  test "a chunk that arrived intact is kept" do
    upload = Tus::Upload.create length: 11
    checksum = Tus::Checksum.parse "sha256 #{OpenSSL::Digest::SHA256.base64digest("hello world")}"

    upload = upload.write StringIO.new("hello world"), offset: 0, checksum: checksum

    assert_equal 11, upload.offset
  end

  test "refusing anything more once we hold the whole file" do
    upload = Tus::Upload.create length: 5
    upload = upload.write StringIO.new("hello"), offset: 0

    assert_raises(Tus::BadRequest) { upload.write StringIO.new("!"), offset: 5 }
  end

  test "refusing a chunk for an upload that has expired" do
    upload = Tus::Upload.create length: 11
    upload.expires_at = 1.hour.ago
    upload.save

    assert upload.expired?
    assert_raises(Tus::Expired) { upload.write StringIO.new("hello"), offset: 0 }
  end

  test "refusing a chunk for an upload that is gone" do
    upload = Tus::Upload.create length: 11
    upload.delete

    assert_raises(Tus::NotFound) { upload.write StringIO.new("hello"), offset: 0 }
  end

  test "two requests can't append to the same upload at once" do
    upload = Tus::Upload.create length: 11

    File.open upload.lock_path, File::RDWR | File::CREAT do |lock|
      lock.flock File::LOCK_EX

      assert_raises(Tus::Locked) { upload.write StringIO.new("hello"), offset: 0 }
    end

    assert_equal 5, upload.write(StringIO.new("hello"), offset: 0).offset, "and once the lock is free it goes through"
  end

  test "a finished upload becomes a blob" do
    upload = Tus::Upload.create length: 11, metadata: { "filename" => "hello.txt", "filetype" => "text/plain" }
    upload = upload.write StringIO.new("hello world"), offset: 0

    blob = upload.finalize!

    assert upload.finalized?
    assert_equal "hello world", blob.download
    assert_equal "hello.txt", blob.filename.to_s
    assert_equal "text/plain", blob.content_type
    assert_equal 11, blob.byte_size
  end

  test "the staged bytes are dropped once Active Storage has them" do
    upload = Tus::Upload.create length: 5
    upload = upload.write StringIO.new("hello"), offset: 0

    upload.finalize!

    assert_not File.exist?(upload.data_path), "the same bytes are not kept in two places"
  end

  test "finishing an upload twice stores the file once" do
    upload = Tus::Upload.create length: 5
    upload = upload.write StringIO.new("hello"), offset: 0

    blob = upload.finalize!

    assert_no_difference -> { ActiveStorage::Blob.count } do
      assert_equal blob, upload.finalize!
    end
  end

  test "an upload picked up again knows the blob it already became" do
    upload = Tus::Upload.create length: 5
    upload = upload.write StringIO.new("hello"), offset: 0
    blob = upload.finalize!

    assert_equal blob, Tus::Upload.find(upload.id).blob
  end

  test "a file the client never named is still stored" do
    upload = Tus::Upload.create length: 5
    upload = upload.write StringIO.new("hello"), offset: 0

    blob = upload.finalize!

    assert_equal "file", blob.filename.to_s
    assert_equal "application/octet-stream", blob.content_type,
      "nothing was said about the type and an unnamed file gives nothing away"
  end

  test "the client can name the file in any of the ways clients do" do
    assert_equal "a.txt", upload_with(metadata: { "filename" => "a.txt" }).filename
    assert_equal "b.txt", upload_with(metadata: { "name" => "b.txt" }).filename
    assert_equal "a.txt", upload_with(metadata: { "filename" => "a.txt", "name" => "b.txt" }).filename
    assert_equal "file", upload_with(metadata: { "filename" => "" }).filename
  end

  test "a content type we can't use is left for Active Storage to work out" do
    assert_equal "video/mp4", upload_with(metadata: { "filetype" => "video/mp4" }).content_type
    assert_equal "video/mp4", upload_with(metadata: { "type" => "video/mp4" }).content_type
    assert_nil upload_with(metadata: { "filetype" => "not a media type" }).content_type
    assert_nil upload_with(metadata: {}).content_type
  end

  test "deleting an upload leaves nothing of it behind" do
    upload = Tus::Upload.create length: 11
    upload.write StringIO.new("hello"), offset: 0

    upload.delete

    assert_not File.exist?(upload.data_path)
    assert_not File.exist?(upload.info_path)
    assert_not File.exist?(upload.lock_path)
    assert_nil Tus::Upload.find(upload.id)
  end

  test "every upload we hold can be listed" do
    ids = 3.times.map { Tus::Upload.create(length: 11).id }

    assert_equal ids.sort, Tus::Upload.all.map(&:id).sort
  end

  test "sweeping up the uploads nobody came back to finish" do
    abandoned = expired_upload
    live = Tus::Upload.create length: 11

    assert_equal 1, Tus.purge_expired

    assert_nil Tus::Upload.find(abandoned.id)
    assert Tus::Upload.find(live.id), "an upload still in flight is not swept up"
  end

  test "a sweep with nothing to sweep up" do
    Tus::Upload.create length: 11

    assert_equal 0, Tus.purge_expired
  end

  private
    def upload_with(metadata:)
      Tus::Upload.new id: SecureRandom.base36(Tus::Upload::ID_LENGTH), length: 11, metadata: metadata
    end

    def expired_upload
      upload = Tus::Upload.create length: 11
      upload.expires_at = 1.hour.ago
      upload.save
    end
end
