# Sends each team member with a phone their morning digest, once a day, at
# DIGEST_AT in their business's time zone. Scheduled every 15 minutes
# (config/recurring.yml); each run sends to whoever hasn't had today's yet.
class DailyDigestJob < ApplicationJob
  queue_as :default

  DIGEST_AT = [ 7, 30 ].freeze
  # Past this, a missed digest is skipped rather than sent late.
  LATEST_HOUR = 11

  def perform(now: Time.current)
    Business.joins(:channel_accounts).merge(ChannelAccount.active).distinct.find_each do |business|
      local = now.in_time_zone(business.time_zone)
      next if local.hour >= LATEST_HOUR || [ local.hour, local.min ].<=>(DIGEST_AT).negative?

      account = business.whatsapp_account
      Tenant.with(business) do
        User.joins(:memberships).where.not(phone: nil).find_each do |user|
          session = AssistantSession.for(user)
          next if session.state["digest_on"] == local.to_date.iso8601

          session.update!(state: session.state.merge("digest_on" => local.to_date.iso8601))
          OutboundMessage.queue!(account: account, to: user.phone, body: Assistant::Digest.new(business: business, user: user, now: now).text)
        end
      end
    end
  end
end
