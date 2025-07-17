# frozen_string_literal: true

require 'spec_helper'

# Test for through association where clause fix without database
RSpec.describe ChronoModel::Patches::Association do
  let(:mock_owner) { double('owner', as_of_time: Time.current, class: double('owner_class')) }
  let(:mock_reflection) { double('reflection', klass: double('klass')) }
  let(:mock_scope) { double('scope') }
  
  let(:association) do
    association_class = Class.new do
      include ChronoModel::Patches::Association
      
      def initialize(owner, reflection)
        @owner = owner
        @reflection = reflection
      end
      
      attr_reader :owner, :reflection
      
      def klass
        reflection.klass
      end
      
      def super_scope
        mock_scope
      end
      
      # Mock the original scope method
      def scope_without_chrono
        super_scope
      end
      alias super scope_without_chrono
    end
    
    association_class.new(mock_owner, mock_reflection)
  end

  before do
    allow(mock_owner.class).to receive(:include?).with(ChronoModel::Patches::AsOfTimeHolder).and_return(true)
    allow(mock_scope).to receive(:as_of_time!).and_return(mock_scope)
  end

  describe '#_through_association_with_where_clause?' do
    context 'when reflection is not a ThroughReflection' do
      before do
        allow(mock_reflection).to receive(:is_a?).with(ActiveRecord::Reflection::ThroughReflection).and_return(false)
      end

      it 'returns false' do
        expect(association.send(:_through_association_with_where_clause?, mock_scope)).to be false
      end
    end

    context 'when reflection is a ThroughReflection' do
      let(:mock_where_clause) { double('where_clause') }
      let(:mock_having_clause) { double('having_clause') }

      before do
        allow(mock_reflection).to receive(:is_a?).with(ActiveRecord::Reflection::ThroughReflection).and_return(true)
        allow(mock_scope).to receive(:where_clause).and_return(mock_where_clause)
        allow(mock_scope).to receive(:having_clause).and_return(mock_having_clause)
      end

      context 'when scope has where clauses' do
        before do
          allow(mock_where_clause).to receive(:any?).and_return(true)
          allow(mock_having_clause).to receive(:any?).and_return(false)
        end

        it 'returns true' do
          expect(association.send(:_through_association_with_where_clause?, mock_scope)).to be true
        end
      end

      context 'when scope has having clauses' do
        before do
          allow(mock_where_clause).to receive(:any?).and_return(false)
          allow(mock_having_clause).to receive(:any?).and_return(true)
        end

        it 'returns true' do
          expect(association.send(:_through_association_with_where_clause?, mock_scope)).to be true
        end
      end

      context 'when scope has no where or having clauses' do
        before do
          allow(mock_where_clause).to receive(:any?).and_return(false)
          allow(mock_having_clause).to receive(:any?).and_return(false)
        end

        it 'returns false' do
          expect(association.send(:_through_association_with_where_clause?, mock_scope)).to be false
        end
      end
    end
  end
end