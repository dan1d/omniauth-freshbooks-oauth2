# OmniAuth FreshBooks OAuth2 Strategy

[![Gem Version](https://badge.fury.io/rb/omniauth-freshbooks-oauth2.svg)](https://badge.fury.io/rb/omniauth-freshbooks-oauth2)
[![CI](https://github.com/dan1d/omniauth-freshbooks-oauth2/actions/workflows/ci.yml/badge.svg)](https://github.com/dan1d/omniauth-freshbooks-oauth2/actions/workflows/ci.yml)

An OmniAuth strategy for authenticating with [FreshBooks](https://www.freshbooks.com/) using OAuth 2.0.

**Compatible with OmniAuth 2.0+** - This gem is designed for modern Rails applications using OmniAuth 2.0 or later with multi-business support.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'omniauth-freshbooks-oauth2'
```

Then execute:

```bash
$ bundle install
```

Or install it yourself:

```bash
$ gem install omniauth-freshbooks-oauth2
```

## FreshBooks Developer Setup

1. Go to the [FreshBooks Developer Page](https://my.freshbooks.com/#/developer)
2. Create a new app or select an existing one
3. Note your **Client ID** and **Client Secret**
4. Configure your **Redirect URIs** (e.g., `https://yourapp.com/auth/freshbooks_oauth2/callback`)

For more details, read the [FreshBooks OAuth 2.0 documentation](https://www.freshbooks.com/api/authentication).

## Usage

### Standalone OmniAuth

Add the middleware to your application in `config/initializers/omniauth.rb`:

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :freshbooks_oauth2,
           ENV['FRESHBOOKS_CLIENT_ID'],
           ENV['FRESHBOOKS_CLIENT_SECRET']
end

# Required for OmniAuth 2.0+
OmniAuth.config.allowed_request_methods = %i[get post]
```

You can now access the OmniAuth FreshBooks URL at `/auth/freshbooks_oauth2`.

### With Devise

Add the provider to your Devise configuration in `config/initializers/devise.rb`:

```ruby
config.omniauth :freshbooks_oauth2,
                ENV['FRESHBOOKS_CLIENT_ID'],
                ENV['FRESHBOOKS_CLIENT_SECRET']
```

**Do not** create a separate `config/initializers/omniauth.rb` file when using Devise.

Add to your routes in `config/routes.rb`:

```ruby
devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }
```

Make your User model omniauthable in `app/models/user.rb`:

```ruby
devise :omniauthable, omniauth_providers: [:freshbooks_oauth2]
```

Create the callbacks controller at `app/controllers/users/omniauth_callbacks_controller.rb`:

```ruby
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def freshbooks_oauth2
    @user = User.from_omniauth(request.env['omniauth.auth'])

    if @user.persisted?
      flash[:notice] = I18n.t('devise.omniauth_callbacks.success', kind: 'FreshBooks')
      sign_in_and_redirect @user, event: :authentication
    else
      session['devise.freshbooks_data'] = request.env['omniauth.auth'].except('extra')
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
    end
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{failure_message}"
  end
end
```

For your views, create a login button:

```erb
<%= button_to "Sign in with FreshBooks", user_freshbooks_oauth2_omniauth_authorize_path, method: :post %>
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `redirect_uri` | Auto-generated | Custom redirect URI (optional). |

### Example with all options:

```ruby
provider :freshbooks_oauth2,
         ENV['FRESHBOOKS_CLIENT_ID'],
         ENV['FRESHBOOKS_CLIENT_SECRET'],
         redirect_uri: 'https://myapp.com/auth/freshbooks_oauth2/callback'
```

## Auth Hash

Here's an example of the authentication hash available in the callback via `request.env['omniauth.auth']`:

```ruby
{
  "provider" => "freshbooks_oauth2",
  "uid" => "ABC123",  # First business membership's account_id
  "info" => {
    "email" => "user@example.com",
    "first_name" => "John",
    "last_name" => "Doe",
    "name" => "John Doe",
    "account_id" => "ABC123",
    "business_name" => "Acme Restaurant"
  },
  "credentials" => {
    "token" => "ACCESS_TOKEN",
    "refresh_token" => "REFRESH_TOKEN",
    "expires_at" => 1704067200,
    "expires" => true
  },
  "extra" => {
    "account_id" => "ABC123",
    "business_memberships" => [
      {
        "id" => 789,
        "role" => "owner",
        "business" => {
          "id" => 456,
          "account_id" => "ABC123",
          "name" => "Acme Restaurant"
        }
      }
    ],
    "raw_info" => {
      "id" => 123456,
      "first_name" => "John",
      "last_name" => "Doe",
      "email" => "user@example.com",
      "business_memberships" => [...]
    }
  }
}
```

## Multi-Business Support

FreshBooks users can belong to multiple businesses. After authentication, the strategy fetches the user's identity via `GET /auth/api/v1/users/me` which includes all `business_memberships`.

- The `uid` is set to the **first business's `account_id`**
- All business memberships are available in `extra.business_memberships`
- Each membership includes `business.account_id` and `business.name`

To make API calls for a specific business, use the `account_id` in the URL path:

```ruby
response = Faraday.get("https://api.freshbooks.com/accounting/account/#{account_id}/invoices/invoices") do |req|
  req.headers['Authorization'] = "Bearer #{access_token}"
  req.headers['Content-Type'] = 'application/json'
end
```

## FreshBooks OAuth 2.0 Specifics

This gem handles several FreshBooks-specific OAuth 2.0 behaviors:

1. **JSON Token Exchange**: FreshBooks requires `Content-Type: application/json` for the token exchange endpoint (not the standard `application/x-www-form-urlencoded`).

2. **Credentials in Body**: Client ID and secret are sent in the JSON request body (not as HTTP Basic Auth).

3. **Split Endpoints**: FreshBooks uses `auth.freshbooks.com` for authorization and `api.freshbooks.com` for token exchange and API calls.

4. **Long-Lived Access Tokens**: Access tokens expire in **12 hours** (much longer than most providers).

5. **Single-Use Refresh Tokens**: Refresh tokens never expire but are **single-use**. Each refresh returns a new refresh token and the old one is invalidated. Always save the new refresh token!

6. **Identity Endpoint**: User and business info is fetched from `/auth/api/v1/users/me` after authentication.

## Token Management

FreshBooks access tokens expire after **12 hours**. Refresh tokens **never expire** but are single-use.

Store tokens securely and implement refresh logic:

```ruby
def self.from_omniauth(auth)
  user = where(provider: auth.provider, uid: auth.uid).first_or_create do |u|
    u.email = auth.info.email
    u.password = Devise.friendly_token[0, 20]
  end

  # Update tokens on each login
  user.update(
    freshbooks_access_token: auth.credentials.token,
    freshbooks_refresh_token: auth.credentials.refresh_token,
    freshbooks_token_expires_at: Time.at(auth.credentials.expires_at),
    freshbooks_account_id: auth.info.account_id,
    freshbooks_business_name: auth.info.business_name
  )

  user
end
```

## Token Refresh

This gem includes a `TokenClient` class to easily refresh tokens in your Rails app.

### Important: Single-Use Refresh Tokens

**FreshBooks refresh tokens are single-use.** Each time you refresh, you get a new refresh token and the old one is invalidated. Always save the new refresh token returned from the refresh call!

### Basic Usage

```ruby
# Create a client instance
client = OmniAuth::FreshbooksOauth2::TokenClient.new(
  client_id: ENV['FRESHBOOKS_CLIENT_ID'],
  client_secret: ENV['FRESHBOOKS_CLIENT_SECRET'],
  redirect_uri: ENV['FRESHBOOKS_REDIRECT_URI']
)

# Refresh an expired token
result = client.refresh_token(account.freshbooks_refresh_token)

if result.success?
  account.update!(
    freshbooks_access_token: result.access_token,
    freshbooks_refresh_token: result.refresh_token,  # Always save the new one!
    freshbooks_token_expires_at: Time.at(result.expires_at)
  )
else
  Rails.logger.error "Token refresh failed: #{result.error}"
end
```

### Check Token Expiration

```ruby
# Check if token is expired (with 5-minute buffer by default)
client.token_expired?(account.freshbooks_token_expires_at)

# Custom buffer (e.g., refresh 1 hour before expiry)
client.token_expired?(account.freshbooks_token_expires_at, buffer_seconds: 3600)
```

### Rails Service Example

```ruby
# app/services/freshbooks_api_service.rb
class FreshBooksApiService
  def initialize(account)
    @account = account
    @client = OmniAuth::FreshbooksOauth2::TokenClient.new(
      client_id: ENV['FRESHBOOKS_CLIENT_ID'],
      client_secret: ENV['FRESHBOOKS_CLIENT_SECRET'],
      redirect_uri: ENV['FRESHBOOKS_REDIRECT_URI']
    )
  end

  def with_valid_token
    refresh_if_expired!
    yield @account.freshbooks_access_token
  end

  private

  def refresh_if_expired!
    return unless @client.token_expired?(@account.freshbooks_token_expires_at)

    result = @client.refresh_token(@account.freshbooks_refresh_token)
    raise "Token refresh failed: #{result.error}" unless result.success?

    @account.update!(
      freshbooks_access_token: result.access_token,
      freshbooks_refresh_token: result.refresh_token,
      freshbooks_token_expires_at: Time.at(result.expires_at)
    )
  end
end

# Usage
FreshBooksApiService.new(current_account).with_valid_token do |token|
  account_id = current_account.freshbooks_account_id
  response = Faraday.get("https://api.freshbooks.com/accounting/account/#{account_id}/invoices/invoices") do |req|
    req.headers['Authorization'] = "Bearer #{token}"
    req.headers['Content-Type'] = 'application/json'
  end
end
```

### TokenResult Object

The `refresh_token` method returns a `TokenResult` object with:

| Method | Description |
|--------|-------------|
| `success?` | Returns `true` if refresh succeeded |
| `failure?` | Returns `true` if refresh failed |
| `access_token` | The new access token |
| `refresh_token` | The new refresh token (save this!) |
| `expires_at` | Unix timestamp when token expires |
| `expires_in` | Seconds until token expires |
| `error` | Error message if failed |
| `raw_response` | Full response hash from FreshBooks |

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/dan1d/omniauth-freshbooks-oauth2](https://github.com/dan1d/omniauth-freshbooks-oauth2).

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a new Pull Request

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rspec` to run the tests.

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
