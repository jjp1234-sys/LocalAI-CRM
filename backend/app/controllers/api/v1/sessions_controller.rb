module Api
  module V1
    # POST   /api/v1/session  log in: { email_address, password } -> token
    # DELETE /api/v1/session  log out: the token used for this request stops working
    class SessionsController < BaseController
      allow_unauthenticated only: :create
      # Two limits: per IP address, and per email address (so a botnet with
      # many IPs still can't try thousands of passwords on one account).
      rate_limit to: 10, within: 3.minutes, only: :create, name: "login-ip", by: -> { client_ip },
        store: Rails.application.config.x.rate_limit_store, with: -> { rate_limited }
      rate_limit to: 10, within: 15.minutes, only: :create, name: "login-email",
        by: -> { params[:email_address].to_s.strip.downcase },
        store: Rails.application.config.x.rate_limit_store, with: -> { rate_limited }

      def create
        user = User.authenticate_by(
          email_address: params.require(:email_address).to_s,
          password: params.require(:password).to_s
        )
        # Same message whether the email or the password was wrong, so the
        # response doesn't reveal which emails have accounts.
        return render_error(:unauthorized, "invalid_credentials", "Invalid email or password") unless user

        session = user.sessions.create!(ip_address: client_ip, user_agent: request.user_agent.to_s.first(255))
        render_data({ token: session.token, expires_at: session.expires_at, user: Serializers.user(user) }, status: :created)
      end

      def destroy
        Current.session.destroy!
        head :no_content
      end
    end
  end
end
