# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

if Rails.version >= '5.1'
  class Attachment < ActiveRecord::Base
    belongs_to :blob
    delegate_missing_to :blob
  end

  class Blob < ActiveRecord::Base
    has_many :attachments
  end

  RSpec.describe 'delegate_missing_to' do
    include ChronoTest::TimeMachine::Helpers

    adapter.create_table 'attachments' do |t|
      t.integer :blob_id
    end

    adapter.create_table 'blobs' do |t|
      t.string :name
    end

    let(:attachment) { Attachment.create!(blob: Blob.create!(name: 'test')).reload }

    it 'does not raise errors' do
      expect do
        attachment.blob
      end.not_to raise_error
    end

    it 'allows delegation to associated models' do
      expect(attachment.name).to eq 'test'
    end
  end
end
