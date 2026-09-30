# A request for money from a customer: a deposit, the balance, or anything
# else. The customer opens its private link (/p/...) and pays through the
# business's payment provider. Once paid, a database trigger freezes it.
class Payment < ApplicationRecord
  include TenantOwned
  include Tracked
  include PublicLink

  URL_PREFIX = "p"
  MIN_CENTS = 50 # Stripe's minimum charge

  belongs_to :lead
  belongs_to :quote, optional: true
  belongs_to :contract, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :kind, %w[deposit balance other].index_by(&:itself), prefix: true, validate: true
  enum :status, %w[pending paid cancelled].index_by(&:itself), prefix: true, validate: true

  tracks_values_of :status, :amount_cents

  normalizes :description, with: ->(v) { v.squish }
  validates :description, presence: true, length: { maximum: 200 }
  validates :amount_cents, numericality: { only_integer: true, in: MIN_CENTS..10_000_000_000 }
  validates :provider, inclusion: { in: %w[simulator stripe], message: "isn't set up: this business can't take payments yet" }
  validate { errors.add(:lead, "must belong to the same business") if lead && lead.business_id != business_id }

  before_validation(on: :create) { self.provider ||= business&.payments_provider }

  # The provider's checkout page for this payment. Reuses a still-open one.
  def checkout_url!(return_url:)
    raise ArgumentError, "only pending payments can be paid" unless status_pending?
    return checkout_url if checkout_url.present?

    session = Payments::Provider.for(self).create_checkout(self, success_url: "#{return_url}?done=1", cancel_url: return_url)
    update!(provider_session_id: session[:id], checkout_url: session[:url])
    checkout_url
  end

  # The provider said the checkout expired: forget it so the next click makes a new one.
  def checkout_expired!
    update!(provider_session_id: nil, checkout_url: nil) if status_pending?
  end

  def cancel!
    update!(status: "cancelled") if status_pending?
  end
end
