module Whatsapp
  # Development and tests: nothing leaves the machine. The message is already
  # in outbound_messages, which is what the simulator page shows.
  class SimulatorTransport
    def deliver(_outbound)
      "sim.#{SecureRandom.hex(12)}"
    end
  end
end
