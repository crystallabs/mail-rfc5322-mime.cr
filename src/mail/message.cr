module Mail
  # The top-level entity, with accessors for the common RFC 5322 headers.
  # Addresses are kept as the strings they are; this library does not parse
  # mailboxes.
  class Message < Part
    def self.parse(source : String) : Message
      Parser.parse(source)
    end

    def subject : String?
      headers["Subject"]?
    end

    def subject=(value : String?) : String?
      headers["Subject"] = value
    end

    def date : Time?
      Date.parse(headers["Date"]?)
    end

    def date=(time : Time?) : Time?
      headers["Date"] = time.try { |value| Date.format(value) }
      time
    end

    def from : String?
      headers["From"]?
    end

    def from=(value : String?) : String?
      headers["From"] = value
    end

    def to : String?
      headers["To"]?
    end

    def to=(value : String?) : String?
      headers["To"] = value
    end

    # With its angle brackets, as written.
    def message_id : String?
      headers["Message-ID"]?.try(&.strip)
    end

    def message_id=(id : String?) : String?
      headers["Message-ID"] = id.try { |value| bracket(value) }
      id
    end

    def in_reply_to : String?
      headers["In-Reply-To"]?.try(&.strip)
    end

    def in_reply_to=(id : String?) : String?
      headers["In-Reply-To"] = id.try { |value| bracket(value) }
      id
    end

    def references : Array(String)
      headers["References"]?.try(&.split) || [] of String
    end

    def references=(ids : Array(String)) : Array(String)
      headers["References"] = ids.empty? ? nil : ids.join(' ') { |id| bracket(id) }
      ids
    end

    private def bracket(id : String) : String
      id = id.strip
      id.starts_with?('<') ? id : "<#{id}>"
    end
  end
end
