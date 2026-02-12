# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OmniAuth::FreshbooksOauth2::TokenClient do
  subject(:client) do
    described_class.new(
      client_id: 'test_client_id',
      client_secret: 'test_client_secret',
      redirect_uri: 'https://example.com/callback'
    )
  end

  let(:token_url) { 'https://api.freshbooks.com/auth/oauth/token' }

  describe '#initialize' do
    it 'sets the client_id' do
      expect(client.client_id).to eq('test_client_id')
    end

    it 'sets the client_secret' do
      expect(client.client_secret).to eq('test_client_secret')
    end

    it 'sets the redirect_uri' do
      expect(client.redirect_uri).to eq('https://example.com/callback')
    end

    it 'allows redirect_uri to be nil' do
      no_redirect_client = described_class.new(
        client_id: 'id',
        client_secret: 'secret'
      )
      expect(no_redirect_client.redirect_uri).to be_nil
    end
  end

  describe '#token_expired?' do
    context 'when expires_at is nil' do
      it 'returns true' do
        expect(client.token_expired?(nil)).to be true
      end
    end

    context 'when token is expired' do
      it 'returns true for past time' do
        expires_at = Time.now - 3600
        expect(client.token_expired?(expires_at)).to be true
      end

      it 'returns true for Unix timestamp in the past' do
        expires_at = Time.now.to_i - 3600
        expect(client.token_expired?(expires_at)).to be true
      end
    end

    context 'when token is within buffer period' do
      it 'returns true when within default 5 minute buffer' do
        expires_at = Time.now + 60 # 1 minute from now
        expect(client.token_expired?(expires_at)).to be true
      end
    end

    context 'when token is not expired' do
      it 'returns false for future time beyond buffer' do
        expires_at = Time.now + 3600 # 1 hour from now
        expect(client.token_expired?(expires_at)).to be false
      end

      it 'respects custom buffer_seconds' do
        expires_at = Time.now + 60 # 1 minute from now
        expect(client.token_expired?(expires_at, buffer_seconds: 30)).to be false
      end
    end
  end

  describe '#refresh_token' do
    let(:refresh_token) { 'test_refresh_token' }

    context 'when refresh_token is nil or empty' do
      it 'returns failure for nil token' do
        result = client.refresh_token(nil)
        expect(result).to be_failure
        expect(result.error).to eq('Refresh token is required')
      end

      it 'returns failure for empty token' do
        result = client.refresh_token('')
        expect(result).to be_failure
        expect(result.error).to eq('Refresh token is required')
      end
    end

    context 'when refresh is successful' do
      let(:success_response) do
        {
          'access_token' => 'new_access_token',
          'refresh_token' => 'new_refresh_token',
          'expires_in' => 43_200,
          'token_type' => 'Bearer',
          'created_at' => 1_704_067_200
        }
      end

      before do
        stub_request(:post, token_url)
          .with(
            headers: {
              'Content-Type' => 'application/json',
              'Accept' => 'application/json'
            }
          )
          .to_return(
            status: 200,
            body: success_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success' do
        result = client.refresh_token(refresh_token)
        expect(result).to be_success
      end

      it 'returns the new access token' do
        result = client.refresh_token(refresh_token)
        expect(result.access_token).to eq('new_access_token')
      end

      it 'returns the new refresh token' do
        result = client.refresh_token(refresh_token)
        expect(result.refresh_token).to eq('new_refresh_token')
      end

      it 'returns expires_in' do
        result = client.refresh_token(refresh_token)
        expect(result.expires_in).to eq(43_200)
      end

      it 'calculates expires_at' do
        result = client.refresh_token(refresh_token)
        expect(result.expires_at).to be_within(5).of(Time.now.to_i + 43_200)
      end

      it 'includes raw response' do
        result = client.refresh_token(refresh_token)
        expect(result.raw_response).to eq(success_response)
      end

      it 'sends JSON content type' do
        client.refresh_token(refresh_token)

        expect(WebMock).to have_requested(:post, token_url)
          .with(headers: { 'Content-Type' => 'application/json' })
      end

      it 'sends grant_type in body' do
        client.refresh_token(refresh_token)

        expect(WebMock).to have_requested(:post, token_url)
          .with(body: hash_including('grant_type' => 'refresh_token'))
      end

      it 'sends client credentials in body' do
        client.refresh_token(refresh_token)

        expect(WebMock).to have_requested(:post, token_url)
          .with(body: hash_including(
            'client_id' => 'test_client_id',
            'client_secret' => 'test_client_secret'
          ))
      end

      it 'sends redirect_uri in body' do
        client.refresh_token(refresh_token)

        expect(WebMock).to have_requested(:post, token_url)
          .with(body: hash_including('redirect_uri' => 'https://example.com/callback'))
      end

      it 'sends refresh_token in body' do
        client.refresh_token(refresh_token)

        expect(WebMock).to have_requested(:post, token_url)
          .with(body: hash_including('refresh_token' => 'test_refresh_token'))
      end
    end

    context 'when redirect_uri is not set' do
      let(:client_without_redirect) do
        described_class.new(
          client_id: 'test_client_id',
          client_secret: 'test_client_secret'
        )
      end

      before do
        stub_request(:post, token_url)
          .to_return(
            status: 200,
            body: { 'access_token' => 'token' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'omits redirect_uri from request body' do
        client_without_redirect.refresh_token('some_token')

        expect(WebMock).to(
          have_requested(:post, token_url)
            .with { |req| !JSON.parse(req.body).key?('redirect_uri') }
        )
      end
    end

    context 'when refresh fails with FreshBooks error format' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 401,
            body: {
              'response' => {
                'errors' => [
                  { 'errno' => 1012, 'message' => 'Invalid refresh token.' }
                ]
              }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns failure' do
        result = client.refresh_token(refresh_token)
        expect(result).to be_failure
      end

      it 'extracts FreshBooks error message' do
        result = client.refresh_token(refresh_token)
        expect(result.error).to eq('Invalid refresh token.')
      end
    end

    context 'when refresh fails with standard OAuth error format' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 400,
            body: { 'error' => 'invalid_grant', 'error_description' => 'Token is expired' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns failure' do
        result = client.refresh_token(refresh_token)
        expect(result).to be_failure
      end

      it 'includes the error description' do
        result = client.refresh_token(refresh_token)
        expect(result.error).to eq('Token is expired')
      end
    end

    context 'when refresh fails with non-JSON response' do
      before do
        stub_request(:post, token_url)
          .to_return(
            status: 500,
            body: 'Internal Server Error',
            headers: { 'Content-Type' => 'text/plain' }
          )
      end

      it 'returns failure with body as error' do
        result = client.refresh_token(refresh_token)
        expect(result).to be_failure
        expect(result.error).to eq('Internal Server Error')
      end
    end

    context 'when network error occurs' do
      before do
        stub_request(:post, token_url)
          .to_raise(Faraday::ConnectionFailed.new('Connection refused'))
      end

      it 'returns failure with network error' do
        result = client.refresh_token(refresh_token)
        expect(result).to be_failure
        expect(result.error).to include('Network error')
      end
    end
  end

  describe OmniAuth::FreshbooksOauth2::TokenClient::TokenResult do
    describe '#success?' do
      it 'returns true for successful result' do
        result = described_class.new(success: true, access_token: 'token')
        expect(result.success?).to be true
      end

      it 'returns false for failed result' do
        result = described_class.new(success: false, error: 'error')
        expect(result.success?).to be false
      end
    end

    describe '#failure?' do
      it 'returns false for successful result' do
        result = described_class.new(success: true, access_token: 'token')
        expect(result.failure?).to be false
      end

      it 'returns true for failed result' do
        result = described_class.new(success: false, error: 'error')
        expect(result.failure?).to be true
      end
    end
  end
end
