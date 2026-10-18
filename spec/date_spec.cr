require "./spec_helper"

private CET2 = Time::Location.fixed(2 * 3600)

describe Mail::Date do
  describe ".format" do
    it "writes the RFC 5322 date-time with the time's own offset" do
      Mail::Date.format(Time.utc(2026, 9, 23, 14, 46, 49)).should eq "Wed, 23 Sep 2026 14:46:49 +0000"
      Mail::Date.format(Time.local(2026, 9, 23, 16, 46, 49, location: CET2)).should eq "Wed, 23 Sep 2026 16:46:49 +0200"
      Mail::Date.format(Time.local(2026, 1, 5, 8, 0, 0, location: Time::Location.fixed(-5 * 3600))).should eq "Mon, 05 Jan 2026 08:00:00 -0500"
    end

    it "zero-pads day, hour, minute and second" do
      Mail::Date.format(Time.utc(2026, 3, 1, 0, 0, 0)).should eq "Sun, 01 Mar 2026 00:00:00 +0000"
    end
  end

  describe ".parse" do
    it "reads the full form, keeping the offset" do
      time = Mail::Date.parse("Wed, 23 Sep 2026 16:46:49 +0200").should_not be_nil
      time.should eq Time.utc(2026, 9, 23, 14, 46, 49)
      time.offset.should eq 7200
    end

    it "reads a negative offset" do
      time = Mail::Date.parse("Mon, 05 Jan 2026 08:00:00 -0500").should_not be_nil
      time.should eq Time.utc(2026, 1, 5, 13, 0, 0)
      time.offset.should eq -5 * 3600
    end

    it "tolerates a missing weekday" do
      Mail::Date.parse("23 Sep 2026 16:46:49 +0200").should eq Time.utc(2026, 9, 23, 14, 46, 49)
    end

    it "tolerates missing seconds" do
      Mail::Date.parse("Wed, 23 Sep 2026 16:46 +0200").should eq Time.utc(2026, 9, 23, 14, 46, 0)
      Mail::Date.parse("23 Sep 2026 16:46 +0200").should eq Time.utc(2026, 9, 23, 14, 46, 0)
    end

    it "assumes UTC when there is no zone" do
      time = Mail::Date.parse("Wed, 23 Sep 2026 16:46:49").should_not be_nil
      time.should eq Time.utc(2026, 9, 23, 16, 46, 49)
      time.offset.should eq 0
      Mail::Date.parse("23 Sep 2026 16:46:49").should eq Time.utc(2026, 9, 23, 16, 46, 49)
    end

    it "drops comments such as a zone name in parentheses" do
      Mail::Date.parse("Wed, 23 Sep 2026 16:46:49 +0200 (CEST)").should eq Time.utc(2026, 9, 23, 14, 46, 49)
      Mail::Date.parse("Wed, 23 Sep 2026 16:46:49 +0000 (UTC)").should eq Time.utc(2026, 9, 23, 16, 46, 49)
    end

    it "collapses stray whitespace and line breaks" do
      Mail::Date.parse("  Wed,   23 Sep 2026\r\n 16:46:49   +0200 ").should eq Time.utc(2026, 9, 23, 14, 46, 49)
    end

    it "accepts an RFC 3339 timestamp as a last resort" do
      time = Mail::Date.parse("2026-09-23T16:46:49+02:00").should_not be_nil
      time.should eq Time.utc(2026, 9, 23, 14, 46, 49)
      Mail::Date.parse("2026-09-23T14:46:49Z").should eq Time.utc(2026, 9, 23, 14, 46, 49)
    end

    it "reads an obsolete two- or three-digit year" do
      Mail::Date.parse("Wed, 23 Sep 26 16:46:49 +0200").should eq Time.utc(2026, 9, 23, 14, 46, 49)
      Mail::Date.parse("Wed, 23 Sep 99 16:46:49 +0200").should eq Time.utc(1999, 9, 23, 14, 46, 49)
      Mail::Date.parse("Wed, 23 Sep 126 16:46:49 +0200").should eq Time.utc(2026, 9, 23, 14, 46, 49)
    end

    it "is nil for a date that does not exist" do
      Mail::Date.parse("Tue, 31 Feb 2026 16:46:49 +0200").should be_nil
      Mail::Date.parse("Wed, 23 Sep 2026 25:46:49 +0200").should be_nil
    end

    it "is nil for nothing, blanks, a bare comment or garbage" do
      Mail::Date.parse(nil).should be_nil
      Mail::Date.parse("").should be_nil
      Mail::Date.parse("   ").should be_nil
      Mail::Date.parse("(CEST)").should be_nil
      Mail::Date.parse("not a date").should be_nil
      Mail::Date.parse("Wed, 23 Sep 2026").should be_nil
      Mail::Date.parse("23/09/2026 16:46").should be_nil
    end

    it "round-trips through format" do
      {
        Time.utc(2026, 9, 23, 14, 46, 49),
        Time.local(2026, 9, 23, 16, 46, 49, location: CET2),
        Time.local(2026, 12, 31, 23, 59, 59, location: Time::Location.fixed(-8 * 3600)),
      }.each do |time|
        parsed = Mail::Date.parse(Mail::Date.format(time)).should_not be_nil
        parsed.should eq time
        parsed.offset.should eq time.offset
      end
    end
  end
end
