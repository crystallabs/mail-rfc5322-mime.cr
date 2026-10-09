require "./spec_helper"

private def qp_decode(text : String, q_encoding = false) : String
  String.new(Mail::QuotedPrintable.decode(text, q_encoding: q_encoding))
end

private def qp_encode(text : String, eol = "\n") : String
  Mail::QuotedPrintable.encode(text.to_slice, eol)
end

describe Mail::QuotedPrintable do
  describe ".decode" do
    it "decodes =XX escapes in upper and lower case" do
      qp_decode("Caf=C3=A9").should eq "Café"
      qp_decode("Caf=c3=a9").should eq "Café"
      qp_decode("a=3Db").should eq "a=b"
    end

    it "keeps plain text, interior whitespace and bare line breaks" do
      qp_decode("hello world").should eq "hello world"
      qp_decode("a\tb").should eq "a\tb"
      qp_decode("line1\nline2").should eq "line1\nline2"
      qp_decode("line1\r\nline2").should eq "line1\r\nline2"
    end

    it "removes soft line breaks with LF, CRLF and trailing whitespace" do
      qp_decode("foo=\nbar").should eq "foobar"
      qp_decode("foo=\r\nbar").should eq "foobar"
      qp_decode("foo= \t\nbar").should eq "foobar"
    end

    it "drops a trailing = with nothing after it" do
      qp_decode("foo=").should eq "foo"
      qp_decode("foo= ").should eq "foo"
    end

    it "keeps a stray = that is not followed by two hex digits" do
      qp_decode("a=zb").should eq "a=zb"
      qp_decode("a=G1").should eq "a=G1"
      qp_decode("a=1").should eq "a=1"
      qp_decode("100% =done").should eq "100% =done"
    end

    it "drops whitespace that precedes a line break or the end" do
      qp_decode("foo  \nbar").should eq "foo\nbar"
      qp_decode("foo \t\r\nbar").should eq "foo\r\nbar"
      qp_decode("foo \t").should eq "foo"
      qp_decode("foo=20 \nbar").should eq "foo \nbar"
    end

    it "treats underscore literally unless Q encoding is requested" do
      qp_decode("a_b").should eq "a_b"
      qp_decode("a_b", q_encoding: true).should eq "a b"
      qp_decode("Caf=C3=A9_au_lait", q_encoding: true).should eq "Café au lait"
    end

    it "returns bytes, not a string" do
      bytes = Mail::QuotedPrintable.decode("=00=FF")
      bytes.should be_a(Bytes)
      bytes.should eq Bytes[0x00, 0xFF]
    end

    it "decodes an empty input to empty bytes" do
      Mail::QuotedPrintable.decode("").should eq Bytes.empty
    end
  end

  describe ".encode" do
    it "leaves printable ASCII alone and escapes = and non-ASCII bytes" do
      qp_encode("hello world").should eq "hello world"
      qp_encode("Café").should eq "Caf=C3=A9"
      qp_encode("a=b").should eq "a=3Db"
      qp_encode("\u007F").should eq "=7F"
    end

    it "escapes control bytes" do
      Mail::QuotedPrintable.encode(Bytes[0x00, 0x01, 0x1F]).should eq "=00=01=1F"
    end

    it "turns input line breaks into the chosen eol" do
      qp_encode("line1\nline2").should eq "line1\nline2"
      qp_encode("line1\nline2", "\r\n").should eq "line1\r\nline2"
      qp_encode("line1\r\nline2", "\n").should eq "line1\nline2"
      qp_encode("line1\r\nline2", "\r\n").should eq "line1\r\nline2"
    end

    it "encodes whitespace at the end of a line or of the input" do
      qp_encode("a \nb").should eq "a=20\nb"
      qp_encode("a\t\r\nb").should eq "a=09\nb"
      qp_encode("a\t\r\nb", "\r\n").should eq "a=09\r\nb"
      qp_encode("a ").should eq "a=20"
      qp_encode("a\t").should eq "a=09"
      qp_encode("a b").should eq "a b"
    end

    it "encodes a lone carriage return rather than treating it as a break" do
      qp_encode("a\rb").should eq "a=0Db"
    end

    it "inserts soft line breaks so no line exceeds 76 characters" do
      text = "a" * 200
      encoded = qp_encode(text)
      lines = encoded.split("\n")
      lines.size.should eq 3
      lines[0].should eq "a" * 75 + "="
      lines[1].should eq "a" * 75 + "="
      lines[2].should eq "a" * 50
      lines.each { |line| line.size.should be <= Mail::QuotedPrintable::MAX_LINE }
      qp_decode(encoded).should eq text
    end

    it "does not split an =XX escape across a soft line break" do
      text = "a" * 74 + "é"
      encoded = qp_encode(text)
      encoded.split("\n").each do |line|
        line.size.should be <= Mail::QuotedPrintable::MAX_LINE
        # A trailing `=` is a soft break; what precedes it must not be half an escape.
        line.rchop("=").should_not match(/=[0-9A-F]\z/)
      end
      qp_decode(encoded).should eq text
    end

    it "uses the eol for soft breaks too" do
      encoded = qp_encode("a" * 100, "\r\n")
      encoded.should contain "=\r\n"
      encoded.should_not match(/[^\r]\n/)
      qp_decode(encoded).should eq "a" * 100
    end

    it "round-trips every byte value" do
      bytes = Bytes.new(256, &.to_u8)
      Mail::QuotedPrintable.decode(Mail::QuotedPrintable.encode(bytes)).should eq bytes
    end

    it "round-trips multi-line UTF-8 text" do
      text = "Pay rent — €1,200\n\nDue on the 30th.\nNaïve façade, 日本語 text.\n"
      qp_decode(qp_encode(text)).should eq text
    end

    it "encodes empty input to an empty string" do
      Mail::QuotedPrintable.encode(Bytes.empty).should eq ""
    end
  end
end
