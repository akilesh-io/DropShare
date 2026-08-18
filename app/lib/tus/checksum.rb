# The Upload-Checksum header of the checksum extension: an algorithm and the Base64 encoded
# checksum of the request body, separated by a space.
#
#   Upload-Checksum: sha256 uU0nuZNNPg2FGiwWpZrtclz1BFVL9nJ8Kbz2wLC7CJU=
#
# The checksum is computed as the body is written out, so a chunk never has to be held in
# memory to be verified. A chunk that doesn't match is thrown away and the client sends it
# again -- which is the whole point of checking.
class Tus::Checksum
  ALGORITHMS = %w[ sha1 sha256 md5 ].freeze

  attr_reader :algorithm, :expected

  # Returns nil when the client didn't ask for verification.
  def self.parse(header)
    return nil if header.blank?

    algorithm, expected = header.split(" ", 2)
    algorithm = algorithm.to_s.downcase
    raise Tus::BadRequest, "Unsupported checksum algorithm #{algorithm.inspect}" unless ALGORITHMS.include?(algorithm)

    new(algorithm, expected.to_s)
  end

  def initialize(algorithm, expected)
    @algorithm = algorithm
    @expected = expected
    @digest = OpenSSL::Digest.new(algorithm)
  end

  def update(data)
    @digest << data
    self
  end

  def verify!
    actual = @digest.base64digest

    unless ActiveSupport::SecurityUtils.secure_compare(actual, expected)
      raise Tus::ChecksumMismatch, "Expected #{algorithm} #{expected.inspect}, got #{actual.inspect}"
    end

    true
  end
end
