# mail-rfc5322-mime

Internet messages for Crystal: RFC 5322 headers and MIME bodies (RFC 2045 to
2047, 2231, 6532). Reading is lenient, so real-world mail parses without
surprises. Writing is strict, so what you produce is accepted everywhere.

The library deals with the message structure only. It does not parse
addresses, speak SMTP or IMAP, or read mailboxes; see
[maildir.cr](https://github.com/crystallabs/maildir.cr) for the last one.

## Installation

```yaml
dependencies:
  mail-rfc5322-mime:
    github: crystallabs/mail-rfc5322-mime.cr
```

## Reading

```crystal
require "mail-rfc5322-mime"

message = Mail.parse(File.read(path))

message.subject            # => "Pay rent"            (encoded words decoded)
message.date               # => Time, or nil when the header is missing or odd
message.from               # => "taskman <taskman@localhost>", the raw string
message.message_id         # => "<1790174809.M884992P94253Q1.host@taskman>"
message.headers["Keywords"]        # first value, case-insensitive name
message.headers.all("Received")    # every value, in order

message.text               # the first text part that is not an attachment, as UTF-8
message.attachments        # the leaf parts that carry a file name
message.attachments.first.filename      # RFC 2231 names decoded
message.attachments.first.body          # Bytes, transfer decoding undone
message.attachments.first.content_type  # => Mail::ContentType
```

A message is a `Mail::Part` with header accessors. A part is either a leaf
(`body : Bytes`, decoded) or a multipart (`parts : Array(Part)`). `leaves`
and `each_leaf` walk the tree.

What lenient means here:

* LF and CRLF line endings are both fine, and so is a mixture.
* Folded header lines are joined; a header line without a colon is skipped.
* Encoded words in any charset iconv knows are decoded; an unknown charset is
  read as UTF-8 with invalid bytes replaced.
* base64 and quoted-printable bodies are decoded; one that does not decode is
  kept verbatim.
* A multipart whose boundary never appears is read as a plain leaf, so no
  content is lost. A missing closing delimiter is tolerated.
* Nothing raises on malformed input.

## Writing

```crystal
message = Mail::Message.new
message.from = "taskman <taskman@localhost>"
message.subject = "Pay rent"
message.date = Time.local
message.message_id = Mail.message_id("taskman")
message.headers["X-Taskman-Due"] = "2026-09-30"
message.text = "Transfer the rent.\n"
message.attach("receipt.pdf", pdf_bytes, "application/pdf")
message.attach("notes.txt", "a note\n", "text/plain; charset=utf-8")

File.write(path, message.to_s)            # LF line endings, for files on disk
message.write(socket, eol: "\r\n")        # CRLF for the wire
message.write(io, ascii_headers: true)    # encoded words instead of raw UTF-8
```

What strict means here:

* Headers are folded at 78 columns on whitespace. Values are written as UTF-8
  (RFC 6532) unless `ascii_headers` is set, which turns the non-ASCII words
  of a value into `=?UTF-8?B?...?=` encoded words and leaves the ASCII ones,
  such as addresses, as they are.
* `MIME-Version: 1.0` is added to the top-level message if missing.
* Content that is clean text, whatever its media type (no NUL, no bare CR,
  no line over 998 bytes), is written 7bit or 8bit with line breaks normalized
  to the chosen `eol` (a final line break is added if missing). Anything else
  is base64 in 76-column lines. A
  declared `base64` or `quoted-printable` encoding is honoured.
* Multipart boundaries are generated when absent.
* Writing never mutates the message.

`text=` on a leaf makes it `text/plain; charset=utf-8` (an existing `text/*`
type is kept). `attach` or `add_part` on a leaf first turns it into
`multipart/mixed`, moving the former content into the first part.

## Building blocks

These are public and usable on their own:

* `Mail::Headers`: an ordered, case-insensitive header list with folding.
* `Mail::ContentType` and `Mail::ParameterizedValue`: `type/subtype;
  name=value` headers, with RFC 2231 continuations and charset-tagged values.
* `Mail::EncodedWord`: RFC 2047 decode and UTF-8 B encode.
* `Mail::QuotedPrintable`: body and Q-encoding variants.
* `Mail::Charset`: bytes in a named charset to a UTF-8 string, forgivingly.
* `Mail::Date`: RFC 5322 date format and lenient parse.

## Development

```sh
shards install
crystal spec
bin/ameba
```

## Contributing

1. Fork it (<https://github.com/crystallabs/mail-rfc5322-mime.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Davor Ocelic](https://github.com/docelic) - creator and maintainer

## License

Copyright (C) 2026 Davor Ocelic.

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License, version 3, as
published by the Free Software Foundation. See [LICENSE](LICENSE) for the
full text.
