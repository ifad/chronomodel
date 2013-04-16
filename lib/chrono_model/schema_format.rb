# h/t http://stackoverflow.com/questions/4698467
#
Rails.application.config.active_record.schema_format = :sql

# Clear Rails' ones
%w( db:structure:dump db:structure:load ).each {|t| Rake::Task[t].clear }

# Make schema:dump and schema:load invoke structure:dump and structure:load
Rake::Task['db:schema:dump'].clear.enhance(['environment']) do
  Rake::Task['db:structure:dump'].invoke
end

Rake::Task['db:schema:load'].clear.enhance(['environment']) do
  Rake::Task['db:structure:load'].invoke
end
