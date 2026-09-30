module Assistant
  # The morning message: the CRM's "home screen", on WhatsApp.
  #   today's appointments, follow-ups due (and overdue), new leads,
  #   leads going cold, and (for owners/admins) money won this month.
  # Owners and admins see the whole business; agents see what's theirs.
  # Empty sections are left out. Runs inside Tenant.with(business).
  class Digest
    COLD_AFTER = 3.days
    LIMIT = 5

    def initialize(business:, user:, now: Time.current)
      @business = business
      @user = user
      @zone = ActiveSupport::TimeZone[business.time_zone]
      @now = now.in_time_zone(@zone)
      @manager = Membership.find_by(user_id: user.id)&.at_least?(:admin)
    end

    def text
      sections = [ appointments, follow_ups, new_leads, going_cold, money ].compact
      header = "☀️ *#{@now.strftime("%A %b %-d")}*"
      return "#{header}\nNothing on today. ☕" if sections.empty?

      ([ header ] + sections).join("\n\n")
    end

    private

    def mine(scope, column = :assigned_user_id)
      @manager ? scope : scope.where(column => @user.id)
    end

    def appointments
      list = mine(Appointment.upcoming.where(starts_at: @now.beginning_of_day..@now.end_of_day)).includes(:lead).order(:starts_at).to_a
      return nil if list.empty?

      "📅 *Today*\n" + list.map { |a| "• #{a.starts_at.in_time_zone(@zone).strftime("%-l:%M%P")} #{a.lead.name} (#{a.kind.humanize.downcase})" }.join("\n")
    end

    def follow_ups
      list = FollowUp.open.where(assigned_user_id: @user.id, due_at: ..@now.end_of_day).includes(:lead).order(:due_at).limit(LIMIT).to_a
      return nil if list.empty?

      lines = list.map do |f|
        overdue = f.due_at < @now.beginning_of_day ? " _(overdue)_" : ""
        "• #{f.body}#{f.lead ? " · #{f.lead.name}" : ""}#{overdue}"
      end
      "✅ *To do*\n#{lines.join("\n")}"
    end

    def new_leads
      list = mine(Lead.active.where(created_at: (@now - 24.hours)..)).order(created_at: :desc).to_a
      return nil if list.empty?

      names = list.first(LIMIT).map(&:name).join(", ")
      more = list.size > LIMIT ? " and #{list.size - LIMIT} more" : ""
      "🆕 *#{list.size} new lead#{"s" if list.size > 1}*: #{names}#{more}"
    end

    def going_cold
      list = mine(Lead.active.where(status: %w[new contacted qualified]).where(last_activity_at: ...(@now - COLD_AFTER)))
        .order(:last_activity_at).limit(3).to_a
      return nil if list.empty?

      "🧊 *Going cold*\n" + list.map { |l| "• #{l.name} · quiet #{((@now - l.last_activity_at) / 1.day).floor} days" }.join("\n")
    end

    def money
      return nil unless @manager

      won_leads = Lead.where(won_at: @now.beginning_of_month..)
      won = won_leads.sum(:value_cents)
      costs = JobCost.where(lead_id: won_leads.select(:id)).sum(:amount_cents)
      pipeline = Lead.active.where(status: %w[new contacted qualified appointment]).sum(:value_cents)
      return nil if won.zero? && pipeline.zero?

      profit = costs.positive? ? " (profit #{Money.format(won - costs)})" : ""
      collected = Payment.status_paid.where(paid_at: @now.beginning_of_month..).sum(:amount_cents)
      cash = collected.positive? ? "\n💵 Collected this month: #{Money.format(collected)}" : ""
      "💰 Won this month: *#{Money.format(won)}*#{profit} · In play: #{Money.format(pipeline)}#{cash}"
    end
  end
end
