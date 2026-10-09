module Mail
  # Strict writing. Headers are folded at 78 columns and written as UTF-8 (or
  # as encoded words when asked). Content that is clean text, whatever its
  # media type (no NUL, no bare CR, no line over 998 bytes), goes out 7bit or
  # 8bit with its line breaks normalized to `eol`; anything else goes base64
  # in 76-column lines. A declared base64 or quoted-printable encoding is
  # honoured.
  module Writer
    BASE64_LINE = 76

    def self.boundary : String
      "=_#{Random::Secure.hex(12)}"
    end

    def self.write(part : Part, io : IO, eol : String = "\n", ascii_headers : Bool = false, top : Bool = true) : Nil
      headers = part.headers.dup
      add_mime_version(headers) if top && !headers.has?("MIME-Version")

      if children = part.parts
        type = part.content_type
        type = ContentType.new("multipart/mixed", type.params) unless type.multipart?
        boundary = type.boundary || self.boundary
        type["boundary"] = boundary
        headers["Content-Type"] = type.to_s
        headers.delete("Content-Transfer-Encoding")
        headers.write(io, eol, ascii_headers)
        io << eol
        children.each do |child|
          io << "--" << boundary << eol
          write(child, io, eol, ascii_headers, top: false)
          # The line break before a boundary belongs to the boundary, so the
          # part keeps its own final one.
          io << eol
        end
        io << "--" << boundary << "--" << eol
      else
        encoding = choose_encoding(part, headers["Content-Transfer-Encoding"]?)
        headers["Content-Transfer-Encoding"] = encoding
        headers.write(io, eol, ascii_headers)
        io << eol
        write_body(part.body, encoding, io, eol)
      end
    end

    def self.choose_encoding(part : Part, declared : String?) : String
      declared = declared.try(&.strip.downcase)
      return declared if declared && (declared == "base64" || declared == "quoted-printable")

      body = part.body
      return "7bit" if body.empty?
      return "base64" unless textual?(body)
      body.all?(&.< 128) ? "7bit" : "8bit"
    end

    # Goes in front of the first Content-* header, or last.
    private def self.add_mime_version(headers : Headers) : Nil
      index = headers.fields.index(&.name.downcase.starts_with?("content-")) || headers.size
      headers.fields.insert(index, Headers::Field.new("MIME-Version", "1.0"))
    end

    private def self.write_body(body : Bytes, encoding : String, io : IO, eol : String) : Nil
      case encoding
      when "base64"
        encoded = Base64.strict_encode(body)
        (0...encoded.size).step(BASE64_LINE) { |offset| io << encoded[offset, BASE64_LINE] << eol }
      when "quoted-printable"
        encoded = QuotedPrintable.encode(body, eol)
        io << encoded
        io << eol unless encoded.empty? || encoded.ends_with?(eol)
      else
        String.new(body).each_line { |line| io << line << eol }
      end
    end

    # No NUL byte, no CR that is not part of CRLF, no line over 998 bytes.
    private def self.textual?(body : Bytes) : Bool
      run = 0
      body.each_with_index do |byte, index|
        return false if byte == 0
        return false if byte == 13 && !(index + 1 < body.size && body[index + 1] == 10)
        if byte == 10
          run = 0
        else
          run += 1
          return false if run > 998
        end
      end
      true
    end
  end
end
