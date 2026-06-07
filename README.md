# KeyNest

KeyNest is a local-first macOS app for keeping LLM provider API keys in one place and tracking monthly usage/budget.

## Current MVP

- Native SwiftUI macOS interface.
- Provider vault for OpenAI, Anthropic, Google AI, OpenRouter, DeepSeek, Aliyun Bailian, MiniMax, SiliconFlow, Zhipu AI, and custom endpoints.
- Distinct provider icons and colors in the app UI.
- API keys are stored in macOS Keychain, not in JSON files.
- Provider metadata and usage snapshots are stored under Application Support.
- Dashboard shows total monthly spend, budget, and provider status.
- Provider detail view tracks budget usage and usage history.
- Manual `Sync Now` and automatic sync every 6 hours while the app is open. The app does not read secrets from Keychain on launch; the first automatic sync waits 6 hours.
- DeepSeek automatic sync reads account balance from `/user/balance`; monthly spend is still tracked through manual usage entries until a provider exposes cost usage data.
- MiniMax automatic sync verifies the saved API key through `GET /v1/models`; MiniMax public docs do not expose billing/usage sync yet.
- SiliconFlow automatic sync reads `chargeBalance` through the official `GET https://api.siliconflow.cn/v1/user/info` endpoint.
- Zhipu AI automatic sync first tries the undocumented `GET https://open.bigmodel.cn/api/finance/balance` endpoint, then falls back to verifying the API key through `GET /models`. Official docs only expose cash balance in the web console.
- OpenRouter stores two optional keys: the inference API key for vault access, and a management API key for balance sync. Sync reads account credits from `GET https://openrouter.ai/api/v1/credits` via the management key, and per-key limits/monthly usage from `GET https://openrouter.ai/api/v1/key` via the inference key.
- Aliyun Bailian automatic sync verifies the saved model API key through the OpenAI-compatible models endpoint. If Aliyun AK/SK is saved, it also queries Alibaba Cloud BSS `QueryAccountBalance` for cash balance and `QueryAccountBill` for the current account bill.
- Saved API keys can be revealed and copied from the provider detail view.
- Custom macOS app icon generated into `Assets/AppIcon.icns` during packaging.

## Run

```bash
swift run
```

## Package as a macOS app

```bash
make app
```

This creates `dist/KeyNest.app`, which can be launched from Finder by double-clicking.

You can also open the folder/package in Xcode and run the `KeyNest` executable target.

## Storage

- Secrets: macOS Keychain service `com.llmvault.provider-keys`.
- Non-secret app data: `~/Library/Application Support/LLMVault/providers.json`.
- Usage snapshots: `~/Library/Application Support/LLMVault/usage.json`.
- Sync status: `~/Library/Application Support/LLMVault/sync.json`.

## Next API Work

Real cost monitoring needs provider-specific usage adapters because billing APIs differ by provider and often require organization/project scopes.

Suggested next slices:

1. Add a `UsageSyncService` protocol with one adapter per provider.
2. Add provider-specific settings such as organization ID, project ID, or billing account ID.
3. Implement OpenAI usage/cost sync first, then Anthropic and OpenRouter.
4. Add a background refresh cadence and budget threshold notifications.
5. Add export to CSV/JSON for accounting.
# keynest
