require "test_helper"

# Upload-Metadata is the one part of the protocol where a client sends us free text, and
# the value comes back out in a response header, so what it may contain is the point.
class Tus::MetadataTest < ActiveSupport::TestCase
  test "decoding what a client sent about its file" do
    header = "filename #{encode64("holiday.mp4")},filetype #{encode64("video/mp4")}"

    assert_equal({ "filename" => "holiday.mp4", "filetype" => "video/mp4" }, Tus::Metadata.decode(header))
  end

  test "decoding a header that isn't there" do
    assert_equal({}, Tus::Metadata.decode(nil))
    assert_equal({}, Tus::Metadata.decode(""))
  end

  test "a key on its own stands for a value of nothing" do
    assert_equal({ "is_confidential" => "" }, Tus::Metadata.decode("is_confidential"))
  end

  test "the spaces a client left around a pair don't matter" do
    assert_equal({ "filename" => "a.txt" }, Tus::Metadata.decode("  filename #{encode64("a.txt")}  "))
  end

  test "refusing a key that isn't a key" do
    assert_raises(Tus::BadRequest) { Tus::Metadata.decode("not!a!key #{encode64("a.txt")}") }
    assert_raises(Tus::BadRequest) { Tus::Metadata.decode("filename #{encode64("a.txt")},,filetype #{encode64("text/plain")}") }
  end

  test "refusing a value that isn't Base64" do
    assert_raises(Tus::BadRequest) { Tus::Metadata.decode("filename not-base64!") }
  end

  test "a value can't smuggle a header of its own" do
    metadata = Tus::Metadata.decode("filename #{encode64("a.txt\r\nX-Injected: yes")}")

    assert_equal "a.txtX-Injected: yes", metadata["filename"]
    assert_no_match %r{[\r\n]}, metadata["filename"]
  end

  test "bytes that aren't text are replaced rather than passed on" do
    metadata = Tus::Metadata.decode("filename #{encode64("caf\xFF.txt".b)}")

    assert_equal Encoding::UTF_8, metadata["filename"].encoding
    assert metadata["filename"].valid_encoding?
  end

  test "a value longer than a header should be is cut short" do
    metadata = Tus::Metadata.decode("filename #{encode64("a" * 2000)}")

    assert_equal Tus::Metadata::MAX_VALUE_LENGTH, metadata["filename"].bytesize
  end

  test "encoding what we hold about a file" do
    assert_equal "filename #{encode64("a.txt")}", Tus::Metadata.encode("filename" => "a.txt")
  end

  test "encoding a value of nothing leaves the key on its own" do
    assert_equal "is_confidential", Tus::Metadata.encode("is_confidential" => "")
  end

  test "what we encode is what a client can decode" do
    metadata = { "filename" => "holiday.mp4", "filetype" => "video/mp4" }

    assert_equal metadata, Tus::Metadata.decode(Tus::Metadata.encode(metadata))
  end

  private
    def encode64(value) = Base64.strict_encode64(value)
end
