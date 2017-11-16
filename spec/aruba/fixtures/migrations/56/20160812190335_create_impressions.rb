class CreateImpressions < ActiveRecord::Migration[5.0]
  def change
    create_table :impressions do |t|
      t.integer :response
      t.decimal :amount

      t.timestamps
    end
  end
end
