require "test_helper"

# The checksum extension: a chunk that arrived corrupted is thrown away so the client can
# send it again, which is only worth anything if we actually check.
class Tus::ChecksumTest < ActiveSupport::TestCase
  test "a client that didn't ask for a check gets none" do
    assert_nil Tus::Checksum.parse(nil)
    assert_nil Tus::Checksum.parse("")
  end

  test "reading the algorithm and the digest a client sent" do
    checksum = Tus::Checksum.parse("sha256 #{digest("hello world")}")

    assert_equal "sha256", checksum.algorithm
    assert_equal digest("hello world"), checksum.expected
  end

  test "the algorithm is read without regard to case" do
    assert_equal "sha256", Tus::Checksum.parse("SHA256 #{digest("hello world")}").algorithm
  end

  test "refusing an algorithm we don't have" do
    assert_raises(Tus::BadRequest) { Tus::Checksum.parse("crc32 #{digest("hello world")}") }
    assert_raises(Tus::BadRequest) { Tus::Checksum.parse("#{digest("hello world")}") }
  end

  test "an algorithm sent without a digest can never match" do
    checksum = Tus::Checksum.parse("sha256")

    assert_equal "", checksum.expected
    assert_raises(Tus::ChecksumMismatch) { checksum.update("hello world").verify! }
  end

  test "every algorithm we advertise verifies a body it matches" do
    Tus::Checksum::ALGORITHMS.each do |algorithm|
      expected = OpenSSL::Digest.new(algorithm).base64digest("hello world")
      checksum = Tus::Checksum.parse("#{algorithm} #{expected}")

      assert checksum.update("hello world").verify!, "#{algorithm} should verify its own digest"
    end
  end

  test "a body that arrives in pieces is checked as a whole" do
    checksum = Tus::Checksum.parse("sha256 #{digest("hello world")}")

    checksum.update("hello").update(" world")

    assert checksum.verify!
  end

  test "refusing a body that doesn't match what was promised" do
    checksum = Tus::Checksum.parse("sha256 #{digest("hello world")}")
    checksum.update "hello mars"

    error = assert_raises(Tus::ChecksumMismatch) { checksum.verify! }
    assert_equal 460, error.status
  end

  test "an empty body is still checked" do
    assert Tus::Checksum.parse("sha256 #{digest("")}").verify!
    assert_raises(Tus::ChecksumMismatch) { Tus::Checksum.parse("sha256 #{digest("x")}").verify! }
  end

  private
    def digest(body) = OpenSSL::Digest::SHA256.base64digest(body)
end
