# The agreement for a job: the business's terms plus the accepted quote,
# frozen into one text (body) when it's created, so later edits to the
# business's terms don't change contracts already sent.
#
# The customer signs on a private page by typing their name and agreeing to
# sign electronically. We record when, from which IP and browser, and a
# SHA-256 of the exact text signed. After that a database trigger refuses any
# change to the row.
class Contract < ApplicationRecord
  include TenantOwned
  include Tracked
  include PublicLink

  URL_PREFIX = "c"

  belongs_to :lead
  belongs_to :quote, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :status, %w[draft sent signed void].index_by(&:itself), prefix: true, validate: true

  tracks_values_of :status

  validates :body, presence: true, length: { maximum: 100_000 }
  validate { errors.add(:lead, "must belong to the same business") if lead && lead.business_id != business_id }

  def label = "C-#{number}"

  def self.build_body(business:, lead:, quote:)
    zone = ActiveSupport::TimeZone[business.time_zone]
    lines = []
    lines << "AGREEMENT #{"FOR QUOTE #{quote.label}" if quote}".strip
    lines << "Date: #{zone.today.strftime("%B %-d, %Y")}"
    lines << ""
    lines << "Between #{business.name} (\"the Business\") and #{lead.name} (\"the Customer\")."
    if quote
      lines << ""
      lines << "WORK AND PRICE"
      quote.items.each do |item|
        qty = item.quantity == item.quantity.to_i ? item.quantity.to_i : item.quantity
        lines << "- #{item.description}: #{qty} x #{Money.format(item.unit_price_cents)} = #{Money.format(item.amount_cents)}"
      end
      lines << "Subtotal: #{Money.format(quote.subtotal_cents)}"
      lines << "Tax (#{quote.tax_rate_bps / 100.0}%): #{Money.format(quote.tax_cents)}" if quote.tax_rate_bps.positive?
      lines << "Total: #{Money.format(quote.total_cents)}"
      lines << "Deposit due on signing: #{Money.format(quote.deposit_amount_cents)}" if quote.deposit_amount_cents
    end
    lines << ""
    lines << "TERMS"
    lines << (business.contract_terms.presence || Business::DEFAULT_CONTRACT_TERMS)
    lines.join("\n")
  end

  def send!
    update!(status: "sent", sent_at: sent_at || Time.current) if status_draft? || status_sent?
  end

  # Called from the customer's page. Returns false if it can't be signed.
  def sign!(name:, consent:, ip:, user_agent:)
    return false unless status_sent? && consent && name.to_s.squish.length.between?(2, 120)

    transaction do
      update!(
        status: "signed", signed_at: Time.current, signer_name: name.to_s.squish,
        signer_ip: ip.to_s.first(64), signer_user_agent: user_agent.to_s.first(255),
        signed_body_sha256: OpenSSL::Digest::SHA256.hexdigest(body)
      )
      value = quote&.total_cents || lead.value_cents
      lead.update!(status: "won", value_cents: value)
      request_deposit
    end
    true
  end

  # The deposit request created when this contract was signed, if any.
  def deposit_payment
    Payment.where(contract_id: id, kind: "deposit").where.not(status: "cancelled").first
  end

  def void!
    update!(status: "void") unless status_signed?
  end

  private

  # If the quote asks for a deposit and the business takes payments, signing
  # creates the payment request; the signed page then shows a Pay button.
  def request_deposit
    amount = quote&.deposit_amount_cents
    return unless amount && amount >= Payment::MIN_CENTS && business.payments_provider != "none"

    Payment.create!(lead: lead, quote: quote, contract: self, kind: "deposit",
      description: "Deposit for #{quote.label}", amount_cents: amount)
  end
end
