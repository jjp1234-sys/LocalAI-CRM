# WhatsApp as the product's front end.
#
#   channel_accounts   a business's WhatsApp number (or a local simulator)
#   inbound_events     every message/status Meta sends us, stored once
#   outbound_messages  an outbox: every message we send, until it's confirmed sent
#   assistant_sessions what a staff member's chat with the assistant is in the
#                      middle of (the last list shown, a booking awaiting "yes")
#
# Staff are recognised by their phone number, so users get one.
class AddWhatsapp < ActiveRecord::Migration[8.1]
  NEW_TENANT_TABLES = %w[channel_accounts inbound_events outbound_messages assistant_sessions].freeze

  def up
    add_column :users, :phone, :string
    add_index :users, :phone, unique: true, where: "phone IS NOT NULL"
    # E.164: a plus sign then up to 15 digits, e.g. +13055550100.
    add_check_constraint :users, "phone ~ '^\\+[1-9][0-9]{6,14}$'", name: "users_phone_e164"

    remove_check_constraint :leads, name: "leads_source_valid"
    add_check_constraint :leads, "source IN ('website', 'facebook', 'instagram', 'google', 'whatsapp', 'referral', 'phone', 'walk_in', 'manual', 'other')", name: "leads_source_valid"
    remove_check_constraint :conversations, name: "conversations_channel_valid"
    add_check_constraint :conversations, "channel IN ('sms', 'whatsapp', 'web_chat', 'email', 'phone', 'facebook', 'instagram', 'other')", name: "conversations_channel_valid"
    add_column :leads, :phone_e164, :string
    add_index :leads, [ :business_id, :phone_e164 ]

    create_table :channel_accounts, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true
      t.string :provider, null: false
      # Meta's ID for the phone number. Webhooks name it, which is how an
      # incoming message is matched to a business.
      t.string :phone_number_id, null: false
      t.string :display_phone, null: false
      # Encrypted by Active Record encryption (see ChannelAccount).
      t.text :access_token
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index :phone_number_id, unique: true
      t.index [ :id, :business_id ], unique: true
      t.check_constraint "provider IN ('whatsapp_cloud', 'simulator')", name: "channel_accounts_provider_valid"
    end

    create_table :inbound_events, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :channel_account_id, null: false
      t.string :kind, null: false
      # Meta's ID for the message or status update. Unique, so a webhook
      # Meta delivers twice is only processed once.
      t.string :provider_event_id, null: false
      t.string :from_phone
      t.jsonb :payload, null: false, default: {}
      t.datetime :processed_at
      t.string :error
      t.datetime :created_at, null: false
      t.index :provider_event_id, unique: true
      t.index [ :business_id, :from_phone, :created_at ]
      t.check_constraint "kind IN ('message', 'status')", name: "inbound_events_kind_valid"
    end
    add_foreign_key :inbound_events, :channel_accounts, column: [ :channel_account_id, :business_id ], primary_key: [ :id, :business_id ]

    create_table :outbound_messages, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :channel_account_id, null: false
      # Set when this is a reply to a customer, linking it to the CRM's record.
      t.references :message, type: :uuid, foreign_key: { on_delete: :nullify }
      # The lead this message is about. When a staff member swipe-replies to
      # a notification, WhatsApp names the notification, and this says which
      # customer they meant.
      t.uuid :lead_id
      t.string :to_phone, null: false
      t.string :kind, null: false, default: "text"
      t.text :body, null: false
      t.jsonb :buttons, null: false, default: []
      t.string :status, null: false, default: "pending"
      t.string :provider_message_id
      t.integer :attempts, null: false, default: 0
      t.string :last_error
      t.datetime :sent_at
      t.timestamps
      t.index :provider_message_id, unique: true, where: "provider_message_id IS NOT NULL"
      t.index [ :status, :created_at ]
      t.index [ :business_id, :to_phone, :created_at ]
      t.check_constraint "kind IN ('text', 'buttons')", name: "outbound_messages_kind_valid"
      t.check_constraint "status IN ('pending', 'sent', 'delivered', 'read', 'failed')", name: "outbound_messages_status_valid"
      t.check_constraint "char_length(body) BETWEEN 1 AND 4096", name: "outbound_messages_body_length"
    end
    add_foreign_key :outbound_messages, :channel_accounts, column: [ :channel_account_id, :business_id ], primary_key: [ :id, :business_id ]
    add_foreign_key :outbound_messages, :leads, column: [ :lead_id, :business_id ], primary_key: [ :id, :business_id ]

    create_table :assistant_sessions, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.jsonb :state, null: false, default: {}
      t.timestamps
      t.index [ :business_id, :user_id ], unique: true
    end

    NEW_TENANT_TABLES.each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute <<~SQL
        CREATE POLICY #{table}_tenant ON #{table}
          USING (business_id = current_business_id())
          WITH CHECK (business_id = current_business_id())
      SQL
    end
  end

  def down
    NEW_TENANT_TABLES.reverse_each do |table|
      execute "DROP POLICY IF EXISTS #{table}_tenant ON #{table}"
      drop_table table
    end
    remove_index :leads, [ :business_id, :phone_e164 ]
    remove_column :leads, :phone_e164
    remove_check_constraint :conversations, name: "conversations_channel_valid"
    add_check_constraint :conversations, "channel IN ('sms', 'web_chat', 'email', 'phone', 'facebook', 'instagram', 'other')", name: "conversations_channel_valid"
    remove_check_constraint :leads, name: "leads_source_valid"
    add_check_constraint :leads, "source IN ('website', 'facebook', 'instagram', 'google', 'referral', 'phone', 'walk_in', 'manual', 'other')", name: "leads_source_valid"
    remove_check_constraint :users, name: "users_phone_e164"
    remove_index :users, :phone
    remove_column :users, :phone
  end
end
