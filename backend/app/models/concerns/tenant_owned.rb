# For records that belong to one business. Fills in the business from the
# current request and refuses to save a record for any other business.
# Row-level security enforces the same rule in the database; this catches the
# mistake earlier with a clearer error.
module TenantOwned
  extend ActiveSupport::Concern

  included do
    belongs_to :business
    attr_readonly :business_id

    before_validation { self.business ||= Current.business }
    validate :business_matches_current, if: -> { Current.business }
  end

  private

  def business_matches_current
    errors.add(:business, "doesn't match the current business") if business_id != Current.business.id
  end

  # Checks that a user this record points at is a member of its business.
  def validate_member(attribute)
    user_id = public_send("#{attribute}_id")
    return if user_id.nil?

    unless Membership.exists?(business_id: business_id, user_id: user_id)
      errors.add(attribute, "must be a member of this business")
    end
  end
end
