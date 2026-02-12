# frozen_string_literal: true

require_relative 'lib/omniauth/freshbooks_oauth2/version'

Gem::Specification.new do |spec|
  spec.name = 'omniauth-freshbooks-oauth2'
  spec.version = OmniAuth::FreshbooksOauth2::VERSION
  spec.authors = ['dan1d']
  spec.email = ['dan@theowner.me']

  spec.summary = 'OmniAuth strategy for FreshBooks OAuth 2.0 (OmniAuth 2.0+ compatible)'
  spec.description = 'An OmniAuth strategy for authenticating with FreshBooks using OAuth 2.0. ' \
                     'Compatible with OmniAuth 2.0+ with multi-business support, ' \
                     'identity fetching, and token refresh capabilities.'
  spec.homepage = 'https://github.com/dan1d/omniauth-freshbooks-oauth2'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob(%w[
                          lib/**/*
                          LICENSE.txt
                          README.md
                          CHANGELOG.md
                        ])
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'faraday', '>= 1.0', '< 3.0'
  spec.add_dependency 'omniauth', '~> 2.0'
  spec.add_dependency 'omniauth-oauth2', '~> 1.8'
  spec.add_dependency 'ostruct', '~> 0.6'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rack-test', '~> 2.1'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '1.84.0'
  spec.add_development_dependency 'rubocop-rspec', '~> 2.31.0'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'webmock', '~> 3.18'
end
