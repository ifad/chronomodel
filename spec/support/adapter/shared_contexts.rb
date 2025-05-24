# frozen_string_literal: true

RSpec.shared_context 'with temporal tables' do
  before { adapter.create_table(table, temporal: true, &columns) }
  after  { adapter.drop_table table }
end

RSpec.shared_context 'with plain tables' do
  before { adapter.create_table(table, temporal: false, &columns) }
  after  { adapter.drop_table table }
end
