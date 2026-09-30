# Money is stored as whole cents (integers), never floats, so amounts add up
# exactly. These turn what people type into cents, and cents into "$4,500".
module Money
  module_function

  # "4500", "$4,500", "4500.50", "4.5k" -> cents. nil if it isn't an amount.
  def parse(text)
    m = text.to_s.strip.downcase.match(/\A\$?\s*(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?\s*(k)?\z/)
    return nil unless m

    dollars = m[1].delete(",").to_i
    cents = m[2].to_s.ljust(2, "0").to_i
    total = dollars * 100 + cents
    total *= 1000 if m[3]
    total
  end

  def format(cents)
    dollars, rem = cents.to_i.divmod(100)
    whole = dollars.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    rem.zero? ? "$#{whole}" : "$#{whole}.#{rem.to_s.rjust(2, "0")}"
  end
end
