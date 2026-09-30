# A priced list of work for one lead. Built as a draft, sent to the customer
# as a private link, and accepted (or declined) by them on that page.
# Accepting freezes it: a database trigger refuses any later change.
class Quote < ApplicationRecord
  include TenantOwned
  include Tracked
  include PublicLink

  URL_PREFIX = "q"

  belongs_to :lead
  belongs_to :created_by, class_name: "User", optional: true
  has_many :items, -> { order(:position, :created_at) }, class_name: "QuoteItem", dependent: :destroy

  enum :status, %w[draft sent accepted declined void].index_by(&:itself), prefix: true, validate: true

  tracks_values_of :status, :tax_rate_bps

  validates :tax_rate_bps, numericality: { only_integer: true, in: 0..3000 }
  validates :notes, length: { maximum: 5000 }
  validates :deposit_bps, numericality: { only_integer: true, in: 1..10_000 }, allow_nil: true
  validates :deposit_cents, numericality: { only_integer: true, in: 1..10_000_000_000 }, allow_nil: true
  validate { errors.add(:base, "Set a deposit as a percentage or an amount, not both") if deposit_bps && deposit_cents }
  validate { errors.add(:lead, "must belong to the same business") if lead && lead.business_id != business_id }

  before_validation(on: :create) do
    # The business's default rate, unless a rate (even 0%) was given.
    self.tax_rate_bps = business.default_tax_rate_bps if business && !attribute_changed?(:tax_rate_bps)
    self.valid_until ||= Time.current.in_time_zone(business.time_zone).to_date + business.quote_valid_days if business
  end

  def label = revision > 1 ? "Q-#{number} rev #{revision}" : "Q-#{number}"

  # A newer revision of this quote, if one has been made.
  def superseded_by
    Quote.where(number: number).where("revision > ?", revision).where.not(status: %w[draft void]).order(:revision).last
  end

  # Deposit: a percentage of the total (deposit_bps) or a fixed amount.
  def deposit_amount_cents
    return deposit_cents if deposit_cents
    return nil unless deposit_bps

    (total_cents * deposit_bps / 10_000.0).round
  end

  # A new draft copying this quote (items, tax, deposit, notes), with the same
  # number and the next revision. The original stays as it was: an accepted
  # quote is a record of what was agreed. An unaccepted one is withdrawn when
  # the revision is sent (see #send!).
  def revise!(by:)
    next_revision = Quote.where(number: number).maximum(:revision) + 1
    copy = Quote.create!(
      lead: lead, created_by: by, number: number, revision: next_revision,
      tax_rate_bps: tax_rate_bps, deposit_bps: deposit_bps, deposit_cents: deposit_cents, notes: notes
    )
    items.each { |i| copy.add_item!(description: i.description, quantity: i.quantity, unit_price_cents: i.unit_price_cents) }
    copy
  end

  # Drafts and sent quotes can still be changed; the customer always sees the
  # current version until they accept it.
  def editable?
    status_draft? || status_sent?
  end

  def expired?
    valid_until && valid_until < Time.current.in_time_zone(business.time_zone).to_date
  end

  def subtotal_cents = items.sum(&:amount_cents)
  def tax_cents = (subtotal_cents * tax_rate_bps / 10_000.0).round
  def total_cents = subtotal_cents + tax_cents

  def add_item!(description:, unit_price_cents:, quantity: 1)
    items.create!(description: description, unit_price_cents: unit_price_cents, quantity: quantity, position: items.size)
  end

  def send!
    if items.empty?
      errors.add(:base, "A quote needs at least one item")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      update!(status: "sent", sent_at: sent_at || Time.current)
      # Sending a revision withdraws earlier versions the customer hasn't accepted.
      Quote.where(number: number).where("revision < ?", revision).where(status: %w[draft sent]).find_each { |q| q.update!(status: "void") }
    end
  end

  # Called from the customer's page. Returns false if it can't be accepted.
  def accept!(name:, ip:)
    return false unless status_sent? && !expired? && name.to_s.squish.length.between?(2, 120)

    transaction do
      update!(status: "accepted", accepted_at: Time.current, accepted_name: name.to_s.squish, accepted_ip: ip.to_s.first(64))
      lead.update!(value_cents: total_cents, status: lead.status.in?(%w[new contacted]) ? "qualified" : lead.status)
    end
    true
  end

  def decline!
    return false unless status_sent?

    update!(status: "declined", declined_at: Time.current)
  end
end
