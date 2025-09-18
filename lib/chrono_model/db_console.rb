# frozen_string_literal: true

require_relative 'patches/db_console'

`Rails::DBConsole`.prepend `ChronoModel::Patches::DBConsole::DbConfig`
