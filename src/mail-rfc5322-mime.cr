# Internet messages: RFC 5322 headers and MIME bodies.
#
#   message = Mail.parse(File.read("cur/1790174809.M1P1Q1.host:2,S"))
#   message.subject            # => "Pay rent"
#   message.text               # => the first text/plain part, decoded
#   message.attachments        # => the parts with a filename
#
#   reply = Mail::Message.new
#   reply.subject = "Re: Pay rent"
#   reply.text = "Paid."
#   reply.attach("receipt.pdf", pdf_bytes, "application/pdf")
#   File.write(path, reply.to_s)
#
# Parsing is lenient: it takes LF or CRLF line endings, folded headers,
# encoded words in any charset iconv knows, and bodies in any transfer
# encoding, and never raises on a malformed message. Writing is strict:
# headers are folded at 78 columns, UTF-8 is written as is (RFC 6532) or as
# encoded words on request, text goes out 7bit or 8bit and everything else
# base64.
require "base64"
require "uri"
require "./mail/version"
require "./mail/quoted_printable"
require "./mail/charset"
require "./mail/encoded_word"
require "./mail/parameterized_value"
require "./mail/headers"
require "./mail/date"
require "./mail/part"
require "./mail/message"
require "./mail/parser"
require "./mail/writer"

module Mail
  # Parses a complete message. Never raises on malformed input: whatever
  # cannot be understood is kept verbatim as text.
  def self.parse(source : String) : Message
    Parser.parse(source)
  end

  def self.parse(io : IO) : Message
    parse(io.gets_to_end)
  end

  # A fresh `<unix-time.random@domain>` Message-ID.
  def self.message_id(domain : String = System.hostname) : String
    "<#{Time.utc.to_unix}.#{Random::Secure.hex(8)}@#{domain}>"
  end
end
