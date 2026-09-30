module Api
  module V1
    class BaseController < ApplicationController
      private

      # The client's IP address, for rate limiting and session records.
      #
      # Rails' request.remote_ip believes an X-Forwarded-For header from
      # anyone. With no proxy in front, a client could send a different fake
      # IP on every request and never hit a per-IP limit. So the header is
      # only honoured when the connection itself comes from a trusted proxy
      # (config.action_dispatch.trusted_proxies, which defaults to loopback
      # and private-network addresses).
      def client_ip
        peer = request.remote_addr.to_s
        from_proxy = begin
          address = IPAddr.new(peer)
          trusted_proxies.any? { |proxy| proxy.is_a?(IPAddr) ? proxy.include?(address) : proxy === peer }
        rescue IPAddr::Error
          false
        end
        from_proxy ? request.remote_ip : peer
      end

      def trusted_proxies
        Array(Rails.application.config.action_dispatch.trusted_proxies.presence || ActionDispatch::RemoteIp::TRUSTED_PROXIES)
      end

      def rate_limit_store
        Rails.application.config.x.rate_limit_store
      end

      def rate_limited
        render_error :too_many_requests, "rate_limited", "Too many requests. Try again shortly."
      end
    end
  end
end
