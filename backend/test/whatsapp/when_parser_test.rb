require "test_helper"

class WhenParserTest < ActiveSupport::TestCase
  NY = "America/New_York"

  def ny(*args)
    ActiveSupport::TimeZone[NY].local(*args)
  end

  # Monday 5 October 2026, 10:00 in New York.
  def monday_morning
    ny(2026, 10, 5, 10, 0)
  end

  def parse(text, now: monday_morning, zone: NY)
    Assistant::WhenParser.parse(text, zone: zone, now: now)
  end

  test "weekday and time" do
    assert_equal ny(2026, 10, 8, 14, 0), parse("thu 2pm")
    assert_equal ny(2026, 10, 8, 14, 30), parse("thursday at 2:30pm")
    assert_equal ny(2026, 10, 8, 14, 0), parse("Thu, 2 PM")
    assert_equal ny(2026, 10, 9, 9, 15), parse("fri 9:15am")
  end

  test "tomorrow and today" do
    assert_equal ny(2026, 10, 6, 9, 0), parse("tomorrow 9")
    assert_equal ny(2026, 10, 6, 9, 0), parse("tomorrow at 9am")
    assert_equal ny(2026, 10, 5, 12, 0), parse("today noon")
    assert_equal ny(2026, 10, 6, 0, 0), parse("tomorrow midnight")
  end

  test "month/day dates, rolling a past date to next year" do
    assert_equal ny(2026, 10, 9, 15, 0), parse("10/9 3pm")
    assert_equal ny(2027, 10, 3, 15, 0), parse("10/3 3pm")
    assert_equal ny(2026, 10, 5, 15, 0), parse("10/5 3pm")
  end

  test "a bare time means today, or tomorrow once it has passed" do
    assert_equal ny(2026, 10, 5, 14, 0), parse("2pm")
    assert_equal ny(2026, 10, 5, 14, 0), parse("at 2pm")
    assert_equal ny(2026, 10, 6, 14, 0), parse("2pm", now: ny(2026, 10, 5, 15, 0))
    assert_equal ny(2026, 10, 6, 14, 0), parse("2pm", now: ny(2026, 10, 5, 14, 0))
  end

  test "today's weekday with a time already passed means next week" do
    assert_equal ny(2026, 10, 12, 9, 0), parse("mon 9am")
    assert_equal ny(2026, 10, 5, 11, 0), parse("mon 11am")
  end

  test "next weekday" do
    assert_equal ny(2026, 10, 9, 10, 0), parse("next fri 10am")
    assert_equal ny(2026, 10, 12, 11, 0), parse("next mon 11am")
  end

  test "hours without am/pm are read as business hours" do
    { 8 => 8, 9 => 9, 10 => 10, 11 => 11, 12 => 12, 1 => 13, 2 => 14, 5 => 17, 7 => 19 }.each do |typed, hour|
      assert_equal ny(2026, 10, 6, hour, 0), parse("tomorrow #{typed}"), "tomorrow #{typed}"
    end
    assert_equal ny(2026, 10, 6, 19, 30), parse("tomorrow 7:30")
  end

  test "am and pm edge cases" do
    assert_equal ny(2026, 10, 6, 0, 0), parse("tomorrow 12am")
    assert_equal ny(2026, 10, 6, 12, 0), parse("tomorrow 12pm")
    assert_equal ny(2026, 10, 6, 21, 0), parse("tomorrow 9pm")
    assert_equal ny(2026, 10, 6, 15, 0), parse("tomorrow 3p")
  end

  test "24-hour times" do
    assert_equal ny(2026, 10, 6, 14, 0), parse("tomorrow 14:00")
    assert_equal ny(2026, 10, 8, 16, 45), parse("thu 16:45")
    assert_equal ny(2026, 10, 6, 0, 30), parse("tomorrow 0:30")
  end

  test "returns nil for anything it doesn't understand" do
    [
      "13pm", "0pm", "2:75pm", "blah 2pm", "", "   ", "thu", "tomorrow", "2/30 3pm", "13/1 3pm",
      "tomorrow 25:00", "thu fri 2pm", "next week 2pm", "hello"
    ].each do |text|
      assert_nil parse(text), text.inspect
    end
    assert_nil parse(nil)
  end

  test "uses the business's time zone" do
    now = Time.utc(2026, 10, 6, 2, 0) # Monday 22:00 in New York, Tuesday 02:00 in UTC

    new_york = parse("today 11pm", now: now, zone: NY)
    assert_equal Time.utc(2026, 10, 6, 3, 0), new_york
    assert_equal NY, new_york.time_zone.tzinfo.name

    utc = parse("today 11pm", now: now, zone: "UTC")
    assert_equal Time.utc(2026, 10, 6, 23, 0), utc

    assert_equal Time.utc(2026, 10, 6, 13, 0), parse("tomorrow 9am", now: now, zone: NY)
    assert_equal Time.utc(2026, 10, 7, 9, 0), parse("tomorrow 9am", now: now, zone: "UTC")
  end

  test "handles daylight saving time" do
    # Clocks go back on 1 November 2026, so 9am on the 2nd is 14:00 UTC.
    assert_equal Time.utc(2026, 11, 2, 14, 0), parse("11/2 9am")
    assert_equal Time.utc(2026, 10, 30, 13, 0), parse("10/30 9am")
  end

  test "an unknown time zone falls back to UTC" do
    assert_equal Time.utc(2026, 10, 6, 9, 0), parse("tomorrow 9am", now: Time.utc(2026, 10, 5, 12), zone: "Mars/Olympus")
  end

  test "defaults to the current time" do
    travel_to ny(2026, 10, 5, 15, 0) do
      assert_equal ny(2026, 10, 6, 14, 0), Assistant::WhenParser.parse("2pm", zone: NY)
      assert_equal ny(2026, 10, 12, 14, 0), Assistant::WhenParser.parse("mon 2pm", zone: NY)
    end
  end
end
