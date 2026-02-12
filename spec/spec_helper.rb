# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  minimum_coverage 80
end

require 'bundler/setup'
require 'omniauth-freshbooks-oauth2'
require 'webmock/rspec'
require 'rack/test'

# Disable real HTTP connections in tests
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before do
    OmniAuth.config.test_mode = true
  end

  config.after do
    OmniAuth.config.test_mode = false
  end
end
