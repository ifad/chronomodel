require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe 'models with counter cache' do
  include ChronoTest::TimeMachine::Helpers

  adapter.create_table 'sections', temporal: true, no_journal: %w[articles_count] do |t|
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

  describe 'are not subject to race condition if no_journal is set on the counter cache column' do
    specify do
      section = Section.create!

      expect(section.articles_count).to eq(0)
      Article.create!(section_id: section.id)
      expect(section.reload.articles_count).to eq(1)

      num_threads = 10

      expect do
        Array.new(num_threads).map do
          Thread.new { Article.create!(section_id: section.id) }
        end.each(&:join)
      end.not_to raise_error
    end
  end
end
