require "test_helper"

class MoneyTest < ActiveSupport::TestCase
  test "parses what people type into cents" do
    { "4500" => 450_000, "$4,500" => 450_000, "4500.5" => 450_050, "$12.99" => 1_299, "12k" => 1_200_000, "1,234,567" => 123_456_700 }.each do |text, cents|
      assert_equal cents, Money.parse(text), text
    end
  end

  test "rejects what isn't an amount" do
    [ nil, "", "lots", "4,50", "12.345", "-5", "$", "1e6" ].each { |text| assert_nil Money.parse(text), text.inspect }
  end

  test "formats cents as dollars" do
    assert_equal "$4,500", Money.format(450_000)
    assert_equal "$0", Money.format(0)
    assert_equal "$12.99", Money.format(1_299)
    assert_equal "$1,234,567.05", Money.format(123_456_705)
  end
end
