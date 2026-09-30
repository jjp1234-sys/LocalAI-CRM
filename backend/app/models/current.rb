# Per-request state: who is making the request and which business it's for.
# Rails resets these automatically at the end of every request.
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :business, :membership
end
