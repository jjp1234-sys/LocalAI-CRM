module Payments
  # Creates a hosted checkout page for a Payment and returns { id:, url: }.
  # Temporary failures raise RetryableError; the customer can just click Pay again.
  module Provider
    class Error < StandardError; end

    def self.for(payment)
      case payment.provider
      when "stripe" then StripeProvider.new(payment.business)
      when "simulator" then SimulatorProvider.new
      else raise Error, "no payment provider"
      end
    end
  end
end
