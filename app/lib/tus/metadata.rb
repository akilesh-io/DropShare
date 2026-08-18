# The Upload-Metadata header: comma separated pairs of a key and its Base64 encoded value.
#
#   Upload-Metadata: filename aG9saWRheS5tcDQ=,filetype dmlkZW8vbXA0
#
# Values are decoded, stripped of anything that has no business being in a filename or a
# response header, and re-encoded before we echo them back, so a value can't smuggle a
# header of its own.
module Tus::Metadata
  KEY_FORMAT = /\A[\w.\-]+\z/
  MAX_VALUE_LENGTH = 1024

  extend self

  def decode(header)
    return {} if header.blank?

    header.split(",").each_with_object({}) do |pair, metadata|
      key, value = pair.strip.split(" ", 2)
      raise Tus::BadRequest, "Invalid Upload-Metadata key #{key.inspect}" unless key.to_s.match?(KEY_FORMAT)

      metadata[key] = decode_value(value)
    end
  end

  def encode(metadata)
    metadata.map { |key, value| value.blank? ? key.to_s : "#{key} #{Base64.strict_encode64(value.to_s)}" }.join(",")
  end

  private
    def decode_value(value)
      return "" if value.nil?

      decoded = Base64.strict_decode64(value)
      decoded.force_encoding(Encoding::UTF_8).scrub.gsub(/[[:cntrl:]]/, "").strip.truncate_bytes(MAX_VALUE_LENGTH, omission: nil)
    rescue ArgumentError
      raise Tus::BadRequest, "Invalid Base64 in Upload-Metadata"
    end
end
