# frozen_string_literal: true

require 'chrono_model/patches/db_console'

Rails::DBConsole.prepend ChronoModel::Patches::DBConsole::DbConfig
