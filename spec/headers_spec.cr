require "./spec_helper"

private def sample_headers : Mail::Headers
  headers = Mail::Headers.new
  headers.add("From", "a@example.com")
  headers.add("Subject", "Hello")
  headers.add("Received", "first")
  headers.add("Received", "second")
  headers
end

describe Mail::Headers do
  describe "lookup" do
    it "finds the first value case-insensitively" do
      headers = sample_headers
      headers["subject"]?.should eq "Hello"
      headers["SUBJECT"]?.should eq "Hello"
      headers["Received"]?.should eq "first"
      headers["received"].should eq "first"
    end

    it "is nil, or raises KeyError, for a missing field" do
      headers = sample_headers
      headers["To"]?.should be_nil
      expect_raises(KeyError, /To/) { headers["To"] }
    end

    it "returns every value of a repeated field in order" do
      headers = sample_headers
      headers.all("received").should eq ["first", "second"]
      headers.all("Subject").should eq ["Hello"]
      headers.all("To").should be_empty
    end

    it "knows which fields it has" do
      headers = sample_headers
      headers.has?("from").should be_true
      headers.has?("FROM").should be_true
      headers.has?("To").should be_false
    end

    it "reports size and emptiness" do
      Mail::Headers.new.empty?.should be_true
      Mail::Headers.new.size.should eq 0
      sample_headers.empty?.should be_false
      sample_headers.size.should eq 4
    end
  end

  describe "#[]=" do
    it "replaces every field of that name, keeping the first one's position" do
      headers = sample_headers
      (headers["RECEIVED"] = "only").should eq "only"
      headers.map(&.first).should eq ["From", "Subject", "RECEIVED"]
      headers.all("received").should eq ["only"]
      headers.size.should eq 3
    end

    it "appends when the field is new" do
      headers = sample_headers
      headers["To"] = "b@example.com"
      headers.fields.last.name.should eq "To"
      headers["to"]?.should eq "b@example.com"
    end

    it "deletes every field of that name when given nil" do
      headers = sample_headers
      (headers["received"] = nil).should be_nil
      headers.has?("Received").should be_false
      headers.size.should eq 2
    end

    it "sanitizes the value" do
      headers = Mail::Headers.new
      headers["Subject"] = "  folded\r\n  line\n\tmore  "
      headers["Subject"]?.should eq "folded line more"
    end
  end

  describe "#add and #delete" do
    it "adds a second field with the same name instead of replacing" do
      headers = Mail::Headers.new
      headers.add("Received", "one")
      headers.add("received", "two")
      headers.all("Received").should eq ["one", "two"]
      headers.fields.map(&.name).should eq ["Received", "received"]
    end

    it "sanitizes folded and padded values on add" do
      headers = Mail::Headers.new
      headers.add("X-Long", "a\n b\r\n\tc")
      headers["x-long"]?.should eq "a b c"
      headers.add("X-Pad", "  padded  ")
      headers["X-Pad"]?.should eq "padded"
      headers.add("X-Bare", "a\nb")
      headers["X-Bare"]?.should eq "a b"
    end

    it "deletes every field of that name case-insensitively" do
      headers = sample_headers
      headers.delete("RECEIVED")
      headers.has?("Received").should be_false
      headers.size.should eq 2
      headers.delete("Nope")
      headers.size.should eq 2
    end
  end

  describe "enumeration" do
    it "yields name/value tuples in order and supports Enumerable" do
      headers = sample_headers
      headers.to_a.should eq [
        {"From", "a@example.com"},
        {"Subject", "Hello"},
        {"Received", "first"},
        {"Received", "second"},
      ]
      headers.map(&.last).should eq ["a@example.com", "Hello", "first", "second"]
      headers.count { |name, _value| name == "Received" }.should eq 2
    end
  end

  describe "#dup" do
    it "copies the fields independently" do
      headers = sample_headers
      copy = headers.dup
      copy["Subject"] = "Changed"
      copy.add("To", "c@example.com")
      headers["Subject"]?.should eq "Hello"
      headers.has?("To").should be_false
      copy["Subject"]?.should eq "Changed"
      copy.size.should eq 5
    end
  end

  describe "#write and #to_s" do
    it "writes one line per field with the given eol" do
      headers = Mail::Headers.new
      headers.add("From", "a@example.com")
      headers.add("Subject", "Hello")
      headers.to_s.should eq "From: a@example.com\nSubject: Hello\n"
      String.build { |io| headers.write(io, "\r\n") }.should eq "From: a@example.com\r\nSubject: Hello\r\n"
    end

    it "writes nothing for no fields" do
      Mail::Headers.new.to_s.should eq ""
    end

    it "leaves a line of exactly 78 characters unfolded" do
      value = "x" * (78 - "Subject: ".size)
      headers = Mail::Headers.new
      headers.add("Subject", value)
      headers.to_s.should eq "Subject: #{value}\n"
    end

    it "folds long values at whitespace so no line exceeds 78 characters" do
      value = (1..30).map { |number| "word#{number}" }.join(' ')
      headers = Mail::Headers.new
      headers.add("Subject", value)
      output = headers.to_s
      lines = output.chomp.split("\n")
      lines.size.should be > 1
      lines.each(&.size.should(be <= Mail::Headers::MAX_LINE))
      lines[0].should start_with "Subject: word1"
      lines[1..].each(&.should(start_with(" ")))
      lines[1..].each(&.should_not(start_with("  ")))
      # Unfolding (removing the line breaks) restores the original line.
      output.chomp.gsub("\n", "").should eq "Subject: #{value}"
    end

    it "folds with the requested eol" do
      value = (1..30).map { |number| "word#{number}" }.join(' ')
      headers = Mail::Headers.new
      headers.add("Subject", value)
      output = String.build { |io| headers.write(io, "\r\n") }
      output.should contain "\r\n "
      output.should_not match(/[^\r]\n/)
      output.gsub("\r\n", "").should eq "Subject: #{value}"
    end

    it "leaves a word longer than the limit whole on its own continuation line" do
      long = "a" * 120
      headers = Mail::Headers.new
      headers.add("X-Long", long)
      lines = headers.to_s.chomp.split("\n")
      lines.should eq ["X-Long:", " #{long}"]
    end

    it "keeps a long word whole in the middle of a folded value" do
      long = "b" * 100
      headers = Mail::Headers.new
      headers.add("Subject", "start #{long} end")
      lines = headers.to_s.chomp.split("\n")
      lines.should eq ["Subject: start", " #{long}", " end"]
    end

    it "writes UTF-8 as is by default and as encoded words when ascii_only" do
      headers = Mail::Headers.new
      headers.add("Subject", "Café")
      headers.add("From", "a@example.com")
      headers.to_s.should eq "Subject: Café\nFrom: a@example.com\n"
      String.build { |io| headers.write(io, "\n", ascii_only: true) }
        .should eq "Subject: =?UTF-8?B?Q2Fmw6k=?=\nFrom: a@example.com\n"
    end

    it "folds encoded words too when ascii_only" do
      value = ("Zażółć gęślą jaźń " * 5).strip
      headers = Mail::Headers.new
      headers.add("Subject", value)
      output = String.build { |io| headers.write(io, "\n", ascii_only: true) }
      lines = output.chomp.split("\n")
      lines.size.should be > 1
      lines.each(&.size.should(be <= Mail::Headers::MAX_LINE))
      lines.each(&.ascii_only?.should(be_true))
      Mail::EncodedWord.decode(output.chomp.gsub("\n", "").lchop("Subject: ")).should eq value
    end
  end
end
