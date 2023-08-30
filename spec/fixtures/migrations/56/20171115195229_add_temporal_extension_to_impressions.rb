class AddTemporalExtensionToImpressions < ActiveRecord::Migration[5.0]
  def self.up
    enable_extension 'btree_gist' unless extension_enabled?('btree_gist')
    change_table :impressions, temporal: true, copy_data: true
  end

  def self.down
    change_table :impressions, temporal: false
  end
end
