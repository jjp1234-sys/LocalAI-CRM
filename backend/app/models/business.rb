class Business < ApplicationRecord
  has_many :memberships, dependent: :restrict_with_error
  has_many :users, through: :memberships
  has_many :intake_keys, dependent: :restrict_with_error
  has_many :leads, dependent: :restrict_with_error
  has_many :conversations, dependent: :restrict_with_error
  has_many :appointments, dependent: :restrict_with_error
  has_many :activities, dependent: :restrict_with_error
  has_many :channel_accounts, dependent: :restrict_with_error

  # Used when a business hasn't written its own terms. Deliberately short and
  # generic: each business should replace it with terms their lawyer approves.
  DEFAULT_CONTRACT_TERMS = <<~TERMS.strip
    1. The Business will carry out the work listed above for the total shown.
    2. Any change to the work or price must be agreed in writing by both parties.
    3. Payment is due as agreed between the parties. Deposits, if any, are stated above.
    4. Either party may cancel before work begins by written notice.
    5. Both parties agree that signing electronically is as binding as signing on paper.

    (Template terms. Have them reviewed by a lawyer and replace them with your own.)
  TERMS

  # The number the business's WhatsApp messages go out from.
  def whatsapp_account
    channel_accounts.active.order(:created_at).first
  end

  normalizes :name, with: ->(name) { name.squish }
  normalizes :slug, with: ->(slug) { slug.strip.downcase }

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\z/, message: "must be 3-63 lowercase letters, digits or hyphens" }
  validates :default_tax_rate_bps, numericality: { only_integer: true, in: 0..3000 }
  validates :quote_valid_days, numericality: { only_integer: true, in: 1..365 }
  validates :contract_terms, length: { maximum: 50_000 }
  validates :payments_provider, inclusion: { in: %w[none simulator stripe] }
  validates :stripe_account_id, format: { with: /\Aacct_[A-Za-z0-9]+\z/ }, allow_nil: true
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name }.uniq }

  # Turns a business name into a unique URL-safe slug: "Bob's AV" -> "bob-s-av".
  def self.unique_slug_for(name)
    base = name.to_s.parameterize.first(50).presence || "business"
    base = base.ljust(3, "x")
    slug = base
    slug = "#{base}-#{SecureRandom.alphanumeric(6).downcase}" while exists?(slug: slug)
    slug
  end
end
