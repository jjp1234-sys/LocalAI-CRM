module Whatsapp
  # Decides what an incoming event is, and hands it on. Runs inside
  # Tenant.with(business) for the business that owns the number.
  #
  #   status update          -> update the outbox row it's about
  #   message from staff     -> the assistant (commands like "leads")
  #   message from anyone    -> the customer inbox (becomes a lead + conversation)
  #
  # "Staff" means a member of THIS business whose saved phone matches the
  # sender. Being staff at a different business makes you a customer here.
  class Router
    def initialize(event)
      @event = event
      @account = event.channel_account
    end

    def call
      if @event.kind == "status"
        apply_status
      elsif (staff = staff_member)
        Assistant::Commands.new(account: @account, user: staff, event: @event).call
      else
        CustomerInbox.new(account: @account, event: @event).call
      end
    end

    private

    def staff_member
      return nil if @event.from_phone.blank?

      User.joins(:memberships)
        .where(memberships: { business_id: @event.business_id })
        .find_by(phone: @event.from_phone)
    end

    def apply_status
      outbound = OutboundMessage.find_by(provider_message_id: @event.payload["id"].to_s)
      return unless outbound

      error = Array(@event.payload["errors"]).map { |e| e["title"] || e["message"] }.compact.join("; ")
      outbound.advance_status!(@event.payload["status"].to_s, error: error.presence)
    end
  end
end
