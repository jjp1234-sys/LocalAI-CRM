module Whatsapp
  # Sends a message to a customer on WhatsApp and records it in the CRM.
  #
  # WhatsApp only lets a business message someone within 24 hours of their
  # last message (outside that it needs an approved template). That depends
  # on when the customer last wrote, not on whether our conversation is still
  # open, so this uses their most recent WhatsApp conversation either way.
  # Returns false when it can't send, so callers can tell the team instead.
  # Runs inside Tenant.with(business).
  module CustomerMessenger
    WINDOW = 24.hours

    module_function

    def conversation(lead)
      lead.conversations.where(channel: "whatsapp").order(Arel.sql("last_message_at DESC NULLS LAST"), created_at: :desc).first
    end

    def last_heard_at(lead)
      Message.joins(:conversation)
        .where(conversations: { lead_id: lead.id, channel: "whatsapp" }, direction: "inbound")
        .maximum(:created_at)
    end

    def can_message?(lead)
      lead.phone_e164.present? && conversation(lead).present? && (last_heard_at(lead)&.>= WINDOW.ago)
    end

    # sender_user: set for a team member's reply; nil for automatic messages.
    def tell(lead, text, sender_user: nil)
      account = Business.find(lead.business_id).whatsapp_account
      return false unless account && can_message?(lead)

      message = conversation(lead).messages.create!(
        body: text, direction: "outbound", sender_kind: sender_user ? "staff" : "system", sender_user: sender_user
      )
      OutboundMessage.queue!(account: account, to: lead.phone_e164, body: text, lead: lead, message: message)
      true
    end
  end
end
