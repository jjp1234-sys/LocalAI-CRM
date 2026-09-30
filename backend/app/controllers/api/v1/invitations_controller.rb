module Api
  module V1
    # The logged-in user's own invitations, across businesses.
    #   GET  /api/v1/invitations              pending invitations for my email
    #   POST /api/v1/invitations/:id/accept   join the business
    #   POST /api/v1/invitations/:id/decline
    #
    # Looking invitations up happens outside any one business (the user isn't
    # a member yet), so it's always filtered to the user's own email address.
    # Accepting then runs inside Tenant.with for the inviting business.
    class InvitationsController < BaseController
      def index
        invitations = my_invitations.includes(:business).order(created_at: :desc)
        render_data(invitations.map { |i| Serializers.invitation(i).merge(business: { id: i.business.id, name: i.business.name }) })
      end

      def accept
        invitation = my_invitations.find(params[:id])
        Tenant.with(invitation.business) { invitation.accept!(Current.user) }
        render_data({ business: Serializers.business(invitation.business), role: invitation.role })
      end

      def decline
        invitation = my_invitations.find(params[:id])
        Tenant.with(invitation.business) { invitation.decline! }
        head :no_content
      end

      private

      def my_invitations
        Invitation.pending.where(email_address: Current.user.email_address)
      end
    end
  end
end
