module Mail
  # RFC 2047 encoded words, `=?charset?B?base64?=` and `=?charset?Q?text?=`,
  # as they appear in Subject and other unstructured headers.
  module EncodedWord
    PATTERN = /=\?([^?\s]+)\?([BbQq])\?([^?\s]*)\?=/
    # Whitespace between two adjacent encoded words carries no meaning.
    BETWEEN = /(=\?[^?\s]+\?[BbQq]\?[^?\s]*\?=)[ \t\r\n]+(?==\?)/

    MAX_WORD = 75

    # Replaces every encoded word in `text` with its decoded form.
    def self.decode(text : String) : String
      return text unless text.includes?("=?")
      text.gsub(BETWEEN, "\\1").gsub(PATTERN) do |word, match|
        bytes = begin
          case match[2].upcase
          when "B" then Base64.decode(match[3])
          else          QuotedPrintable.decode(match[3], q_encoding: true)
          end
        rescue Base64::Error
          nil
        end
        bytes ? Charset.decode(bytes, match[1]) : word
      end
    end

    # Encodes `text` as a run of UTF-8 B-encoded words, each at most 75
    # characters, split on character boundaries.
    def self.encode(text : String) : String
      prefix = "=?UTF-8?B?"
      # 75 - prefix - "?=", in base64 groups of 4 for 3 bytes.
      max_bytes = ((MAX_WORD - prefix.size - 2) // 4) * 3
      words = [] of String
      chunk = IO::Memory.new
      text.each_char do |char|
        if chunk.bytesize + char.bytesize > max_bytes
          words << prefix + Base64.strict_encode(chunk.to_slice) + "?="
          chunk.clear
        end
        chunk << char
      end
      words << prefix + Base64.strict_encode(chunk.to_slice) + "?=" unless chunk.empty?
      words.join(' ')
    end

    # `text` if it is plain ASCII. Otherwise each run of space-separated
    # words holding non-ASCII characters is replaced by encoded words, and
    # the ASCII words around it are kept, so that `Käte <k@example.com>`
    # keeps a readable address. Whitespace between adjacent encoded words is
    # dropped on decoding, so a run is encoded as one unit, spaces included.
    def self.encode_if_needed(text : String) : String
      return text if text.ascii_only?
      pieces = [] of String
      run = [] of String
      text.split(' ').each do |word|
        if word.ascii_only? && !word.empty?
          pieces << encode(run.join(' ')) unless run.empty?
          run.clear
          pieces << word
        else
          run << word
        end
      end
      pieces << encode(run.join(' ')) unless run.empty?
      pieces.join(' ')
    end
  end
end
