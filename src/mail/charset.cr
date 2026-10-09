module Mail
  # Bytes in a declared charset to a Crystal (UTF-8) string, as forgivingly as
  # possible: an unknown or missing charset is read as UTF-8 and invalid
  # sequences are replaced rather than raised on.
  module Charset
    UTF8_NAMES = %w[utf-8 utf8 us-ascii ascii]

    def self.decode(bytes : Bytes, charset : String?) : String
      name = normalize(charset)
      return String.new(bytes).scrub if name.nil? || UTF8_NAMES.includes?(name)
      String.new(bytes, name, invalid: :skip)
    rescue ArgumentError
      String.new(bytes).scrub
    end

    # Strips the RFC 2231 language suffix (`utf-8*en`) and surrounding noise.
    def self.normalize(charset : String?) : String?
      return unless charset
      name = charset.split('*', 2).first.strip.strip('"').downcase
      name.empty? ? nil : name
    end
  end
end
