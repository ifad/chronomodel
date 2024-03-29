# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

class Section < ActiveRecord::Base
  include ChronoModel::TimeMachine

  has_many :articles
end

class Article < ActiveRecord::Base
  include ChronoModel::TimeMachine

  belongs_to :section, counter_cache: true
end

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  context 'when models have a counter cache' do
    adapter.create_table 'sections', temporal: true, no_journal: %w[articles_count] do |t|
      t.string :name
      t.integer :articles_count, default: 0
    end

    adapter.create_table 'articles', temporal: true do |t|
      t.string :title
      t.references :section
    end

    it 'is not subject to race condition if no_journal is set on the counter cache column' do
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
