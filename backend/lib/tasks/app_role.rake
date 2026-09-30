# Applies db/app_role.sql (the restricted role's permissions) after anything
# that builds or changes the schema. See that file for why it exists.
namespace :db do
  desc "Create the restricted app database role and grant its permissions"
  task app_role: :environment do
    sql = Rails.root.join("db/app_role.sql").read
    ActiveRecord::Base.connection.execute(sql)
  end
end

%w[db:migrate db:schema:load db:prepare].each do |task_name|
  Rake::Task[task_name].enhance do
    Rake::Task["db:app_role"].reenable # returns false, so don't chain it with &&
    Rake::Task["db:app_role"].invoke
  end
end
