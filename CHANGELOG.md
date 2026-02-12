# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-12

### Added

- Initial release with OmniAuth 2.0+ compatibility
- Support for FreshBooks OAuth 2.0 authentication
- Multi-business support via identity endpoint with business_memberships
- JSON body token exchange (FreshBooks-specific)
- TokenClient class for easy token refresh with single-use refresh token handling
- `refresh_token` method with result object pattern
- `token_expired?` helper with configurable buffer
- FreshBooks error format parsing (nested response.errors)
- Comprehensive RSpec test suite
- GitHub Actions CI/CD workflow
