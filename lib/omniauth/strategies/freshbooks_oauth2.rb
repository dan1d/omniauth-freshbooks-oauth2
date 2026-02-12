# frozen_string_literal: true

require 'omniauth-oauth2'
require 'faraday'
require 'json'
require 'ostruct'

module OmniAuth
  module Strategies
    # OmniAuth strategy for FreshBooks OAuth 2.0
    #
    # This strategy handles FreshBooks' OAuth 2.0 flow with:
    # - JSON body for token exchange (not form-urlencoded)
    # - Multi-business support via identity endpoint
    # - Automatic account discovery via /auth/api/v1/users/me
    # - Single-use refresh tokens (always save the new one)
    #
    # FreshBooks OAuth 2.0 specifics:
    # - Uses auth.freshbooks.com for authorization
    # - Uses api.freshbooks.com for token exchange and API calls
    # - Requires JSON Content-Type for token exchange
    # - Access tokens expire in 12 hours
    # - Refresh tokens never expire but are single-use
    # - Identity endpoint returns business_memberships with account_id
    #
    # @example Basic usage with Devise
    #   config.omniauth :freshbooks_oauth2,
    #                   ENV['FRESHBOOKS_CLIENT_ID'],
    #                   ENV['FRESHBOOKS_CLIENT_SECRET']
    #
    class FreshbooksOauth2 < OmniAuth::Strategies::OAuth2
      option :name, :freshbooks_oauth2

      option :client_options, {
        site: 'https://auth.freshbooks.com',
        authorize_url: '/oauth/authorize',
        token_url: 'https://api.freshbooks.com/auth/oauth/token'
      }

      # Use the first business membership's account_id as the UID
      uid { account_id }

      info do
        {
          email: identity_info['email'],
          first_name: identity_info['first_name'],
          last_name: identity_info['last_name'],
          name: full_name,
          account_id: account_id,
          business_name: business_info['name']
        }
      end

      credentials do
        hash = { 'token' => access_token.token }
        hash['refresh_token'] = access_token.refresh_token if access_token.refresh_token
        hash['expires_at'] = access_token.expires_at if access_token.expires_at
        hash['expires'] = access_token.expires?
        hash
      end

      extra do
        {
          account_id: account_id,
          business_memberships: business_memberships,
          raw_info: identity_info
        }
      end

      # Identity info fetched from FreshBooks identity endpoint
      def identity_info
        @identity_info ||= fetch_identity
      end

      # All business memberships for this user
      def business_memberships
        identity_info['business_memberships'] || []
      end

      # Override callback_url to support custom redirect URIs
      def callback_url
        options[:redirect_uri] || (full_host + script_name + callback_path)
      end

      private

      # The FreshBooks account_id from the first business membership
      def account_id
        business_info['account_id']
      end

      # First business membership's business info
      def business_info
        @business_info ||= begin
          first_membership = business_memberships.first || {}
          first_membership['business'] || {}
        end
      end

      # Construct full name from identity info
      def full_name
        name = [identity_info['first_name'], identity_info['last_name']].compact.join(' ')
        name.empty? ? nil : name
      end

      # Fetch user identity from FreshBooks identity endpoint
      def fetch_identity
        response = Faraday.get(identity_url) do |req|
          req.headers['Authorization'] = "Bearer #{access_token.token}"
          req.headers['Accept'] = 'application/json'
        end

        return {} unless response.success?

        data = JSON.parse(response.body)
        data['response'] || {}
      rescue StandardError => e
        log(:error, "Failed to fetch identity: #{e.message}")
        {}
      end

      # FreshBooks identity endpoint
      def identity_url
        'https://api.freshbooks.com/auth/api/v1/users/me'
      end

      # Override to handle FreshBooks' JSON token endpoint
      # FreshBooks requires JSON body for token exchange with credentials in body
      def build_access_token
        code = request.params['code']
        token_url = options.client_options['token_url'] || options.client_options[:token_url]

        response = Faraday.post(token_url) do |req|
          req.headers['Content-Type'] = 'application/json'
          req.headers['Accept'] = 'application/json'
          req.body = {
            grant_type: 'authorization_code',
            client_id: options.client_id,
            client_secret: options.client_secret,
            code: code,
            redirect_uri: callback_url
          }.to_json
        end

        unless response.success?
          error_body = begin
            JSON.parse(response.body)
          rescue JSON::ParserError
            { 'error' => response.body }
          end
          raise ::OAuth2::Error, build_error_response(error_body, response)
        end

        token_data = JSON.parse(response.body)

        ::OAuth2::AccessToken.new(
          client,
          token_data['access_token'],
          refresh_token: token_data['refresh_token'],
          expires_in: token_data['expires_in'],
          token_type: token_data['token_type'] || 'Bearer'
        )
      end

      def build_error_response(error_body, response)
        OpenStruct.new(
          parsed: error_body,
          body: response.body,
          status: response.status
        )
      end

      def log(level, message)
        return unless defined?(OmniAuth.logger) && OmniAuth.logger

        OmniAuth.logger.send(level, "[FreshbooksOauth2] #{message}")
      end
    end
  end
end
