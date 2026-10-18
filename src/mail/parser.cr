module Mail
  # Lenient reading. The header section ends at the first empty line; LF and
  # CRLF both count. A header line without a colon is skipped, folded lines
  # are joined, encoded words are decoded. A multipart whose boundary never
  # appears is read as a plain leaf so no content is lost.
  module Parser
    def self.parse(source : String) : Message
      message = Message.new
      fill(message, source)
      message
    end

    # Fills `part` from the raw text of one entity.
    def self.fill(part : Part, source : String) : Nil
      header_text, body_text = split(source)
      parse_headers(part.headers, header_text)

      type = part.content_type
      boundary = type.boundary
      if type.multipart? && boundary && !boundary.empty?
        pieces = split_multipart(body_text, boundary)
        unless pieces.empty?
          part.parts = pieces.map do |piece|
            child = Part.new
            fill(child, piece)
            child
          end
          return
        end
      end
      part.body = decode_transfer(body_text, part.headers["Content-Transfer-Encoding"]?)
    end

    # The header section and the body, without the empty line between them.
    def self.split(source : String) : {String, String}
      return {"", source.lchop("\r\n").lchop("\n")} if source.starts_with?("\n") || source.starts_with?("\r\n")
      if match = source.match(/\r?\n\r?\n/)
        {source[0, match.begin], source[match.end..]}
      else
        {source, ""}
      end
    end

    def self.parse_headers(headers : Headers, text : String) : Nil
      name = nil
      value = String::Builder.new
      flush = -> do
        headers.add(name.as(String), EncodedWord.decode(value.to_s)) if name
        name = nil
        value = String::Builder.new
      end

      text.each_line do |line|
        if (line.starts_with?(' ') || line.starts_with?('\t')) && name
          value << ' ' << line.strip
          next
        end
        flush.call
        field, separator, rest = line.partition(':')
        # A field name is one or more printable ASCII characters other than the colon.
        next if separator.empty? || field.empty? || field.each_char.any? { |char| char.ord < 33 || char.ord > 126 }
        name = field
        value << rest.strip
      end
      flush.call
    end

    # The raw text of each part between the boundary lines; the preamble and
    # epilogue are dropped, and a missing closing delimiter is tolerated.
    def self.split_multipart(body : String, boundary : String) : Array(String)
      delimiter = "--#{boundary}"
      pieces = [] of String
      current = IO::Memory.new
      inside = false

      body.each_line(chomp: false) do |line|
        marker = line.rstrip
        if marker == delimiter
          pieces << finish(current) if inside
          current = IO::Memory.new
          inside = true
        elsif marker == "#{delimiter}--"
          pieces << finish(current) if inside
          inside = false
          break
        elsif inside
          current << line
        end
      end
      pieces << finish(current) if inside
      pieces
    end

    def self.decode_transfer(text : String, encoding : String?) : Bytes
      case encoding.try(&.strip.downcase)
      when "base64"
        begin
          Base64.decode(text.gsub(/\s+/, ""))
        rescue Base64::Error
          text.to_slice
        end
      when "quoted-printable"
        QuotedPrintable.decode(text)
      else
        text.to_slice
      end
    end

    # The line break before a boundary belongs to the boundary, not the part.
    private def self.finish(io : IO::Memory) : String
      io.to_s.rchop("\n").rchop("\r")
    end
  end
end
