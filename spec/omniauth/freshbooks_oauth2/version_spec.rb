# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OmniAuth::FreshbooksOauth2 do
  describe 'VERSION' do
    it 'has a version number' do
      expect(OmniAuth::FreshbooksOauth2::VERSION).not_to be_nil
    end

    it 'follows semantic versioning format' do
      expect(OmniAuth::FreshbooksOauth2::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end
end
