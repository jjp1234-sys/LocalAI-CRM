# Something Meta told us: a message someone sent to a business's number, or a
# status update on a message we sent. Stored once per Meta ID, then processed
# by ProcessInboundEventJob.
class InboundEvent < ApplicationRecord
  include TenantOwned

  belongs_to :channel_account

  def processed?
    processed_at.present?
  end

  # The message's text, or a button's ID if the person tapped a button.
  def text
    case payload["type"]
    when "text" then payload.dig("text", "body").to_s
    when "interactive" then payload.dig("interactive", "button_reply", "title").to_s
    when "button" then payload.dig("button", "text").to_s
    else ""
    end
  end

  def button_id
    payload.dig("interactive", "button_reply", "id") if payload["type"] == "interactive"
  end

  # Set when the person used WhatsApp's "reply" on one of our messages.
  def replying_to
    payload.dig("context", "id")
  end

  def profile_name
    payload["profile_name"].to_s.squish.first(120).presence
  end

  # Photos, voice notes etc. aren't handled yet; this names what was sent.
  def unsupported_type
    payload["type"] unless %w[text interactive button].include?(payload["type"])
  end
end
