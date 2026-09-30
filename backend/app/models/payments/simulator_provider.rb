module Payments
  # Development and tests: a pretend checkout (/dev/pay/<id>) that settles
  # through the same Payments::Settle code a real provider's webhook uses.
  class SimulatorProvider
    def create_checkout(_payment, success_url:, cancel_url:)
      id = "sim_cs_#{SecureRandom.hex(12)}"
      { id: id, url: "#{Rails.application.config.x.public_base_url}/dev/pay/#{id}?#{{ success: success_url, cancel: cancel_url }.to_query}" }
    end
  end
end
