require 'spec_helper'
require 'support/helpers'

describe ChronoModel::TimeMachine do
  include ChronoTest::Helpers::TimeMachine

    adapter.create_table 'sections', temporal: true do |t|
      t.string :name
      t.integer :articles_count, default: 0
    end

    adapter.create_table 'articles', temporal: true do |t|
      t.string :title
      t.references :section
    end

  class ::Section < ActiveRecord::Base
    include ChronoModel::TimeMachine

    has_many :articles
  end

  class ::Article < ActiveRecord::Base
    include ChronoModel::TimeMachine

    belongs_to :section, counter_cache: true
  end

  describe 'race condition' do
    specify do
      section = Section.create!
      expect(section.articles_count).to eq(0)

      Article.create!(section_id: section.id)

      expect(section.reload.articles_count).to eq(1)

      num_threads = 10
      expect do
        Array.new(num_threads).map do
          Thread.new do
            # sleep(rand) # With the sleep statement everything works
            Article.create!(section_id: section.id)
          end
        end.each(&:join)
      end.to_not raise_error
    end
  end
end
