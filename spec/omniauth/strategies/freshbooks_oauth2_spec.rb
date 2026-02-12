# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OmniAuth::Strategies::FreshbooksOauth2 do
  include Rack::Test::Methods

  let(:app) do
    Rack::Builder.new do
      use OmniAuth::Test::PhonySession
      use OmniAuth::Strategies::FreshbooksOauth2, 'client_id', 'client_secret' # rubocop:disable RSpec/DescribedClass
      run ->(env) { [200, { 'Content-Type' => 'text/plain' }, [env.key?('omniauth.auth').to_s]] }
    end.to_app
  end

  let(:strategy) { described_class.new(app, 'client_id', 'client_secret') }

  describe 'client options' do
    subject(:client_options) { strategy.options.client_options }

    it 'has correct site' do
      expect(client_options[:site]).to eq('https://auth.freshbooks.com')
    end

    it 'has correct authorize_url' do
      expect(client_options[:authorize_url]).to eq('/oauth/authorize')
    end

    it 'has correct token_url' do
      expect(client_options[:token_url]).to eq('https://api.freshbooks.com/auth/oauth/token')
    end
  end

  describe 'default options' do
    it 'has correct name' do
      expect(strategy.options.name).to eq(:freshbooks_oauth2)
    end
  end

  describe '#callback_url' do
    context 'with custom redirect_uri' do
      let(:strategy) do
        described_class.new(app, 'client_id', 'client_secret',
                            redirect_uri: 'https://custom.example.com/callback')
      end

      it 'uses the custom redirect_uri' do
        expect(strategy.callback_url).to eq('https://custom.example.com/callback')
      end
    end

    context 'without custom redirect_uri' do
      before do
        allow(strategy).to receive_messages(full_host: 'https://example.com', script_name: '',
                                            callback_path: '/auth/freshbooks_oauth2/callback')
      end

      it 'builds callback URL from host and path' do
        expect(strategy.callback_url).to eq('https://example.com/auth/freshbooks_oauth2/callback')
      end
    end
  end

  describe 'credentials' do
    let(:access_token) do
      double(
        token: 'access_token_value',
        refresh_token: 'refresh_token_value',
        expires_at: 1_704_067_200,
        expires?: true
      )
    end

    before do
      allow(strategy).to receive(:access_token).and_return(access_token)
    end

    it 'includes token' do
      expect(strategy.credentials['token']).to eq('access_token_value')
    end

    it 'includes refresh_token' do
      expect(strategy.credentials['refresh_token']).to eq('refresh_token_value')
    end

    it 'includes expires_at' do
      expect(strategy.credentials['expires_at']).to eq(1_704_067_200)
    end

    it 'includes expires flag' do
      expect(strategy.credentials['expires']).to be true
    end

    context 'when refresh_token is nil' do
      let(:access_token) do
        double(
          token: 'access_token_value',
          refresh_token: nil,
          expires_at: 1_704_067_200,
          expires?: true
        )
      end

      it 'does not include refresh_token key' do
        expect(strategy.credentials).not_to have_key('refresh_token')
      end
    end

    context 'when expires_at is nil' do
      let(:access_token) do
        double(
          token: 'access_token_value',
          refresh_token: 'refresh_token_value',
          expires_at: nil,
          expires?: false
        )
      end

      it 'does not include expires_at key' do
        expect(strategy.credentials).not_to have_key('expires_at')
      end

      it 'sets expires to false' do
        expect(strategy.credentials['expires']).to be false
      end
    end
  end

  describe 'info' do
    let(:identity_response) do
      {
        'id' => 123_456,
        'first_name' => 'John',
        'last_name' => 'Doe',
        'email' => 'john@example.com',
        'business_memberships' => [
          {
            'id' => 789,
            'role' => 'owner',
            'business' => {
              'id' => 456,
              'account_id' => 'ABC123',
              'name' => 'Acme Restaurant'
            }
          }
        ]
      }
    end

    before do
      allow(strategy).to receive(:identity_info).and_return(identity_response)
    end

    it 'includes email' do
      expect(strategy.info[:email]).to eq('john@example.com')
    end

    it 'includes first_name' do
      expect(strategy.info[:first_name]).to eq('John')
    end

    it 'includes last_name' do
      expect(strategy.info[:last_name]).to eq('Doe')
    end

    it 'includes full name' do
      expect(strategy.info[:name]).to eq('John Doe')
    end

    it 'includes account_id' do
      expect(strategy.info[:account_id]).to eq('ABC123')
    end

    it 'includes business_name' do
      expect(strategy.info[:business_name]).to eq('Acme Restaurant')
    end

    context 'when only first_name is present' do
      let(:identity_response) { { 'first_name' => 'John', 'business_memberships' => [] } }

      it 'returns just the first name' do
        expect(strategy.info[:name]).to eq('John')
      end
    end

    context 'when neither name is present' do
      let(:identity_response) { { 'email' => 'john@example.com', 'business_memberships' => [] } }

      it 'returns nil for name' do
        expect(strategy.info[:name]).to be_nil
      end
    end
  end

  describe 'uid' do
    let(:identity_response) do
      {
        'business_memberships' => [
          { 'business' => { 'account_id' => 'ABC123' } }
        ]
      }
    end

    before do
      allow(strategy).to receive(:identity_info).and_return(identity_response)
    end

    it 'uses account_id as uid' do
      expect(strategy.uid).to eq('ABC123')
    end

    context 'when no business memberships exist' do
      let(:identity_response) { { 'business_memberships' => [] } }

      it 'returns nil' do
        expect(strategy.uid).to be_nil
      end
    end

    context 'when business_memberships key is missing' do
      let(:identity_response) { {} }

      it 'returns nil' do
        expect(strategy.uid).to be_nil
      end
    end
  end

  describe 'extra' do
    let(:identity_response) do
      {
        'email' => 'john@example.com',
        'business_memberships' => [
          { 'business' => { 'account_id' => 'ABC123', 'name' => 'My Biz' } }
        ]
      }
    end

    before do
      allow(strategy).to receive(:identity_info).and_return(identity_response)
    end

    it 'includes account_id' do
      expect(strategy.extra[:account_id]).to eq('ABC123')
    end

    it 'includes business_memberships' do
      expect(strategy.extra[:business_memberships].length).to eq(1)
    end

    it 'includes raw_info' do
      expect(strategy.extra[:raw_info]).to eq(identity_response)
    end
  end

  describe '#identity_info' do
    let(:identity_response_body) do
      {
        'response' => {
          'id' => 123_456,
          'first_name' => 'John',
          'last_name' => 'Doe',
          'email' => 'john@example.com',
          'business_memberships' => [
            { 'business' => { 'account_id' => 'ABC123' } }
          ]
        }
      }
    end

    let(:access_token) { double(token: 'test_access_token') }

    context 'when identity endpoint succeeds' do
      before do
        allow(strategy).to receive(:access_token).and_return(access_token)
        stub_request(:get, 'https://api.freshbooks.com/auth/api/v1/users/me')
          .with(headers: { 'Authorization' => 'Bearer test_access_token' })
          .to_return(
            status: 200,
            body: identity_response_body.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'fetches identity from the API' do
        expect(strategy.identity_info['email']).to eq('john@example.com')
      end

      it 'extracts the response body' do
        expect(strategy.identity_info['id']).to eq(123_456)
      end

      it 'caches the result' do
        strategy.identity_info
        strategy.identity_info

        expect(WebMock).to have_requested(:get, 'https://api.freshbooks.com/auth/api/v1/users/me').once
      end
    end

    context 'when identity endpoint fails' do
      before do
        allow(strategy).to receive(:access_token).and_return(access_token)
        stub_request(:get, 'https://api.freshbooks.com/auth/api/v1/users/me')
          .to_return(status: 401, body: 'Unauthorized')
      end

      it 'returns empty hash' do
        expect(strategy.identity_info).to eq({})
      end
    end

    context 'when identity endpoint raises an error' do
      before do
        allow(strategy).to receive(:access_token).and_return(access_token)
        stub_request(:get, 'https://api.freshbooks.com/auth/api/v1/users/me')
          .to_raise(StandardError.new('Connection error'))
      end

      it 'returns empty hash' do
        expect(strategy.identity_info).to eq({})
      end
    end
  end

  describe '#build_access_token' do
    let(:token_url) { 'https://api.freshbooks.com/auth/oauth/token' }
    let(:mock_request) { double('Request', params: { 'code' => 'test_auth_code' }) }

    let(:token_response) do
      {
        'access_token' => 'test_access_token',
        'refresh_token' => 'test_refresh_token',
        'expires_in' => 43_200,
        'token_type' => 'Bearer'
      }
    end

    before do
      allow(strategy).to receive_messages(request: mock_request,
                                          callback_url: 'https://example.com/callback')
      stub_request(:post, token_url)
        .with(
          headers: {
            'Content-Type' => 'application/json',
            'Accept' => 'application/json'
          }
        )
        .to_return(
          status: 200,
          body: token_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'exchanges the code for an access token' do
      token = strategy.send(:build_access_token)
      expect(token.token).to eq('test_access_token')
    end

    it 'includes the refresh token' do
      token = strategy.send(:build_access_token)
      expect(token.refresh_token).to eq('test_refresh_token')
    end

    it 'sends JSON content type header' do
      strategy.send(:build_access_token)

      expect(WebMock).to have_requested(:post, token_url)
        .with(headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends credentials in JSON body' do
      strategy.send(:build_access_token)

      expect(WebMock).to have_requested(:post, token_url)
        .with(body: hash_including(
          'client_id' => 'client_id',
          'client_secret' => 'client_secret',
          'code' => 'test_auth_code',
          'grant_type' => 'authorization_code',
          'redirect_uri' => 'https://example.com/callback'
        ))
    end

    context 'when token exchange fails' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 401,
            body: { 'error' => 'invalid_grant', 'error_description' => 'Invalid code' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises an OAuth2 error' do
        expect { strategy.send(:build_access_token) }.to raise_error(OAuth2::Error)
      end
    end
  end
end
