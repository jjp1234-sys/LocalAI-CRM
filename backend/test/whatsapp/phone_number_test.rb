require "test_helper"

class PhoneNumberTest < ActiveSupport::TestCase
  test "US numbers in common formats" do
    [
      "305-555-0100", "(305) 555 0100", "305.555.0100", "3055550100",
      "13055550100", "1 305 555 0100", "1-305-555-0100", "+1 305 555 0100", "+13055550100", "  +1 (305) 555-0100  "
    ].each do |raw|
      assert_equal "+13055550100", PhoneNumber.normalize(raw), raw.inspect
    end
  end

  test "international numbers keep their country code" do
    assert_equal "+442079460958", PhoneNumber.normalize("+44 20 7946 0958")
    assert_equal "+5511987654321", PhoneNumber.normalize("+55 (11) 98765-4321")
    assert_equal "+34612345678", PhoneNumber.normalize("+34612345678")
  end

  test "junk is nil" do
    [ nil, "", "   ", "abc", "+", "12345", "+0123456789", "+1234567890123456", "call me" ].each do |raw|
      assert_nil PhoneNumber.normalize(raw), raw.inspect
    end
  end

  test "a number without a country code that isn't a full US number is nil" do
    # The module assumes US/Canada when there's no "+". A 7-digit local number
    # isn't a complete US number, so it shouldn't become "+5550100" (Brazil).
    assert_nil PhoneNumber.normalize("555-0100")
  end
end
