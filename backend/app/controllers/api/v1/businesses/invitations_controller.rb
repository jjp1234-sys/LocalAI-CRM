module Api
  module V1
    module Businesses
      # Invitations to join this business (admins and owners).
      #
      # POST answers 202 with the same body whether or not the email has an
      # account, so it can't be used to discover who is registered. Nothing
      # about the invitee is revealed until they accept.
      class InvitationsController < BaseController
        require_role :admin

        def index
          records, meta = paginate(Invitation.pending.order(created_at: :desc, id: :desc))
          render_data records.map { |i| Serializers.invitation(i) }, meta: meta
        end

        def create
          attrs = params.expect(invitation: [ :email_address, :role ])
          role = attrs[:role].presence || "agent"
          if role == "owner" && !Current.membership.owner?
            raise ErrorHandling::Forbidden, "Only an owner can invite an owner"
          end

          email = attrs[:email_address].to_s.strip.downcase
          # Re-inviting someone replaces their open invitation.
          Invitation.open.where(email_address: email).find_each(&:revoke!)
          invitation = Invitation.create!(email_address: email, role: role, invited_by: Current.user)
          render_data Serializers.invitation(invitation), status: :accepted
        end

        def destroy
          Invitation.open.find(params[:id]).revoke!
          head :no_content
        end
      end
    end
  end
end
