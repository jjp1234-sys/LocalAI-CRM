module Whatsapp
  # Sends an OutboundMessage somewhere and returns the provider's message ID.
  #   RetryableError  temporary (network trouble, Meta overloaded): try again later
  #   PermanentError  will never work as-is (bad number, outside the 24-hour window)
  module Transport
    class RetryableError < StandardError; end
    class PermanentError < StandardError; end

    def self.for(account)
      case account.provider
      when "whatsapp_cloud" then CloudApiTransport.new(account)
      when "simulator" then SimulatorTransport.new
      else raise ArgumentError, "unknown provider #{account.provider}"
      end
    end
  end
end
