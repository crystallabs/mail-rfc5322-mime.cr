module Mail
  # The header section: an ordered list of fields whose names compare
  # case-insensitively. Values are kept as single unfolded lines; folding
  # happens on write.
  class Headers
    include Enumerable({String, String})

    record Field, name : String, value : String

    MAX_LINE = 78

    getter fields : Array(Field)

    def initialize
      @fields = [] of Field
    end

    def each(& : {String, String} ->) : Nil
      @fields.each { |field| yield({field.name, field.value}) }
    end

    # The first value of the field, or `nil`.
    def []?(name : String) : String?
      @fields.find { |field| same_name?(field.name, name) }.try(&.value)
    end

    def [](name : String) : String
      self[name]? || raise KeyError.new("Missing header #{name.inspect}")
    end

    def all(name : String) : Array(String)
      @fields.select { |field| same_name?(field.name, name) }.map(&.value)
    end

    def has?(name : String) : Bool
      @fields.any? { |field| same_name?(field.name, name) }
    end

    # Sets the field, replacing every existing one of that name while keeping
    # the first one's position. `nil` deletes.
    def []=(name : String, value : String?) : String?
      if value.nil?
        delete(name)
        return
      end
      field = Field.new(name, sanitize(value))
      index = @fields.index { |existing| same_name?(existing.name, name) }
      @fields.reject! { |existing| same_name?(existing.name, name) }
      index ? @fields.insert(index, field) : @fields << field
      value
    end

    def add(name : String, value : String) : Nil
      @fields << Field.new(name, sanitize(value))
    end

    def delete(name : String) : Nil
      @fields.reject! { |field| same_name?(field.name, name) }
    end

    def empty? : Bool
      @fields.empty?
    end

    def size : Int32
      @fields.size
    end

    def dup : Headers
      copy = Headers.new
      @fields.each { |field| copy.fields << field }
      copy
    end

    # Writes the section folded at 78 columns; the blank line is the caller's.
    def write(io : IO, eol : String = "\n", ascii_only : Bool = false) : Nil
      @fields.each do |field|
        value = ascii_only ? EncodedWord.encode_if_needed(field.value) : field.value
        fold(io, "#{field.name}: #{value}", eol)
      end
    end

    def to_s(io : IO) : Nil
      write(io)
    end

    # Breaks a header line at whitespace so no line exceeds 78 characters
    # when that is possible; a word longer than that is left whole.
    private def fold(io : IO, line : String, eol : String) : Nil
      if line.size <= MAX_LINE
        io << line << eol
        return
      end

      column = 0
      line.split(' ').each_with_index do |word, index|
        if index.zero?
          io << word
          column = word.size
        elsif column + 1 + word.size > MAX_LINE && column > 0
          io << eol << ' ' << word
          column = 1 + word.size
        else
          io << ' ' << word
          column += 1 + word.size
        end
      end
      io << eol
    end

    private def same_name?(a : String, b : String) : Bool
      a.compare(b, case_insensitive: true) == 0
    end

    # A value must not contain bare line breaks; a folded one is unfolded.
    private def sanitize(value : String) : String
      value.gsub(/\r?\n[ \t]*/, " ").strip
    end
  end
end
