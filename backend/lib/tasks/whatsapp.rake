namespace :whatsapp do
  desc "Re-queue WhatsApp work whose job was lost (run on a schedule, e.g. every 5 minutes)"
  task redeliver: :environment do
    # Incoming messages stored but never processed (the job was lost to a
    # restart, or enqueueing failed). Ones that gave up with an error need a
    # person to look at them, so they're left alone.
    inbound = InboundEvent.where(processed_at: nil, error: nil).where(created_at: ...2.minutes.ago).pluck(:id)
    inbound.each { |id| ProcessInboundEventJob.perform_later(id) }

    # Outgoing messages still waiting to be sent.
    outbound = OutboundMessage.where(status: "pending").where(created_at: ...2.minutes.ago).pluck(:id)
    outbound.each { |id| DeliverOutboundMessageJob.perform_later(id) }

    puts "Re-queued #{inbound.size} incoming and #{outbound.size} outgoing"
  end
end
