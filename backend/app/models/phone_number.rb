# Normalises phone numbers to E.164 (+13055550100), the format WhatsApp uses,
# so "305-555-0100", "(305) 555 0100" and "13055550100" are the same person.
#
# Numbers without a country code are assumed to be US/Canada (+1). That's
# right for the first businesses; other countries need a real library
# (e.g. phonelib) and the business's country.
module PhoneNumber
  module_function

  def normalize(raw)
    return nil if raw.blank?

    digits = raw.to_s.gsub(/\D/, "")
    e164 =
      if raw.to_s.strip.start_with?("+") then "+#{digits}"
      elsif digits.length == 10 then "+1#{digits}"
      elsif digits.length == 11 && digits.start_with?("1") then "+#{digits}"
      else return nil # e.g. a 7-digit local number: not enough to know who it is
      end
    e164.match?(/\A\+[1-9]\d{6,14}\z/) ? e164 : nil
  end
end
