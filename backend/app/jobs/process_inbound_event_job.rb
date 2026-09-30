# Handles one stored InboundEvent: routes it to the customer inbox, the
# assistant, or the outbox status tracker.
#
# The event row is locked while it's processed and marked done in the same
# transaction, so a message is acted on exactly once even if this job runs
# twice. On an error everything rolls back and the job retries.
class ProcessInboundEventJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    InboundEvent.where(id: job.arguments.first).update_all(error: "#{error.class}: #{error.message}".first(500))
  end

  def perform(event_id)
    business = InboundEvent.find_by(id: event_id)&.business
    return unless business

    Tenant.with(business) do
      event = InboundEvent.lock.find(event_id)
      next if event.processed?

      Whatsapp::Router.new(event).call
      event.update!(processed_at: Time.current, error: nil)
    end
  end
end
