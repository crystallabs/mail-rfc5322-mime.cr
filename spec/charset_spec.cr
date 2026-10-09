require "./spec_helper"

describe Mail::Charset do
  describe ".decode" do
    it "reads UTF-8 for a missing charset" do
      Mail::Charset.decode("Café".to_slice, nil).should eq "Café"
    end

    it "reads UTF-8 under all its usual names, case-insensitively" do
      %w[utf-8 UTF-8 utf8 us-ascii US-ASCII ascii].each do |name|
        Mail::Charset.decode("Café".to_slice, name).should eq "Café"
      end
    end

    it "transcodes a known single-byte charset" do
      Mail::Charset.decode(Bytes[0x43, 0x61, 0x66, 0xE9], "ISO-8859-1").should eq "Café"
      Mail::Charset.decode(Bytes[0x43, 0x61, 0x66, 0xE9], "iso-8859-1").should eq "Café"
      Mail::Charset.decode(Bytes[0xA4], "ISO-8859-15").should eq "€"
    end

    it "falls back to UTF-8 for an unknown charset, replacing invalid bytes" do
      Mail::Charset.decode("Café".to_slice, "x-nonexistent").should eq "Café"
      Mail::Charset.decode(Bytes[0x41, 0xFF], "x-nonexistent").should eq "A�"
    end

    it "replaces invalid UTF-8 sequences instead of raising" do
      Mail::Charset.decode(Bytes[0x41, 0xFF, 0x42], "utf-8").should eq "A�B"
      Mail::Charset.decode(Bytes[0xC3], nil).should eq "�"
    end

    it "ignores an RFC 2231 language tag and quotes around the name" do
      Mail::Charset.decode(Bytes[0x43, 0x61, 0x66, 0xE9], "iso-8859-1*en").should eq "Café"
      Mail::Charset.decode(Bytes[0x43, 0x61, 0x66, 0xE9], "\"ISO-8859-1\"").should eq "Café"
    end

    it "returns an empty string for empty bytes" do
      Mail::Charset.decode(Bytes.empty, "utf-8").should eq ""
      Mail::Charset.decode(Bytes.empty, "iso-8859-1").should eq ""
    end
  end

  describe ".normalize" do
    it "is nil for a missing, empty or blank charset" do
      Mail::Charset.normalize(nil).should be_nil
      Mail::Charset.normalize("").should be_nil
      Mail::Charset.normalize("   ").should be_nil
      Mail::Charset.normalize("\"\"").should be_nil
    end

    it "lowercases and strips whitespace, quotes and the language suffix" do
      Mail::Charset.normalize("UTF-8").should eq "utf-8"
      Mail::Charset.normalize(" \"ISO-8859-1\" ").should eq "iso-8859-1"
      Mail::Charset.normalize("utf-8*en").should eq "utf-8"
      Mail::Charset.normalize("UTF-8*en-US").should eq "utf-8"
    end

    it "is nil when only a language suffix is given" do
      Mail::Charset.normalize("*en").should be_nil
    end
  end
end
