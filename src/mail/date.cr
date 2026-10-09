module Mail
  # The RFC 5322 date-time, `Wed, 23 Sep 2026 16:46:49 +0200`.
  module Date
    FORMAT = Time::Format.new("%a, %d %b %Y %H:%M:%S %z")

    def self.format(time : Time) : String
      FORMAT.format(time)
    end

    # Parses the common real-world spellings; `nil` when none fits. A trailing
    # comment such as `(CEST)` and a missing weekday are tolerated.
    def self.parse(text : String?) : Time?
      return unless text
      cleaned = text.gsub(/\([^)]*\)/, "").strip.gsub(/\s+/, " ")
      return if cleaned.empty?

      {
        "%a, %d %b %Y %H:%M:%S %z",
        "%d %b %Y %H:%M:%S %z",
        "%a, %d %b %Y %H:%M %z",
        "%d %b %Y %H:%M %z",
        "%a, %d %b %Y %H:%M:%S",
        "%d %b %Y %H:%M:%S",
      }.each do |pattern|
        return Time.parse(cleaned, pattern, Time::Location::UTC)
      rescue Time::Format::Error
        next
      end
      Time.parse_rfc3339(cleaned)
    rescue Time::Format::Error
      nil
    end
  end
end
