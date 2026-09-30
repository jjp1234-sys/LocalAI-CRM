module Api
  module V1
    # GET /api/v1/me: the logged-in user and the businesses they belong to.
    class MeController < BaseController
      def show
        memberships = Current.user.memberships.includes(:business).order(:created_at)
        render_data({
          user: Serializers.user(Current.user),
          memberships: memberships.map { |m| { role: m.role, business: Serializers.business(m.business) } }
        })
      end
    end
  end
end
