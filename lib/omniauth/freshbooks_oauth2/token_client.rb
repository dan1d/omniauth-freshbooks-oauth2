# frozen_string_literal: true

require 'faraday'
require 'json'

module OmniAuth
  module FreshbooksOauth2
    # Client for managing FreshBooks OAuth2 tokens
    #
    # This class provides an easy way to refresh expired tokens in your Rails app.
    # FreshBooks access tokens expire in 12 hours. Refresh tokens never expire but
    # are single-use — always save the new refresh token returned from each refresh call.
    #
    # @example Basic usage
    #   client = OmniAuth::FreshbooksOauth2::TokenClient.new(
    #     client_id: ENV['FRESHBOOKS_CLIENT_ID'],
    #     client_secret: ENV['FRESHBOOKS_CLIENT_SECRET'],
    #     redirect_uri: ENV['FRESHBOOKS_REDIRECT_URI']
    #   )
    #
    #   result = client.refresh_token(account.freshbooks_refresh_token)
    #   if result.success?
    #     account.update!(
    #       freshbooks_access_token: result.access_token,
    #       freshbooks_refresh_token: result.refresh_token,
    #       freshbooks_token_expires_at: Time.at(result.expires_at)
    #     )
    #   end
    #
    # @example With automatic token refresh in a service
    #   class FreshBooksApiService
    #     def initialize(account)
    #       @account = account
    #       @client = OmniAuth::FreshbooksOauth2::TokenClient.new(
    #         client_id: ENV['FRESHBOOKS_CLIENT_ID'],
    #         client_secret: ENV['FRESHBOOKS_CLIENT_SECRET'],
    #         redirect_uri: ENV['FRESHBOOKS_REDIRECT_URI']
    #       )
    #     end
    #
    #     def with_valid_token
    #       refresh_if_expired!
    #       yield @account.freshbooks_access_token
    #     end
    #
    #     private
    #
    #     def refresh_if_expired!
    #       return unless @client.token_expired?(@account.freshbooks_token_expires_at)
    #
    #       result = @client.refresh_token(@account.freshbooks_refresh_token)
    #       raise "Token refresh failed: #{result.error}" unless result.success?
    #
    #       @account.update!(
    #         freshbooks_access_token: result.access_token,
    #         freshbooks_refresh_token: result.refresh_token,
    #         freshbooks_token_expires_at: Time.at(result.expires_at)
    #       )
    #     end
    #   end
    #
    class TokenClient
      # Result object for token operations
      class TokenResult
        attr_reader :access_token, :refresh_token, :expires_at, :expires_in, :error, :raw_response

        def initialize(success:, access_token: nil, refresh_token: nil, expires_at: nil, expires_in: nil,
                       error: nil, raw_response: nil)
          @success = success
          @access_token = access_token
          @refresh_token = refresh_token
          @expires_at = expires_at
          @expires_in = expires_in
          @error = error
          @raw_response = raw_response
        end

        def success?
          @success
        end

        def failure?
          !@success
        end
      end

      # FreshBooks OAuth2 token endpoint
      TOKEN_URL = 'https://api.freshbooks.com/auth/oauth/token'

      attr_reader :client_id, :client_secret, :redirect_uri

      # Initialize a new TokenClient
      #
      # @param client_id [String] Your FreshBooks App Client ID
      # @param client_secret [String] Your FreshBooks App Client Secret
      # @param redirect_uri [String] Your registered redirect URI (required by FreshBooks for refresh)
      def initialize(client_id:, client_secret:, redirect_uri: nil)
        @client_id = client_id
        @client_secret = client_secret
        @redirect_uri = redirect_uri
      end

      # Refresh an access token using a refresh token
      #
      # Important: FreshBooks refresh tokens are single-use. Each refresh returns a new
      # refresh token and the old one is invalidated. Always save the new refresh token!
      #
      # @param refresh_token [String] The refresh token to use
      # @return [TokenResult] Result object with new tokens or error
      def refresh_token(refresh_token)
        if refresh_token.nil? || refresh_token.empty?
          return TokenResult.new(success: false,
                                 error: 'Refresh token is required')
        end

        response = make_refresh_request(refresh_token)

        if response.success?
          parse_success_response(response)
        else
          parse_error_response(response)
        end
      rescue Faraday::Error => e
        TokenResult.new(success: false, error: "Network error: #{e.message}")
      rescue JSON::ParserError => e
        TokenResult.new(success: false, error: "Invalid JSON response: #{e.message}")
      rescue StandardError => e
        TokenResult.new(success: false, error: "Unexpected error: #{e.message}")
      end

      # Check if a token is expired or about to expire
      #
      # @param expires_at [Time, Integer] Token expiration time
      # @param buffer_seconds [Integer] Buffer before expiration (default: 300 = 5 minutes)
      # @return [Boolean] True if token is expired or will expire within buffer
      def token_expired?(expires_at, buffer_seconds: 300)
        return true if expires_at.nil?

        expires_at_time = expires_at.is_a?(Integer) ? Time.at(expires_at) : expires_at
        Time.now >= (expires_at_time - buffer_seconds)
      end

      private

      def make_refresh_request(refresh_token)
        # FreshBooks requires JSON body with credentials for refresh
        body = {
          grant_type: 'refresh_token',
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: refresh_token
        }
        body[:redirect_uri] = redirect_uri if redirect_uri

        Faraday.post(TOKEN_URL) do |req|
          req.headers['Content-Type'] = 'application/json'
          req.headers['Accept'] = 'application/json'
          req.body = body.to_json
        end
      end

      def parse_success_response(response)
        data = JSON.parse(response.body)

        expires_in = data['expires_in']&.to_i
        expires_at = expires_in ? Time.now.to_i + expires_in : nil

        TokenResult.new(
          success: true,
          access_token: data['access_token'],
          refresh_token: data['refresh_token'],
          expires_in: expires_in,
          expires_at: expires_at,
          raw_response: data
        )
      end

      def parse_error_response(response)
        error_data = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          { 'error' => response.body }
        end

        error_message = extract_error_message(error_data, response)

        TokenResult.new(
          success: false,
          error: error_message,
          raw_response: error_data
        )
      end

      def extract_error_message(error_data, response)
        # FreshBooks error format: { "response": { "errors": [{ "message": "..." }] } }
        if error_data['response'] && error_data['response']['errors']
          errors = error_data['response']['errors']
          return errors.map { |e| e['message'] }.compact.join('; ') unless errors.empty?
        end

        error_data['error_description'] || error_data['error'] || "HTTP #{response.status}"
      end
    end
  end
end
