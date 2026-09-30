# The everyday CRM pieces:
#   notes       free-text notes on a lead ("wants black speakers")
#   follow_ups  reminders ("call Sarah Friday 10am"), pushed on WhatsApp when due
#   leads.value_cents / won_at     what a deal is worth, and when it was won,
#                                  so revenue can be reported
#   leads.acquisition_cost_cents   what the lead cost (an ad, or a lead we
#                                  sold them), so "your leads made you $X" is
#                                  one query
# plus a "purchased" lead source for leads the business bought from us.
class AddNotesFollowUpsAndDealValue < ActiveRecord::Migration[8.1]
  SOURCES = %w[website facebook instagram google whatsapp referral phone walk_in manual purchased other].freeze

  def up
    add_column :leads, :value_cents, :bigint
    add_column :leads, :acquisition_cost_cents, :bigint
    add_column :leads, :won_at, :datetime
    add_check_constraint :leads, "value_cents IS NULL OR value_cents BETWEEN 0 AND 100000000000", name: "leads_value_range"
    add_check_constraint :leads, "acquisition_cost_cents IS NULL OR acquisition_cost_cents BETWEEN 0 AND 100000000000", name: "leads_cost_range"
    add_index :leads, [ :business_id, :won_at ]
    remove_check_constraint :leads, name: "leads_source_valid"
    add_check_constraint :leads, "source IN (#{SOURCES.map { |s| "'#{s}'" }.join(", ")})", name: "leads_source_valid"
    execute "UPDATE leads SET won_at = updated_at WHERE status = 'won' AND won_at IS NULL"

    # Notes are a record, like messages: added, never edited or deleted.
    create_table :notes, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :lead_id, null: false
      t.references :author_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :body, null: false
      t.datetime :created_at, null: false
      t.index [ :lead_id, :created_at ]
      t.check_constraint "char_length(body) BETWEEN 1 AND 5000", name: "notes_body_length"
    end
    add_foreign_key :notes, :leads, column: [ :lead_id, :business_id ], primary_key: [ :id, :business_id ]

    create_table :follow_ups, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      # Optional: "remind me to order cables" isn't about a lead.
      t.uuid :lead_id
      # Who gets reminded.
      t.references :assigned_user, type: :uuid, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :body, null: false
      t.datetime :due_at, null: false
      t.datetime :reminded_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.timestamps
      # The reminder sweep: due, not yet reminded, still open.
      t.index :due_at, where: "reminded_at IS NULL AND completed_at IS NULL AND cancelled_at IS NULL", name: "index_follow_ups_awaiting_reminder"
      t.index [ :business_id, :assigned_user_id, :due_at ]
      t.index :lead_id
      t.check_constraint "char_length(body) BETWEEN 1 AND 500", name: "follow_ups_body_length"
      t.check_constraint "NOT (completed_at IS NOT NULL AND cancelled_at IS NOT NULL)", name: "follow_ups_single_outcome"
    end
    add_foreign_key :follow_ups, :leads, column: [ :lead_id, :business_id ], primary_key: [ :id, :business_id ]

    %w[notes follow_ups].each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute <<~SQL
        CREATE POLICY #{table}_tenant ON #{table}
          USING (business_id = current_business_id())
          WITH CHECK (business_id = current_business_id())
      SQL
    end
  end

  def down
    %w[follow_ups notes].each do |table|
      execute "DROP POLICY IF EXISTS #{table}_tenant ON #{table}"
      drop_table table
    end
    remove_check_constraint :leads, name: "leads_source_valid"
    add_check_constraint :leads, "source IN (#{(SOURCES - %w[purchased]).map { |s| "'#{s}'" }.join(", ")})", name: "leads_source_valid"
    remove_index :leads, [ :business_id, :won_at ]
    remove_check_constraint :leads, name: "leads_cost_range"
    remove_check_constraint :leads, name: "leads_value_range"
    remove_column :leads, :won_at
    remove_column :leads, :acquisition_cost_cents
    remove_column :leads, :value_cents
  end
end
