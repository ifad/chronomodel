# frozen_string_literal: true

require 'chrono_model/patches/db_console'

if Rails.version < '6.1'
  Rails::DBConsole.prepend ChronoModel::Patches::DBConsole::Config
else
  Rails::DBConsole.prepend ChronoModel::Patches::DBConsole::DbConfig
end
