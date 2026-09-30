module Whatsapp
  # Who on the team hears about a lead, and telling them. Only current
  # members with a saved phone: the lead's assigned person if they qualify,
  # otherwise the owners and admins. Runs inside Tenant.with(business).
  module Team
    module_function

    def recipients(lead)
      members = User.joins(:memberships).where(memberships: { business_id: lead.business_id }).where.not(phone: nil)
      assigned = members.find_by(id: lead.assigned_user_id) if lead.assigned_user_id
      return [ assigned ] if assigned

      members.where(memberships: { role: %w[owner admin] })
    end

    def notify(lead, body)
      account = Business.find(lead.business_id).whatsapp_account
      return unless account

      recipients(lead).each { |user| OutboundMessage.queue!(account: account, to: user.phone, lead: lead, body: body) }
    end
  end
end
