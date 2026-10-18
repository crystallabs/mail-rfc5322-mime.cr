require "./spec_helper"

describe Mail::ParameterizedValue do
  describe ".parse" do
    it "splits the value from its parameters" do
      parsed = Mail::ParameterizedValue.parse("text/plain; charset=utf-8")
      parsed.value.should eq "text/plain"
      parsed.params.should eq({"charset" => "utf-8"})
    end

    it "lowercases parameter names and keeps parameter values as given" do
      parsed = Mail::ParameterizedValue.parse("text/plain; Charset=UTF-8; FORMAT=Flowed")
      parsed.params.should eq({"charset" => "UTF-8", "format" => "Flowed"})
    end

    it "tolerates whitespace around the value, names, equals signs and semicolons" do
      parsed = Mail::ParameterizedValue.parse("  text/plain ;  charset = utf-8 ; format=flowed  ")
      parsed.value.should eq "text/plain"
      parsed.params.should eq({"charset" => "utf-8", "format" => "flowed"})
    end

    it "handles a bare value and an empty string" do
      Mail::ParameterizedValue.parse("inline").params.should be_empty
      Mail::ParameterizedValue.parse("inline").value.should eq "inline"
      Mail::ParameterizedValue.parse("").value.should eq ""
      Mail::ParameterizedValue.parse("").params.should be_empty
    end

    it "unquotes quoted values, including escapes and semicolons inside quotes" do
      Mail::ParameterizedValue.parse(%q(attachment; filename="my file.txt"))["filename"].should eq "my file.txt"
      Mail::ParameterizedValue.parse(%q(attachment; filename="a \"q\" b"))["filename"].should eq %q(a "q" b)
      Mail::ParameterizedValue.parse(%q(attachment; filename="a;b.txt"; x=1))["filename"].should eq "a;b.txt"
      Mail::ParameterizedValue.parse(%q(attachment; filename="back\\slash"))["filename"].should eq "back\\slash"
      Mail::ParameterizedValue.parse(%q(attachment; filename=""))["filename"].should eq ""
    end

    it "ignores pieces without an equals sign and a trailing semicolon" do
      parsed = Mail::ParameterizedValue.parse("text/plain; junk; charset=utf-8;")
      parsed.params.should eq({"charset" => "utf-8"})
    end

    it "keeps the first of a repeated parameter or section" do
      Mail::ParameterizedValue.parse("text/plain; charset=utf-8; charset=latin1").params.should eq({"charset" => "utf-8"})
      Mail::ParameterizedValue.parse("text/plain; Charset=utf-8; charset=latin1")["charset"].should eq "utf-8"
      Mail::ParameterizedValue.parse("attachment; filename*0=a; filename*1=b; filename*1=c")["filename"].should eq "ab"
    end

    it "decodes an RFC 2231 charset-tagged value" do
      Mail::ParameterizedValue.parse("attachment; filename*=utf-8''%E2%82%AC.txt")["filename"].should eq "€.txt"
      Mail::ParameterizedValue.parse("attachment; filename*=iso-8859-1''caf%E9")["filename"].should eq "café"
      Mail::ParameterizedValue.parse("attachment; filename*=UTF-8''%E2%82%AC")["filename"].should eq "€"
    end

    it "ignores the RFC 2231 language tag" do
      Mail::ParameterizedValue.parse("attachment; filename*=utf-8'en'%E2%82%AC.txt")["filename"].should eq "€.txt"
    end

    it "reads an extended value without a charset marker as UTF-8" do
      Mail::ParameterizedValue.parse("attachment; filename*=%E2%82%AC")["filename"].should eq "€"
    end

    it "joins RFC 2231 continuations in numeric order, mixing extended and plain sections" do
      text = "attachment; filename*0*=utf-8''%E2%82%AC; filename*1*=%20rate; filename*2=.txt"
      Mail::ParameterizedValue.parse(text)["filename"].should eq "€ rate.txt"

      shuffled = "attachment; filename*2=.txt; filename*0*=utf-8''%E2%82%AC; filename*1*=%20rate"
      Mail::ParameterizedValue.parse(shuffled)["filename"].should eq "€ rate.txt"

      unquoted = %q(attachment; filename*0="part one "; filename*1="part two")
      Mail::ParameterizedValue.parse(unquoted)["filename"].should eq "part one part two"
    end

    it "applies the charset from the first section to every extended section" do
      text = "attachment; filename*0*=iso-8859-1''caf%E9; filename*1*=%20ol%E9"
      Mail::ParameterizedValue.parse(text)["filename"].should eq "café olé"
    end
  end

  describe "#[] and #[]=" do
    it "looks parameters up case-insensitively" do
      parsed = Mail::ParameterizedValue.parse("text/plain; charset=utf-8")
      parsed["CHARSET"].should eq "utf-8"
      parsed["Charset"].should eq "utf-8"
      parsed["boundary"].should be_nil
    end

    it "sets, replaces and deletes parameters" do
      value = Mail::ParameterizedValue.new("text/plain")
      (value["Charset"] = "utf-8").should eq "utf-8"
      value.params.should eq({"charset" => "utf-8"})
      value["charset"] = "iso-8859-1"
      value.params.should eq({"charset" => "iso-8859-1"})
      (value["CHARSET"] = nil).should be_nil
      value.params.should be_empty
    end
  end

  describe "#to_s" do
    it "writes the value and parameters with `; ` separators" do
      Mail::ParameterizedValue.new("text/plain", {"charset" => "utf-8"}).to_s.should eq "text/plain; charset=utf-8"
      Mail::ParameterizedValue.new("inline").to_s.should eq "inline"
    end

    it "keeps parameter order" do
      value = Mail::ParameterizedValue.new("multipart/mixed", {"boundary" => "b1", "charset" => "utf-8"})
      value.to_s.should eq "multipart/mixed; boundary=b1; charset=utf-8"
    end

    it "quotes values with whitespace, tspecials or nothing in them, escaping quotes and backslashes" do
      Mail::ParameterizedValue.new("attachment", {"filename" => "my file.txt"}).to_s.should eq %q(attachment; filename="my file.txt")
      Mail::ParameterizedValue.new("attachment", {"filename" => "a/b"}).to_s.should eq %q(attachment; filename="a/b")
      Mail::ParameterizedValue.new("attachment", {"filename" => %q(a"b)}).to_s.should eq %q(attachment; filename="a\"b")
      Mail::ParameterizedValue.new("attachment", {"filename" => "a\\b"}).to_s.should eq %q(attachment; filename="a\\b")
      Mail::ParameterizedValue.new("attachment", {"filename" => ""}).to_s.should eq %q(attachment; filename="")
    end

    it "writes non-ASCII values in RFC 2231 form" do
      Mail::ParameterizedValue.new("attachment", {"filename" => "€.txt"}).to_s.should eq "attachment; filename*=utf-8''%E2%82%AC.txt"
      Mail::ParameterizedValue.new("attachment", {"filename" => "café rate.txt"}).to_s.should eq "attachment; filename*=utf-8''caf%C3%A9%20rate.txt"
    end

    it "round-trips through parse" do
      {
        {"text/plain", {"charset" => "utf-8", "format" => "flowed"}},
        {"attachment", {"filename" => "my \"quoted\" file;v2.txt"}},
        {"attachment", {"filename" => "Zażółć gęślą.txt", "size" => "1234"}},
        {"multipart/mixed", {"boundary" => "=_abc_123"}},
      }.each do |value, params|
        original = Mail::ParameterizedValue.new(value, params)
        Mail::ParameterizedValue.parse(original.to_s).should eq original
      end
    end
  end

  describe "#==" do
    it "compares value and parameters" do
      first = Mail::ParameterizedValue.new("text/plain", {"charset" => "utf-8"})
      second = Mail::ParameterizedValue.new("text/plain", {"charset" => "utf-8"})
      third = Mail::ParameterizedValue.new("text/plain", {"charset" => "ascii"})
      first.should eq second
      first.should_not eq third
      first.should_not eq Mail::ParameterizedValue.new("text/html", {"charset" => "utf-8"})
    end
  end

  describe ".quote_if_needed" do
    it "leaves plain tokens alone" do
      Mail::ParameterizedValue.quote_if_needed("simple").should eq "simple"
      Mail::ParameterizedValue.quote_if_needed("file.txt").should eq "file.txt"
      Mail::ParameterizedValue.quote_if_needed("a-b_c+d").should eq "a-b_c+d"
    end

    it "quotes empty strings, whitespace, tspecials and control characters" do
      Mail::ParameterizedValue.quote_if_needed("").should eq %q("")
      Mail::ParameterizedValue.quote_if_needed("a b").should eq %q("a b")
      Mail::ParameterizedValue.quote_if_needed("a\tb").should eq %q("a	b")
      Mail::ParameterizedValue::TSPECIALS.each_char do |special|
        Mail::ParameterizedValue.quote_if_needed("a#{special}b").should start_with %q(")
      end
      Mail::ParameterizedValue.quote_if_needed("a\u0001b").should eq %q("a) + "\u0001" + %q(b")
    end

    it "escapes quotes and backslashes inside the quoted form" do
      Mail::ParameterizedValue.quote_if_needed(%q(a"b)).should eq %q("a\"b")
      Mail::ParameterizedValue.quote_if_needed("a\\b").should eq %q("a\\b")
    end
  end
end

describe Mail::ContentType do
  describe ".parse" do
    it "lowercases the media type and exposes its halves" do
      content_type = Mail::ContentType.parse("Text/HTML; Charset=UTF-8")
      content_type.value.should eq "text/html"
      content_type.media_type.should eq "text"
      content_type.subtype.should eq "html"
      content_type.charset.should eq "UTF-8"
    end

    it "falls back to application/octet-stream for a value without a slash" do
      Mail::ContentType.parse("garbage").value.should eq "application/octet-stream"
      Mail::ContentType.parse("").value.should eq "application/octet-stream"
      Mail::ContentType.parse("; charset=utf-8").value.should eq "application/octet-stream"
    end

    it "keeps the parameters" do
      content_type = Mail::ContentType.parse("multipart/mixed; boundary=\"=_b1\"")
      content_type.boundary.should eq "=_b1"
      content_type.charset.should be_nil
    end

    it "returns a ContentType, not the base class" do
      Mail::ContentType.parse("text/plain").should be_a(Mail::ContentType)
    end
  end

  describe ".text_plain" do
    it "is text/plain in UTF-8 by default" do
      content_type = Mail::ContentType.text_plain
      content_type.value.should eq "text/plain"
      content_type.charset.should eq "utf-8"
      content_type.to_s.should eq "text/plain; charset=utf-8"
    end

    it "takes another charset" do
      Mail::ContentType.text_plain("iso-8859-2").charset.should eq "iso-8859-2"
    end
  end

  describe "predicates" do
    it "tells text and multipart from the rest" do
      Mail::ContentType.parse("text/plain").text?.should be_true
      Mail::ContentType.parse("text/plain").multipart?.should be_false
      Mail::ContentType.parse("multipart/alternative").multipart?.should be_true
      Mail::ContentType.parse("multipart/alternative").text?.should be_false
      Mail::ContentType.parse("application/pdf").text?.should be_false
      Mail::ContentType.parse("application/pdf").multipart?.should be_false
    end

    it "has an empty subtype when none is present after construction" do
      Mail::ContentType.new("text").subtype.should eq ""
      Mail::ContentType.new("text").media_type.should eq "text"
    end
  end
end
