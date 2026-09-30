# Writes an Activity row whenever a record is created or updated, so every
# change has a who and a when. It runs inside the same transaction as the
# change itself: if the log entry can't be written, the change is rolled back.
#
# Models list which attributes to log with their values. Other changed
# attributes are logged by name only, which keeps customer contact details
# from being copied into the log.
module Tracked
  extend ActiveSupport::Concern

  IGNORED = %w[id business_id created_at updated_at last_activity_at last_message_at last_used_at].freeze

  class_methods do
    def tracks_values_of(*attributes)
      @tracked_value_attributes = attributes.map(&:to_s)
    end

    def tracked_value_attributes
      @tracked_value_attributes || []
    end
  end

  included do
    after_create { record_activity("created") }
    after_update { record_activity("updated") if (saved_changes.keys - IGNORED).any? }
  end

  private

  def record_activity(action)
    changed = saved_changes.except(*IGNORED)
    values = changed.slice(*self.class.tracked_value_attributes)
    Activity.create!(
      business_id: business_id,
      actor_user: Current.user,
      subject: self,
      action: action,
      details: { changes: values, changed_fields: changed.keys.sort }
    )
  end
end
