require "./spec_helper"

private SIMPLE = <<-MAIL
  From: taskman <taskman@localhost>
  Subject: Pay rent
  Date: Wed, 23 Sep 2026 16:46:49 +0200
  Message-ID: <1790174809.M884992P94253Q1.host@taskman>
  Keywords: bills, monthly
  X-Taskman-Due: 2026-09-30
  Content-Type: text/plain; charset=utf-8
  Content-Transfer-Encoding: 8bit

  Transfer €1200 to the landlord.
  Second line.

  MAIL

private MULTIPART = <<-MAIL
  Subject: =?UTF-8?B?UMOkeSByZW50?=
  MIME-Version: 1.0
  Content-Type: multipart/mixed; boundary="=_b1"

  This is the preamble, ignored.
  --=_b1
  Content-Type: text/plain; charset=iso-8859-1
  Content-Transfer-Encoding: quoted-printable

  Caf=E9 note with a soft=
   break.
  --=_b1
  Content-Type: application/x-taskman+yaml; name=taskman.yaml
  Content-Disposition: attachment; filename=taskman.yaml

  repeat: monthly
  completions:
  - 2026-08-30
  --=_b1
  Content-Type: application/octet-stream
  Content-Disposition: attachment; filename*=utf-8''r%C3%A9%C3%A7u.bin
  Content-Transfer-Encoding: base64

  AAECA/8=
  --=_b1--
  Epilogue, ignored.

  MAIL

describe Mail::Parser do
  it "reads headers and a plain body" do
    message = Mail.parse(SIMPLE)
    message.subject.should eq "Pay rent"
    message.from.should eq "taskman <taskman@localhost>"
    message.date.should eq Time.utc(2026, 9, 23, 14, 46, 49)
    message.message_id.should eq "<1790174809.M884992P94253Q1.host@taskman>"
    message.headers["Keywords"].should eq "bills, monthly"
    message.headers["x-taskman-due"].should eq "2026-09-30"
    message.multipart?.should be_false
    message.text.should eq "Transfer €1200 to the landlord.\nSecond line.\n"
    message.content_type.charset.should eq "utf-8"
  end

  it "accepts CRLF line endings and folded headers" do
    source = SIMPLE.gsub("\n", "\r\n").sub("Subject: Pay rent", "Subject: Pay\r\n  rent\r\n\tnow")
    message = Mail.parse(source)
    message.subject.should eq "Pay rent now"
    message.text.should eq "Transfer €1200 to the landlord.\r\nSecond line.\r\n"
  end

  it "parses a multipart message with every transfer encoding" do
    message = Mail.parse(MULTIPART)
    message.subject.should eq "Päy rent"
    message.multipart?.should be_true
    parts = message.parts.should_not be_nil
    parts.size.should eq 3

    parts[0].text.should eq "Café note with a soft break."
    parts[0].attachment?.should be_false
    message.text.should eq "Café note with a soft break."
    message.text_part.should be parts[0]

    parts[1].content_type.value.should eq "application/x-taskman+yaml"
    parts[1].filename.should eq "taskman.yaml"
    parts[1].attachment?.should be_true
    parts[1].text.should eq "repeat: monthly\ncompletions:\n- 2026-08-30"

    parts[2].filename.should eq "réçu.bin"
    parts[2].body.should eq Bytes[0, 1, 2, 3, 255]

    message.attachments.map(&.filename).should eq ["taskman.yaml", "réçu.bin"]
    message.leaves.size.should eq 3
  end

  it "reads a multipart whose boundary never appears as a plain leaf" do
    message = Mail.parse("Content-Type: multipart/mixed; boundary=zzz\n\njust text\n")
    message.multipart?.should be_false
    message.text.should eq "just text\n"
  end

  it "tolerates a missing closing delimiter, a missing body and junk header lines" do
    message = Mail.parse("Content-Type: multipart/mixed; boundary=b\n\n--b\n\nonly part\n")
    message.parts.should_not(be_nil).size.should eq 1
    message.text.should eq "only part"

    Mail.parse("Subject: only headers").subject.should eq "only headers"
    Mail.parse("Subject: only headers\n").text.should eq ""

    message = Mail.parse("From mbox line\nSubject: kept\nno colon here\nBad Name: dropped\n\nbody")
    message.headers.map(&.[0]).should eq ["Subject"]
    message.text.should eq "body"
    Mail.parse("").text.should eq ""
    Mail.parse("\nbody only").text.should eq "body only"
  end

  it "keeps a body with undecodable base64 verbatim" do
    message = Mail.parse("Content-Transfer-Encoding: base64\n\n!!! not base64 !!!\n")
    message.text.should eq "!!! not base64 !!!\n"
  end

  it "defaults the content type to text/plain in us-ascii" do
    part = Mail.parse("Subject: x\n\nhi")
    part.content_type.value.should eq "text/plain"
    part.content_type.charset.should eq "us-ascii"
    part.text?.should be_true
  end
end

describe Mail::Writer do
  it "writes a text message with 8bit UTF-8 and folds long headers" do
    message = Mail::Message.new
    message.subject = "Päy rent " + "word " * 20
    message.date = Time.utc(2026, 9, 23, 14, 46, 49)
    message.text = "Line one\nLine two"
    output = message.to_s

    output.should start_with("Subject: Päy rent word word")
    output.should contain("\nMIME-Version: 1.0\nContent-Type: text/plain; charset=utf-8\n")
    output.each_line(&.size.should(be <= 78))
    output.should contain("Date: Wed, 23 Sep 2026 14:46:49 +0000\n")
    output.should contain("Content-Type: text/plain; charset=utf-8\nContent-Transfer-Encoding: 7bit\n\nLine one\nLine two\n")

    copy = Mail.parse(output)
    copy.subject.should eq message.subject
    copy.text.should eq "Line one\nLine two\n"
  end

  it "uses 7bit for ASCII text, CRLF when asked, and encoded words for ascii_headers" do
    message = Mail::Message.new
    message.subject = "Päy"
    message.text = "plain\n"
    io = IO::Memory.new
    message.write(io, eol: "\r\n", ascii_headers: true)
    output = io.to_s
    output.should contain("Subject: =?UTF-8?B?UMOkeQ==?=\r\n")
    output.should contain("Content-Transfer-Encoding: 7bit\r\n\r\nplain\r\n")
    Mail.parse(output).subject.should eq "Päy"
  end

  it "round-trips attachments as base64 bytes and keeps declared encodings" do
    message = Mail::Message.new
    message.subject = "With files"
    message.text = "See attached.\n"
    binary = Bytes.new(300) { |index| (index % 256).to_u8 }
    message.attach("data.bin", binary)
    message.attach("notes.txt", "a note\n", "text/plain; charset=utf-8")
    qp = Mail::Part.new
    qp.headers["Content-Type"] = "text/plain; charset=utf-8"
    qp.headers["Content-Transfer-Encoding"] = "quoted-printable"
    qp.body = "Café = good\n".to_slice
    message.add_part(qp)

    output = message.to_s
    output.should contain("Content-Type: multipart/mixed; boundary=")
    output.lines.select(&.starts_with?("Content-Transfer-Encoding")).should eq [
      "Content-Transfer-Encoding: 7bit",
      "Content-Transfer-Encoding: base64",
      "Content-Transfer-Encoding: 7bit",
      "Content-Transfer-Encoding: quoted-printable",
    ]
    output.should contain("Caf=C3=A9 =3D good\n")
    output.each_line(&.size.should(be <= 78))

    copy = Mail.parse(output)
    copy.text.should eq "See attached.\n"
    copy.attachments.map(&.filename).should eq ["data.bin", "notes.txt"]
    copy.attachments[0].body.should eq binary
    copy.attachments[0].content_type.value.should eq "application/octet-stream"
    copy.attachments[1].text.should eq "a note\n"
    copy.parts.should_not(be_nil)[3].text.should eq "Café = good\n"
  end

  it "base64-encodes text that is not clean, and keeps an empty body empty" do
    part = Mail::Part.new
    part.headers["Content-Type"] = "text/plain"
    part.body = "has\0nul".to_slice
    Mail::Writer.choose_encoding(part, nil).should eq "base64"
    part.body = ("x" * 999 + "\n").to_slice
    Mail::Writer.choose_encoding(part, nil).should eq "base64"
    part.body = ("x" * 998 + "\r\n").to_slice
    Mail::Writer.choose_encoding(part, nil).should eq "7bit"
    part.body = "bare\rcr".to_slice
    Mail::Writer.choose_encoding(part, nil).should eq "base64"
    part.body = Bytes.empty
    Mail::Writer.choose_encoding(part, nil).should eq "7bit"
    part.to_s.should eq "MIME-Version: 1.0\nContent-Type: text/plain\nContent-Transfer-Encoding: 7bit\n\n"
  end

  it "does not mutate the message while writing" do
    message = Mail::Message.new
    message.text = "x"
    message.attach("a.txt", "a", "text/plain")
    before = message.headers.map { |name, value| {name, value} }
    message.to_s
    message.headers.map { |name, value| {name, value} }.should eq before
    message.headers.has?("MIME-Version").should be_false
  end
end

describe Mail::Part do
  it "promotes a leaf to multipart, moving its content headers into the first part" do
    message = Mail::Message.new
    message.subject = "S"
    message.text = "body"
    message.make_multipart!
    parts = message.parts.should_not be_nil
    parts.size.should eq 1
    parts[0].text.should eq "body"
    parts[0].content_type.value.should eq "text/plain"
    message.content_type.multipart?.should be_true
    message.content_type.boundary.should_not be_nil
    # The boundary holds tspecials, so it must be written as a quoted string.
    message.headers["Content-Type"].should match(/\Amultipart\/mixed; boundary="=_[0-9a-f]{24}"\z/)
    message.headers["Subject"].should eq "S"
    message.body.should be_empty
  end

  it "makes an empty multipart from an empty leaf and accepts parts" do
    message = Mail::Message.new
    message.make_multipart!("alternative")
    message.parts.should_not(be_nil).should be_empty
    message.content_type.value.should eq "multipart/alternative"
    message.add_part(Mail::Part.new).should be_a(Mail::Part)
    message.parts.should_not(be_nil).size.should eq 1
  end

  it "keeps a non-plain text type on text= and forces utf-8" do
    part = Mail::Part.new
    part.headers["Content-Type"] = "text/html; charset=latin1"
    part.text = "<p>hi</p>"
    part.content_type.to_s.should eq "text/html; charset=utf-8"
    part.headers["Content-Type"] = "image/png"
    part.text = "oops"
    part.content_type.value.should eq "text/plain"
  end
end

describe Mail::Message do
  it "brackets ids and splits references" do
    message = Mail::Message.new
    message.message_id = "a@b"
    message.message_id.should eq "<a@b>"
    message.in_reply_to = "<c@d>"
    message.in_reply_to.should eq "<c@d>"
    message.references = ["x@y", "<z@w>"]
    message.headers["References"].should eq "<x@y> <z@w>"
    message.references.should eq ["<x@y>", "<z@w>"]
    message.references = [] of String
    message.headers.has?("References").should be_false
    message.date = nil
    message.headers.has?("Date").should be_false
  end

  it "generates message ids" do
    id = Mail.message_id("example.org")
    id.should match(/\A<\d+\.[0-9a-f]{16}@example\.org>\z/)
    Mail.message_id.should_not eq Mail.message_id
  end
end
