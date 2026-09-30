# Sends one OutboundMessage through its account's transport.
#
# The row is locked while sending, so two copies of this job can't both send
# it. Temporary failures (network, Meta overloaded) are retried with growing
# waits; permanent ones (bad number, outside the 24-hour window) mark the
# message failed with the reason. Unexpected errors also mark it failed rather
# than risk sending twice. Anything still "pending" is re-queued by the
# `whatsapp:redeliver` sweeper.
class DeliverOutboundMessageJob < ApplicationJob
  queue_as :default
  retry_on Whatsapp::Transport::RetryableError, wait: :polynomially_longer, attempts: 6 do |job, error|
    OutboundMessage.where(id: job.arguments.first, status: "pending")
      .update_all(status: "failed", last_error: "gave up: #{error.message}".first(500), updated_at: Time.current)
  end

  def perform(outbound_id)
    business = OutboundMessage.find_by(id: outbound_id)&.business
    return unless business

    retry_later = nil
    Tenant.with(business) do
      outbound = OutboundMessage.lock.find(outbound_id)
      next unless outbound.status_pending?

      outbound.increment!(:attempts)
      begin
        provider_id = outbound.channel_account.transport.deliver(outbound)
        outbound.update!(status: "sent", provider_message_id: provider_id, sent_at: Time.current, last_error: nil)
      rescue Whatsapp::Transport::PermanentError => e
        outbound.update!(status: "failed", last_error: e.message.first(500))
      rescue Whatsapp::Transport::RetryableError => e
        # Save the attempt and the reason first, then raise outside the
        # transaction so the retry doesn't roll them back.
        outbound.update!(last_error: e.message.first(500))
        retry_later = e
      rescue StandardError => e
        # Anything unexpected: we can't tell whether Meta got the message, so
        # retrying risks sending it twice (or forever). Stop and say why.
        outbound.update!(status: "failed", last_error: "unexpected #{e.class}: #{e.message}".first(500))
        Rails.logger.error("Outbound #{outbound.id} failed: #{e.class}: #{e.message}")
      end
    end
    raise retry_later if retry_later
  end
end
