# Turns records into the JSON the API returns. Each serializer lists its
# fields explicitly: adding a column to a table never exposes it by accident.
module Serializers
  module_function

  def user(user)
    { id: user.id, name: user.name, email_address: user.email_address }
  end

  def business(business)
    business.slice(:id, :name, :slug, :time_zone, :default_tax_rate_bps, :quote_valid_days, :contract_terms,
                   :payments_provider, :stripe_account_id, :created_at, :updated_at)
  end

  def membership(membership)
    {
      id: membership.id,
      role: membership.role,
      user: user(membership.user),
      created_at: membership.created_at
    }
  end

  def invitation(invitation)
    invitation.slice(:id, :email_address, :role, :expires_at, :created_at)
  end

  def intake_key(key)
    key.slice(:id, :name, :token_prefix, :last_used_at, :revoked_at, :created_at)
  end

  def lead(lead)
    lead.slice(
      :id, :name, :email, :phone, :need, :source, :status, :score, :external_id,
      :value_cents, :acquisition_cost_cents, :won_at,
      :assigned_user_id, :archived_at, :last_activity_at, :created_at, :updated_at
    )
  end

  def conversation(conversation)
    conversation.slice(
      :id, :lead_id, :channel, :status, :assigned_user_id, :last_message_at, :created_at, :updated_at
    )
  end

  def message(message)
    message.slice(:id, :conversation_id, :direction, :sender_kind, :sender_user_id, :body, :created_at)
  end

  def appointment(appointment)
    appointment.slice(
      :id, :lead_id, :assigned_user_id, :kind, :status, :starts_at, :ends_at,
      :location, :notes, :created_at, :updated_at
    )
  end

  def note(note)
    note.slice(:id, :lead_id, :author_user_id, :body, :created_at)
  end

  def follow_up(follow_up)
    follow_up.slice(
      :id, :lead_id, :assigned_user_id, :created_by_id, :body, :due_at,
      :reminded_at, :completed_at, :cancelled_at, :created_at, :updated_at
    )
  end

  def job_cost(cost)
    cost.slice(:id, :lead_id, :description, :amount_cents, :created_by_id, :created_at)
  end

  # Staff-facing: includes the customer link. Never includes the token digest.
  def quote(quote)
    quote.slice(:id, :lead_id, :number, :revision, :deposit_bps, :deposit_cents, :status, :tax_rate_bps, :notes, :valid_until, :sent_at, :viewed_at,
                :accepted_at, :accepted_name, :declined_at, :created_at, :updated_at).merge(
      label: quote.label, url: quote.public_url,
      subtotal_cents: quote.subtotal_cents, tax_cents: quote.tax_cents, total_cents: quote.total_cents,
      deposit_amount_cents: quote.deposit_amount_cents,
      items: quote.items.map { |i| i.slice(:id, :description, :quantity, :unit_price_cents).merge(amount_cents: i.amount_cents) }
    )
  end

  def contract(contract)
    contract.slice(:id, :lead_id, :quote_id, :number, :status, :body, :sent_at, :viewed_at, :signed_at,
                   :signer_name, :signed_body_sha256, :created_at, :updated_at).merge(label: contract.label, url: contract.public_url)
  end

  def payment(payment)
    payment.slice(:id, :lead_id, :quote_id, :contract_id, :kind, :description, :amount_cents, :currency,
                  :status, :provider, :paid_at, :created_at, :updated_at).merge(url: payment.public_url)
  end

  def activity(activity)
    activity.slice(:id, :subject_type, :subject_id, :action, :actor_user_id, :details, :created_at)
  end
end
