# The outbox. Every WhatsApp message we send is written here first, then sent
# by DeliverOutboundMessageJob. If sending fails, the row stays "pending" (or
# "failed", with the reason) instead of the message silently vanishing.
class OutboundMessage < ApplicationRecord
  include TenantOwned

  STATUS_ORDER = %w[pending sent delivered read].freeze
  MAX_BUTTONS = 3 # WhatsApp's limit for reply buttons

  belongs_to :channel_account
  belongs_to :lead, optional: true
  belongs_to :message, optional: true

  enum :status, %w[pending sent delivered read failed].index_by(&:itself), prefix: true, validate: true
  enum :kind, %w[text buttons].index_by(&:itself), prefix: true, validate: true

  validates :to_phone, presence: true
  validates :body, presence: true, length: { maximum: 4096 }
  validate :buttons_shape

  after_create_commit { DeliverOutboundMessageJob.perform_later(id) }

  # Queue a message. buttons: [{ id: "confirm:abc", title: "Yes" }, ...]
  def self.queue!(account:, to:, body:, buttons: [], lead: nil, message: nil)
    create!(
      channel_account: account, to_phone: to, body: body.to_s.first(4096),
      kind: buttons.any? ? "buttons" : "text", buttons: buttons, lead: lead, message: message
    )
  end

  # Meta's status updates can arrive out of order; never move backwards
  # (a late "sent" mustn't overwrite "read").
  def advance_status!(new_status, error: nil)
    if new_status == "failed"
      update!(status: "failed", last_error: error.to_s.first(500))
    elsif STATUS_ORDER.index(new_status).to_i > STATUS_ORDER.index(status).to_i
      update!(status: new_status)
    end
  end

  private

  def buttons_shape
    return if buttons.blank?

    valid = buttons.is_a?(Array) && buttons.size <= MAX_BUTTONS &&
      buttons.all? { |b| b.is_a?(Hash) && b["id"].present? && b["title"].to_s.length.between?(1, 20) }
    errors.add(:buttons, "must be up to #{MAX_BUTTONS} buttons with an id and a 1-20 character title") unless valid
  end
end
