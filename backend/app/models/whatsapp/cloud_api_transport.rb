module Whatsapp
  # Meta's WhatsApp Cloud API.
  class CloudApiTransport
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    def initialize(account)
      @account = account
    end

    def deliver(outbound)
      version = Rails.application.config.x.whatsapp.graph_api_version
      uri = URI("https://graph.facebook.com/#{version}/#{@account.phone_number_id}/messages")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{@account.access_token}")
      request.body = JSON.generate(body_for(outbound))

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
      handle(response)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise Transport::RetryableError, "#{e.class}: #{e.message}"
    end

    private

    def body_for(outbound)
      base = { messaging_product: "whatsapp", to: outbound.to_phone.delete("+") }
      if outbound.kind_buttons?
        base.merge(type: "interactive", interactive: {
          type: "button", body: { text: outbound.body },
          action: { buttons: outbound.buttons.map { |b| { type: "reply", reply: { id: b["id"], title: b["title"] } } } }
        })
      else
        base.merge(type: "text", text: { body: outbound.body, preview_url: false })
      end
    end

    def handle(response)
      body = JSON.parse(response.body.to_s) rescue {}
      case response.code.to_i
      when 200..299
        body.dig("messages", 0, "id") || raise(Transport::PermanentError, "no message id in response")
      when 429, 500..599
        raise Transport::RetryableError, "HTTP #{response.code}: #{body.dig("error", "message")}"
      else
        # 4xx: bad number, expired token, outside the 24-hour window, etc.
        raise Transport::PermanentError, "HTTP #{response.code}: #{body.dig("error", "message")}".first(500)
      end
    end
  end
end
