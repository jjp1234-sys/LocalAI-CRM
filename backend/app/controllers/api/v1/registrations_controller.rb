module Api
  module V1
    # POST /api/v1/signup: creates a user, their business, and makes them its
    # owner, all or nothing. Responds with a login token.
    class RegistrationsController < BaseController
      allow_unauthenticated only: :create
      rate_limit to: 5, within: 1.hour, only: :create, by: -> { client_ip },
        store: Rails.application.config.x.rate_limit_store, with: -> { rate_limited }

      def create
        user = User.new(params.expect(user: [ :name, :email_address, :password ]))
        business_params = params.expect(business: [ :name, :time_zone ])
        business = Business.new(business_params)
        business.slug = Business.unique_slug_for(business.name)
        session = nil

        # Don't say that an email is already registered: that would let anyone
        # check which addresses have accounts. (A generic failure still differs
        # from a success; fully closing this needs email verification, where
        # signup always answers "check your inbox".)
        if User.exists?(email_address: user.email_address)
          return render_error(:unprocessable_content, "signup_failed", "Couldn't create an account with those details")
        end

        ActiveRecord::Base.transaction do
          user.save!
          business.save!
          Membership.create!(business: business, user: user, role: "owner")
          session = user.sessions.create!(ip_address: client_ip, user_agent: request.user_agent.to_s.first(255))
        end

        render_data({
          token: session.token,
          expires_at: session.expires_at,
          user: Serializers.user(user),
          business: Serializers.business(business)
        }, status: :created)
      end
    end
  end
end
