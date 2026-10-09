module Mail
  # A MIME entity: a header section plus either decoded content (a leaf) or a
  # list of sub-parts (a multipart). The top-level entity is a `Message`.
  class Part
    getter headers : Headers
    # The content after transfer decoding; empty for a multipart.
    property body : Bytes
    # The sub-parts; `nil` for a leaf.
    property parts : Array(Part)?

    def initialize(@headers = Headers.new, @body = Bytes.empty, @parts = nil)
    end

    # -- content type ----------------------------------------------------------

    # The declared type; `text/plain; charset=us-ascii` when there is none, as
    # RFC 2045 prescribes.
    def content_type : ContentType
      ContentType.parse(headers["Content-Type"]? || "text/plain; charset=us-ascii")
    end

    def content_type=(type : ContentType | String) : Nil
      headers["Content-Type"] = type.to_s
    end

    def disposition : ParameterizedValue?
      headers["Content-Disposition"]?.try { |value| ParameterizedValue.parse(value) }
    end

    # From Content-Disposition, falling back to the Content-Type `name`.
    def filename : String?
      disposition.try(&.["filename"]) || content_type["name"]
    end

    # Declared as an attachment, or carrying a file name.
    def attachment? : Bool
      disposition.try(&.value.downcase) == "attachment" || !filename.nil?
    end

    def multipart? : Bool
      !parts.nil?
    end

    def text? : Bool
      content_type.text?
    end

    # -- content ---------------------------------------------------------------

    # The content as a string: a leaf decoded by its charset, a multipart's
    # first text part (or "" when it has none).
    def text : String
      if parts
        text_part.try(&.text) || ""
      else
        Charset.decode(body, content_type.charset)
      end
    end

    # Replaces the content with UTF-8 text, making this a `text/plain` leaf
    # unless it already is some other text type.
    def text=(string : String) : String
      @parts = nil
      @body = string.to_slice
      type = headers.has?("Content-Type") ? content_type : ContentType.text_plain
      type = ContentType.text_plain unless type.text?
      type["charset"] = "utf-8"
      headers["Content-Type"] = type.to_s
      string
    end

    # The first text part that is not an attachment, depth-first; self for a
    # text leaf.
    def text_part : Part?
      if children = parts
        children.each do |child|
          found = child.text_part
          return found if found
        end
        nil
      else
        text? && !attachment? ? self : nil
      end
    end

    # Every leaf below this part, depth-first; self for a leaf.
    def leaves : Array(Part)
      found = [] of Part
      each_leaf { |leaf| found << leaf }
      found
    end

    def each_leaf(&block : Part ->) : Nil
      if children = parts
        children.each(&.each_leaf(&block))
      else
        yield self
      end
    end

    def attachments : Array(Part)
      leaves.select(&.attachment?)
    end

    # -- building --------------------------------------------------------------

    # Turns a leaf into a `multipart/<subtype>` whose first part holds what the
    # leaf contained; a leaf with no content becomes an empty multipart.
    def make_multipart!(subtype : String = "mixed") : Nil
      return if parts

      first = Part.new(Headers.new, body)
      %w[Content-Type Content-Transfer-Encoding Content-Disposition Content-ID].each do |name|
        if value = headers[name]?
          first.headers[name] = value
          headers.delete(name)
        end
      end
      @parts = body.empty? && first.headers.empty? ? [] of Part : [first]
      @body = Bytes.empty
      headers["Content-Type"] = "multipart/#{subtype}; boundary=#{Writer.boundary}"
    end

    def add_part(part : Part) : Part
      make_multipart!
      (@parts ||= [] of Part) << part
      part
    end

    # Adds an attachment part with the given file name and content type.
    def attach(filename : String, content : Bytes | String, content_type : String = "application/octet-stream") : Part
      part = Part.new
      type = ContentType.parse(content_type)
      type["name"] = filename
      part.headers["Content-Type"] = type.to_s
      part.headers["Content-Disposition"] = ParameterizedValue.new("attachment", {"filename" => filename}).to_s
      part.body = content.is_a?(String) ? content.to_slice : content
      add_part(part)
    end

    # -- output ----------------------------------------------------------------

    # Writes the entity. `eol` is "\n" for files on disk (the maildir
    # convention) or "\r\n" for the wire; `ascii_headers` turns non-ASCII
    # header values into encoded words instead of raw UTF-8.
    def write(io : IO, eol : String = "\n", ascii_headers : Bool = false) : Nil
      Writer.write(self, io, eol, ascii_headers)
    end

    def to_s(io : IO) : Nil
      write(io)
    end
  end
end
