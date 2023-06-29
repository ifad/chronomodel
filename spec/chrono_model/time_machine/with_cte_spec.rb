require 'spec_helper'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  adapter.create_table 'posts', temporal: true do |t|
    t.string :title
    t.references :author
    t.timestamps
  end

  adapter.create_table 'authors', temporal: true do |t|
    t.string :name
    t.timestamps
  end

  class Post < ActiveRecord::Base
    include ChronoModel::TimeMachine

    belongs_to :author
  end

  class Author < ActiveRecord::Base
    include ChronoModel::TimeMachine
  end

  describe '.with CTE' do
    let(:author1) { Author.create(name: author1_name_as_of_post1) }
    let(:post1) { Post.create(title: 'Post 1', author: author1) }
    let(:author2) { Author.create(name: 'Author 2') }
    let(:post2) { Post.create(title: 'Post 2', author: author2) }

    let(:author1_name_as_of_post1) { 'Author 1.1' }
    let(:author1_name_as_of_post2) { 'Author 1.2' }
    let(:author1_name_as_of_now) { 'Author 1.3' }

    before do
      post1
      sleep(0.05)
      author1.update(name: author1_name_as_of_post2)
      post2
      sleep(0.05)
      author1.update(name: author1_name_as_of_now)
    end

    it 'works' do
      # it does not automatically add as_of to CTE
      scope = Post.as_of(post2.created_at)
                  .with(authors_cte: Author.all)
                  .joins("inner join authors_cte on authors_cte.id = posts.author_id")
      expect(scope.where(authors_cte: { name: author1_name_as_of_now }).count).to eq(1)
      expect(scope.where(authors_cte: { name: author1_name_as_of_post2 }).count).to eq(0)

      # it produces an as_of CTE
      scope = Post.as_of(post2.created_at)
                  .with(authors_cte: Author.as_of(post2.created_at).all)
                  .joins("inner join authors_cte on authors_cte.id = posts.author_id")
      expect(scope.where(authors_cte: { name: author1_name_as_of_now }).count).to eq(0)
      expect(scope.where(authors_cte: { name: author1_name_as_of_post2 }).count).to eq(1)
    end
  end
end
