module Api
  module V1
    module Businesses
      # GET .../summary: the numbers a dashboard needs, computed from real data.
      class SummariesController < BaseController
        def show
          leads = Lead.active
          month_start = Time.current.in_time_zone(Current.business.time_zone).beginning_of_month
          render_data({
            leads_by_status: Lead::STATUSES.index_with(0).merge(leads.group(:status).count),
            new_leads_last_7_days: leads.where(created_at: 7.days.ago..).count,
            open_conversations: Conversation.status_open.count,
            upcoming_appointments: Appointment.upcoming.count,
            open_follow_ups: FollowUp.open.count,
            overdue_follow_ups: FollowUp.open.where(due_at: ...Time.current).count,
            # Money, in cents.
            pipeline_value_cents: leads.where(status: %w[new contacted qualified appointment]).sum(:value_cents),
            won_this_month_cents: Lead.where(won_at: month_start..).sum(:value_cents),
            collected_this_month_cents: Payment.status_paid.where(paid_at: month_start..).sum(:amount_cents),
            outstanding_payments_cents: Payment.status_pending.sum(:amount_cents),
            won_this_month_costs_cents: JobCost.where(lead_id: Lead.where(won_at: month_start..).select(:id)).sum(:amount_cents),
            by_source: by_source
          })
        end

        private

        # For each source: how many leads, how many won, what they earned and
        # what they cost. This is the "your leads from us made you $X" report.
        def by_source
          rows = Lead.group(:source).pluck(
            :source, Arel.sql("count(*)"), Arel.sql("count(*) FILTER (WHERE status = 'won')"),
            Arel.sql("coalesce(sum(value_cents) FILTER (WHERE status = 'won'), 0)"),
            Arel.sql("coalesce(sum(acquisition_cost_cents), 0)"),
            Arel.sql("coalesce(sum((SELECT sum(amount_cents) FROM job_costs jc WHERE jc.lead_id = leads.id)) FILTER (WHERE status = 'won'), 0)")
          )
          # Postgres returns sums as decimals; money here is whole cents.
          # profit = what won jobs earned, minus what they cost to do, minus
          # what the leads cost to get.
          rows.to_h do |source, count, won, revenue, cost, job_costs|
            [ source, { leads: count, won: won, revenue_cents: revenue.to_i, cost_cents: cost.to_i,
                        job_costs_cents: job_costs.to_i, profit_cents: revenue.to_i - job_costs.to_i - cost.to_i } ]
          end
        end
      end
    end
  end
end
