# Requires a valid login token on every request unless a controller opts out
# with `allow_unauthenticated`. Clients send the token they got from
# POST /api/v1/session as:  Authorization: Bearer fds_...
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate!
  end

  class_methods do
    def allow_unauthenticated(**options)
      skip_before_action :authenticate!, **options
    end
  end

  private

  def authenticate!
    session = Session.authenticate(bearer_token)
    if session
      Current.session = session
      Current.user = session.user
    else
      response.headers["WWW-Authenticate"] = 'Bearer realm="api"'
      render_error :unauthorized, "unauthorized", "A valid login token is required"
    end
  end

  def bearer_token
    request.authorization.to_s[/\ABearer\s+(\S+)\z/, 1]
  end
end
