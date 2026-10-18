module Mail
  # A header value of the form `value; name=param; name="quoted"`, as used by
  # Content-Type and Content-Disposition. Parameter names are case-insensitive
  # and kept lowercase. RFC 2231 continuations (`name*0*=`) and charset-tagged
  # values (`name*=utf-8''%E2%82%AC`) are decoded on read and produced on write
  # for non-ASCII values.
  class ParameterizedValue
    TSPECIALS = "()<>@,;:\\\"/[]?="

    getter value : String
    getter params : Hash(String, String)

    def initialize(@value, @params = {} of String => String)
    end

    def self.parse(text : String) : self
      pieces = split_on_semicolons(text)
      value = pieces.shift?.try(&.strip) || ""

      sections = {} of String => Array({Int32, Bool, String})
      pieces.each do |piece|
        next unless section = parse_section(piece)
        name, index, extended, raw = section
        parts = sections[name] ||= [] of {Int32, Bool, String}
        # A repeated parameter (or section) is a mistake; the first one wins.
        parts << {index, extended, raw} unless parts.any? { |existing| existing[0] == index }
      end

      params = {} of String => String
      sections.each do |name, parts|
        parts.sort_by! { |section| section[0] }
        charset = nil
        decoded = String.build do |io|
          parts.each do |_, extended, raw|
            if extended
              if charset.nil? && (first = raw.index("'")) && (second = raw.index("'", first + 1))
                charset = raw[0, first]
                raw = raw[second + 1..]
              end
              io << Charset.decode(URI.decode(raw).to_slice, charset || "utf-8")
            else
              io << raw
            end
          end
        end
        params[name] = decoded
      end
      new(value, params)
    end

    def [](name : String) : String?
      params[name.downcase]?
    end

    def []=(name : String, param : String?) : String?
      if param
        params[name.downcase] = param
      else
        params.delete(name.downcase)
      end
      param
    end

    def to_s(io : IO) : Nil
      io << value
      params.each do |name, param|
        io << "; "
        if param.ascii_only?
          io << name << '=' << self.class.quote_if_needed(param)
        else
          io << name << "*=utf-8''" << URI.encode_path_segment(param)
        end
      end
    end

    def ==(other : self) : Bool
      value == other.value && params == other.params
    end

    def self.quote_if_needed(text : String) : String
      return text unless text.empty? || text.each_char.any? { |char| char.ascii_whitespace? || TSPECIALS.includes?(char) || char.ord < 32 }
      "\"#{text.gsub(/(["\\])/) { "\\#{$1}" }}\""
    end

    # One `name=value` piece as its name, RFC 2231 section index, whether it
    # is an extended (`name*=`) value, and the raw value; `nil` for a piece
    # with no `=`.
    private def self.parse_section(piece : String) : {String, Int32, Bool, String}?
      name, separator, raw = piece.partition('=')
      return if separator.empty?
      name = name.strip.downcase
      raw = raw.strip
      extended = name.ends_with?('*')
      name = name.rchop('*') if extended
      index = 0
      if (star = name.index('*')) && (number = name[star + 1..].to_i?)
        index = number
        name = name[0, star]
      end
      raw = unquote(raw) unless extended
      {name, index, extended, raw}
    end

    # Splits on `;` outside quotes, honouring backslash escapes.
    private def self.split_on_semicolons(text : String) : Array(String)
      pieces = [] of String
      current = String::Builder.new
      quoted = false
      escaped = false
      text.each_char do |char|
        if escaped
          current << char
          escaped = false
        elsif char == '\\' && quoted
          current << char
          escaped = true
        elsif char == '"'
          quoted = !quoted
          current << char
        elsif char == ';' && !quoted
          pieces << current.to_s
          current = String::Builder.new
        else
          current << char
        end
      end
      pieces << current.to_s
      pieces
    end

    private def self.unquote(text : String) : String
      return text unless text.size >= 2 && text.starts_with?('"') && text.ends_with?('"')
      text[1..-2].gsub(/\\(.)/) { $1 }
    end
  end

  # `type/subtype; charset=...; boundary=...; name=...`.
  class ContentType < ParameterizedValue
    def self.parse(text : String) : self
      base = ParameterizedValue.parse(text)
      value = base.value.downcase
      value = "application/octet-stream" unless value.includes?('/')
      new(value, base.params)
    end

    def self.text_plain(charset : String = "utf-8") : self
      new("text/plain", {"charset" => charset})
    end

    def media_type : String
      value.split('/', 2).first
    end

    def subtype : String
      value.split('/', 2)[1]? || ""
    end

    def charset : String?
      self["charset"]
    end

    def boundary : String?
      self["boundary"]
    end

    def text? : Bool
      media_type == "text"
    end

    def multipart? : Bool
      media_type == "multipart"
    end
  end
end
