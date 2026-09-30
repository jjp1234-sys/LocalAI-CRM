# The audit log. Written by the Tracked concern; never edited or deleted.
class Activity < ApplicationRecord
  include TenantOwned

  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true

  def readonly?
    persisted?
  end
end
