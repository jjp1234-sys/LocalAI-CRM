module Api
  module V1
    module Businesses
      # The business's team. Everyone can see it; admins and owners manage it.
      # New people join by invitation (InvitationsController), never by being
      # added directly.
      #
      # Admins can't change or remove owners, and can't make anyone an owner.
      # Anyone can leave (remove their own membership). A business always
      # keeps at least one owner.
      class MembershipsController < BaseController
        require_role :admin, only: :update
        before_action :set_membership, only: [ :update, :destroy ]

        def index
          records, meta = paginate(Membership.includes(:user).order(:created_at, :id))
          render_data records.map { |m| Serializers.membership(m) }, meta: meta
        end

        def update
          role = params.expect(membership: [ :role ])[:role]
          guard_owner_role!(@membership.role)
          guard_owner_role!(role)
          @membership.update!(role: role)
          render_data Serializers.membership(@membership)
        end

        def destroy
          require_role!(:admin) unless @membership.user_id == Current.user.id
          guard_owner_role!(@membership.role) unless @membership.user_id == Current.user.id
          @membership.destroy!
          head :no_content
        end

        private

        def set_membership
          @membership = Membership.find(params[:id])
        end

        def guard_owner_role!(role)
          if role.to_s == "owner" && !Current.membership.owner?
            raise ErrorHandling::Forbidden, "Only an owner can manage owners"
          end
        end
      end
    end
  end
end
