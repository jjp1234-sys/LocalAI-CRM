# Sends each follow-up that has come due to its assigned team member on
# WhatsApp, once, with "Done" and "Tomorrow 9am" buttons. Scheduled every
# minute (config/recurring.yml).
class FollowUpRemindersJob < ApplicationJob
  queue_as :default

  def perform
    # Finding what's due crosses businesses, so it runs outside Tenant.with;
    # everything after that happens inside the owning business.
    FollowUp.awaiting_reminder.distinct.pluck(:business_id).each do |business_id|
      business = Business.find(business_id)
      account = business.whatsapp_account
      next unless account

      Tenant.with(business) do
        FollowUp.awaiting_reminder.lock("FOR UPDATE SKIP LOCKED").includes(:lead, :assigned_user).find_each do |follow_up|
          remind(account, follow_up)
        end
      end
    end
  end

  private

  def remind(account, follow_up)
    follow_up.update_columns(reminded_at: Time.current)
    phone = follow_up.assigned_user.phone
    return unless phone

    about = follow_up.lead ? "\nAbout: *#{follow_up.lead.name}*" : ""
    OutboundMessage.queue!(
      account: account, to: phone, lead: follow_up.lead,
      body: "⏰ Reminder: #{follow_up.body}#{about}",
      buttons: [
        { "id" => "fudone:#{follow_up.id}", "title" => "Done" },
        { "id" => "futomorrow:#{follow_up.id}", "title" => "Tomorrow 9am" }
      ]
    )
  end
end
