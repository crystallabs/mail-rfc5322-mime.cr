require "./spec_helper"

describe Mail::EncodedWord do
  describe ".decode" do
    it "decodes a B encoded word" do
      Mail::EncodedWord.decode("=?UTF-8?B?Q2Fmw6k=?=").should eq "Café"
      Mail::EncodedWord.decode("=?utf-8?b?Q2Fmw6k=?=").should eq "Café"
    end

    it "decodes a Q encoded word, with underscores as spaces" do
      Mail::EncodedWord.decode("=?UTF-8?Q?Caf=C3=A9_au_lait?=").should eq "Café au lait"
      Mail::EncodedWord.decode("=?utf-8?q?Caf=C3=A9?=").should eq "Café"
    end

    it "honours the declared charset" do
      Mail::EncodedWord.decode("=?ISO-8859-1?Q?Caf=E9?=").should eq "Café"
      Mail::EncodedWord.decode("=?iso-8859-1?B?Q2Fm6Q==?=").should eq "Café"
    end

    it "ignores an RFC 2231 language tag on the charset" do
      Mail::EncodedWord.decode("=?ISO-8859-1*en?Q?Caf=E9?=").should eq "Café"
    end

    it "falls back to UTF-8 for an unknown charset" do
      Mail::EncodedWord.decode("=?x-nonexistent?Q?Caf=C3=A9?=").should eq "Café"
    end

    it "keeps the surrounding plain text" do
      Mail::EncodedWord.decode("Re: =?UTF-8?B?Q2Fmw6k=?= please").should eq "Re: Café please"
    end

    it "drops the whitespace between adjacent encoded words" do
      Mail::EncodedWord.decode("=?UTF-8?B?Q2Fm?= =?UTF-8?B?w6k=?=").should eq "Café"
      Mail::EncodedWord.decode("=?UTF-8?B?Q2Fm?=\r\n =?UTF-8?B?w6k=?=").should eq "Café"
      Mail::EncodedWord.decode("=?UTF-8?Q?a?= \t =?UTF-8?Q?b?= =?UTF-8?Q?c?=").should eq "abc"
    end

    it "keeps whitespace around plain text between encoded words" do
      Mail::EncodedWord.decode("=?UTF-8?B?Q2Fm?= and =?UTF-8?B?w6k=?=").should eq "Caf and é"
    end

    it "replaces, rather than raises on, a multi-byte character split across two words" do
      # RFC 2047 requires each word to hold whole characters; a split one is
      # decoded per word, so the halves come out as replacement characters.
      Mail::EncodedWord.decode("=?UTF-8?B?Q2Fmww==?= =?UTF-8?B?qQ==?=").should eq "Caf\uFFFD\uFFFD"
    end

    it "returns text without encoded words unchanged" do
      plain = "Just a subject"
      Mail::EncodedWord.decode(plain).should be plain
      Mail::EncodedWord.decode("a =? b").should eq "a =? b"
      Mail::EncodedWord.decode("=?UTF-8?X?abc?=").should eq "=?UTF-8?X?abc?="
    end

    it "keeps a word whose base64 does not decode" do
      Mail::EncodedWord.decode("=?UTF-8?B?!!!?=").should eq "=?UTF-8?B?!!!?="
    end

    it "decodes an empty encoded text to nothing" do
      Mail::EncodedWord.decode("[=?UTF-8?B??=]").should eq "[]"
      Mail::EncodedWord.decode("[=?UTF-8?Q??=]").should eq "[]"
    end
  end

  describe ".encode" do
    it "produces a single UTF-8 B word for short text" do
      Mail::EncodedWord.encode("Café").should eq "=?UTF-8?B?Q2Fmw6k=?="
    end

    it "encodes ASCII too when asked directly" do
      Mail::EncodedWord.encode("abc").should eq "=?UTF-8?B?YWJj?="
    end

    it "returns an empty string for empty text" do
      Mail::EncodedWord.encode("").should eq ""
    end

    it "splits long text into words of at most 75 characters" do
      text = "Zażółć gęślą jaźń " * 6
      encoded = Mail::EncodedWord.encode(text)
      words = encoded.split(' ')
      words.size.should be > 1
      words.each do |word|
        word.size.should be <= Mail::EncodedWord::MAX_WORD
        word.should match(/\A=\?UTF-8\?B\?[A-Za-z0-9+\/]+=*\?=\z/)
      end
      Mail::EncodedWord.decode(encoded).should eq text
    end

    it "splits on character boundaries, never inside a multi-byte sequence" do
      text = "é" * 40
      encoded = Mail::EncodedWord.encode(text)
      words = encoded.split(' ')
      words.size.should eq 2
      words.each do |word|
        payload = word.lchop("=?UTF-8?B?").rchop("?=")
        String.new(Base64.decode(payload)).valid_encoding?.should be_true
      end
      Mail::EncodedWord.decode(encoded).should eq text
    end

    it "fills each word with 45 bytes when the text is ASCII" do
      encoded = Mail::EncodedWord.encode("a" * 100)
      words = encoded.split(' ')
      words.size.should eq 3
      words[0].should eq "=?UTF-8?B?" + Base64.strict_encode("a" * 45) + "?="
      words[0].size.should eq 72
      Mail::EncodedWord.decode(encoded).should eq "a" * 100
    end
  end

  describe ".encode_if_needed" do
    it "leaves ASCII alone" do
      Mail::EncodedWord.encode_if_needed("Plain subject").should eq "Plain subject"
      Mail::EncodedWord.encode_if_needed("").should eq ""
    end

    it "encodes the words with non-ASCII characters and keeps the rest" do
      Mail::EncodedWord.encode_if_needed("Café").should eq "=?UTF-8?B?Q2Fmw6k=?="
      Mail::EncodedWord.encode_if_needed("Re: naïve").should eq "Re: =?UTF-8?B?bmHDr3Zl?="
      Mail::EncodedWord.encode_if_needed("Käte <k@example.com>").should eq "=?UTF-8?B?S8OkdGU=?= <k@example.com>"
    end

    it "encodes a run of non-ASCII words as one unit so their spacing survives" do
      encoded = Mail::EncodedWord.encode_if_needed("Zażółć gęślą jaźń")
      encoded.split(' ').size.should eq 1
      Mail::EncodedWord.decode(encoded).should eq "Zażółć gęślą jaźń"
    end

    it "round-trips mixed text, including repeated spaces" do
      {"Päy the rënt", "a  ä", "ä  a", "ä a  ä", "x é y", "1 ü 2 ü 3"}.each do |text|
        encoded = Mail::EncodedWord.encode_if_needed(text)
        encoded.ascii_only?.should be_true
        Mail::EncodedWord.decode(encoded).should eq text
      end
    end
  end
end
