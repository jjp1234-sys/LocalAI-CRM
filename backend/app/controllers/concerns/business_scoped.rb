# For endpoints under /api/v1/businesses/:business_id/...
#
# 1. Finds the current user's membership in that business. Not a member, or
#    no such business: 404, the same answer either way, so the response
#    doesn't confirm whether a business exists.
# 2. Runs the rest of the request inside Tenant.with, so the database only
#    lets it see and change that business's rows.
module BusinessScoped
  extend ActiveSupport::Concern

  included do
    before_action :load_membership
    around_action :within_business
  end

  class_methods do
    # Limits some or all actions to members with at least this role.
    #   require_role :admin, only: [:create, :destroy]
    def require_role(role, **options)
      before_action(**options) { require_role!(role) }
    end
  end

  private

  def business_id_param
    params.require(:business_id)
  end

  def load_membership
    membership = Current.user.memberships.includes(:business).find_by(business_id: business_id_param)
    raise ActiveRecord::RecordNotFound unless membership

    Current.membership = membership
    Current.business = membership.business
  end

  def within_business(&action)
    Tenant.with(Current.business, &action)
  end

  def require_role!(role)
    unless Current.membership.at_least?(role)
      raise ErrorHandling::Forbidden, "This needs the #{role} role or higher"
    end
  end
end
