module Assistant
  # Turns what people type into a time, in the business's time zone:
  #   "thu 2pm", "thursday at 2:30pm", "tomorrow 9", "today noon", "10/3 3pm",
  #   "2pm" (today, or tomorrow if that's already past), "next fri 10am"
  #
  # A time is required; the day is optional. Hours without am/pm are read as
  # business hours: 8-11 morning, 12-7 afternoon/evening. Returns nil for
  # anything it doesn't understand, so the caller can ask again rather than
  # guess.
  module WhenParser
    DAYS = {
      "sun" => 0, "sunday" => 0, "mon" => 1, "monday" => 1,
      "tue" => 2, "tues" => 2, "tuesday" => 2, "wed" => 3, "weds" => 3, "wednesday" => 3,
      "thu" => 4, "thur" => 4, "thurs" => 4, "thursday" => 4,
      "fri" => 5, "friday" => 5, "sat" => 6, "saturday" => 6
    }.freeze
    TIME = /(?<![\d\/:])(?<clock>noon|midnight|(?<hour>\d{1,2})(?::(?<min>\d{2}))?\s*(?<ampm>am|pm|a|p)?)(?![\d\/:])/

    module_function

    def parse(text, zone:, now: Time.current)
      zone = ActiveSupport::TimeZone[zone] || ActiveSupport::TimeZone["UTC"]
      now = now.in_time_zone(zone)
      input = text.to_s.downcase.tr(",.", "  ").squeeze(" ").strip

      match = input.to_enum(:scan, TIME).map { Regexp.last_match }.last
      return nil unless match

      hour, minute = clock(match)
      return nil unless hour

      rest = (input[0...match.begin(0)] + " " + input[match.end(0)..]).split - %w[at on]
      date = day(rest, now)
      return nil unless date

      time = zone.local(date.year, date.month, date.day, hour, minute)
      # A bare time that's already passed today means tomorrow.
      time += 1.day if rest.empty? && time <= now
      # "thu 2pm" said on a Thursday afternoon means next Thursday.
      time += 7.days if DAYS.key?(rest.last) && time <= now
      time
    end

    def clock(match)
      return [ 12, 0 ] if match[:clock] == "noon"
      return [ 0, 0 ] if match[:clock] == "midnight"

      hour = match[:hour].to_i
      minute = match[:min].to_i
      return nil if minute > 59

      case match[:ampm]
      when "am", "a" then hour = 0 if hour == 12
      when "pm", "p" then hour += 12 if hour < 12
      else
        return nil if hour > 23
        hour += 12 if hour.between?(1, 7)
      end
      return nil unless hour.between?(0, 23) && (match[:ampm].nil? || match[:hour].to_i.between?(1, 12))

      [ hour, minute ]
    end

    def day(words, now)
      explicit_next = words.delete("next")
      return now.to_date if words.empty? || words == [ "today" ]
      return nil unless words.size == 1

      word = words.first
      return now.to_date + 1 if %w[tomorrow tmrw tmr].include?(word)

      if (weekday = DAYS[word])
        ahead = (weekday - now.wday) % 7
        ahead = 7 if ahead.zero? && explicit_next
        return now.to_date + ahead
      end

      if (m = word.match(/\A(\d{1,2})\/(\d{1,2})\z/))
        date = Date.new(now.year, m[1].to_i, m[2].to_i) rescue nil
        return nil unless date

        return date < now.to_date ? date.next_year : date
      end

      nil
    end
  end
end
