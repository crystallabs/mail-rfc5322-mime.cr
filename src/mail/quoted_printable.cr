module Mail
  # The quoted-printable transfer encoding (RFC 2045 §6.7) and the Q encoding
  # of encoded words (RFC 2047 §4.2), which differs only in treating `_` as a
  # space.
  module QuotedPrintable
    MAX_LINE = 76
    HEX      = "0123456789ABCDEF"

    def self.decode(text : String, q_encoding : Bool = false) : Bytes # ameba:disable Metrics/CyclomaticComplexity
      io = IO::Memory.new
      bytes = text.to_slice
      i = 0
      while i < bytes.size
        byte = bytes[i]
        case byte
        when '='.ord
          # Soft line break: `=` followed by optional whitespace and an EOL.
          j = i + 1
          j = skip_blanks(bytes, j)
          if j >= bytes.size
            i = j
          elsif bytes[j] == '\r'.ord || bytes[j] == '\n'.ord
            j += 1 if bytes[j] == '\r'.ord
            j += 1 if j < bytes.size && bytes[j] == '\n'.ord
            i = j
          elsif i + 2 < bytes.size && (hi = hex(bytes[i + 1])) && (lo = hex(bytes[i + 2]))
            io.write_byte((hi << 4 | lo).to_u8)
            i += 3
          else
            # A stray `=`: keep it, RFC 2045 says a robust decoder includes it.
            io.write_byte(byte)
            i += 1
          end
        when '_'.ord
          io.write_byte(q_encoding ? ' '.ord.to_u8 : byte)
          i += 1
        when ' '.ord, '\t'.ord
          # Whitespace before an EOL was added in transit; drop it.
          j = i
          j = skip_blanks(bytes, j)
          if j >= bytes.size || bytes[j] == '\r'.ord || bytes[j] == '\n'.ord
            i = j
          else
            io.write(bytes[i, j - i])
            i = j
          end
        else
          io.write_byte(byte)
          i += 1
        end
      end
      io.to_slice
    end

    # Encodes `bytes` for a message body. Input line breaks (LF or CRLF) become
    # `eol`; output lines are at most 76 characters, with soft breaks.
    def self.encode(bytes : Bytes, eol : String = "\n") : String # ameba:disable Metrics/CyclomaticComplexity
      String.build do |output|
        column = 0
        i = 0
        while i < bytes.size
          byte = bytes[i]
          if byte == '\n'.ord || (byte == '\r'.ord && i + 1 < bytes.size && bytes[i + 1] == '\n'.ord)
            i += byte == '\r'.ord ? 2 : 1
            output << eol
            column = 0
            next
          end

          at_line_end = i + 1 >= bytes.size || bytes[i + 1] == '\n'.ord || bytes[i + 1] == '\r'.ord
          literal = (33 <= byte <= 126 && byte != '='.ord) || ((byte == ' '.ord || byte == '\t'.ord) && !at_line_end)
          width = literal ? 1 : 3

          # Leave room for the `=` of a soft break.
          if column + width > MAX_LINE - 1
            output << '=' << eol
            column = 0
          end
          if literal
            output << byte.unsafe_chr
          else
            output << '=' << HEX[byte >> 4] << HEX[byte & 0xF]
          end
          column += width
          i += 1
        end
      end
    end

    private def self.skip_blanks(bytes : Bytes, from : Int32) : Int32
      while from < bytes.size && (bytes[from] == ' '.ord || bytes[from] == '\t'.ord)
        from += 1
      end
      from
    end

    private def self.hex(byte : UInt8) : UInt8?
      case byte
      when '0'.ord..'9'.ord then (byte - '0'.ord).to_u8
      when 'A'.ord..'F'.ord then (byte - 'A'.ord + 10).to_u8
      when 'a'.ord..'f'.ord then (byte - 'a'.ord + 10).to_u8
      end
    end
  end
end
