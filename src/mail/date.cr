module Mail
  # The RFC 5322 date-time, `Wed, 23 Sep 2026 16:46:49 +0200`.
  module Date
    FORMAT = Time::Format.new("%a, %d %b %Y %H:%M:%S %z")

    def self.format(time : Time) : String
      FORMAT.format(time)
    end

    # Parses the common real-world spellings; `nil` when none fits. A trailing
    # comment such as `(CEST)`, a missing weekday and an obsolete two- or
    # three-digit year are tolerated.
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
        return fix_year(Time.parse(cleaned, pattern, Time::Location::UTC))
      rescue Time::Format::Error
        next
      end
      Time.parse_rfc3339(cleaned)
    rescue Time::Format::Error | ArgumentError
      # A date that does not exist, such as 31 Feb, raises ArgumentError.
      nil
    end

    # RFC 5322 §4.3: a two-digit year below 50 is in the 2000s, any other
    # year below 1000 is in the 1900s.
    private def self.fix_year(time : Time) : Time
      return time if time.year >= 1000
      time + (time.year < 50 ? 2000 : 1900).years
    end
  end
end
