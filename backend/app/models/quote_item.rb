class QuoteItem < ApplicationRecord
  include TenantOwned

  belongs_to :quote

  normalizes :description, with: ->(v) { v.squish }
  validates :description, presence: true, length: { maximum: 300 }
  validates :quantity, numericality: { greater_than: 0, less_than_or_equal_to: 100_000 }
  validates :unit_price_cents, numericality: { only_integer: true, in: 0..10_000_000_000 }
  validate { errors.add(:quote, "can no longer be changed") if quote && !quote.editable? }

  def amount_cents
    (quantity * unit_price_cents).round
  end
end
