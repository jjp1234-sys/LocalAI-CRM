# Leads saved before phone_e164 existed have a phone but no normalised copy,
# so a returning customer's WhatsApp message wouldn't find their lead. Fill it
# in with the same normalisation the app uses.
class BackfillLeadPhoneE164 < ActiveRecord::Migration[8.1]
  class MigrationLead < ActiveRecord::Base
    self.table_name = "leads"
  end

  def up
    MigrationLead.where(phone_e164: nil).where.not(phone: nil).find_each do |lead|
      e164 = PhoneNumber.normalize(lead.phone)
      lead.update_columns(phone_e164: e164) if e164
    end
  end

  def down
    # Nothing to undo: the column is derived from phone.
  end
end
