## this file overrides the default initialization of assets.rb

Rails.application.config.assets.version = "1.0" if Rails.version < '7.0'
