# Codex access-token refresh for AgentBar

Date: 2026-08-19
Upstream baseline: [`openai/codex` commit `3b45c29062ff0e76e71c91b6753290400e7fa8da`](https://github.com/openai/codex/tree/3b45c29062ff0e76e71c91b6753290400e7fa8da)

## Bottom line

OpenAI's supported integration is to let Codex refresh its own managed ChatGPT session and persist the resulting credential bundle; its CI guidance explicitly says not to call the OAuth token endpoint independently. A direct AgentBar refresh client is therefore an upstream-coupled compatibility layer, not a documented public OpenAI API. It can be implemented, but only for file-backed, Codex-managed ChatGPT credentials and only with strict serialization. [OpenAI authentication guide](https://learn.chatgpt.com/docs/auth#login-caching) · [OpenAI CI/CD auth guide](https://learn.chatgpt.com/docs/auth/ci-cd-auth#why-this-works)

No implementation can guarantee permanent login. OpenAI says the same session is not guaranteed to last forever, and identifies expired/revoked refresh tokens, concurrent rotation, and restoration of an old credential copy as re-login cases. OAuth also permits security-event revocation and inactivity expiry. [OpenAI CI/CD auth guide](https://learn.chatgpt.com/docs/auth/ci-cd-auth#what-to-do-when-refresh-stops-working) · [RFC 9700 §4.14.2](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14.2)

## Verified source facts

### Storage and schema

Codex can cache credentials in `CODEX_HOME/auth.json` (normally `~/.codex/auth.json`), the OS credential store, or `auto` mode; a file is therefore not guaranteed to exist or be authoritative. The current source also has an internal ephemeral mode. Successful keyring persistence removes the file fallback. [`AuthCredentialsStoreMode`](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/config/src/types.rs#L105-L118) · [`DirectKeyringAuthStorage.save`](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/storage.rs#L291-L305) · [OpenAI credential-storage docs](https://learn.chatgpt.com/docs/auth#credential-storage)

For refreshable managed ChatGPT auth, the relevant serialized shape is:

```json
{
  "auth_mode": "chatgpt",
  "OPENAI_API_KEY": null,
  "tokens": {
    "id_token": "<JWT>",
    "access_token": "<JWT>",
    "refresh_token": "<opaque token>",
    "account_id": "<ChatGPT workspace/account ID>"
  },
  "last_refresh": "<timestamp>"
}
```

The complete top-level schema also allows agent identity, personal access token, and Bedrock fields; the token bundle is `id_token`, `access_token`, `refresh_token`, and optional `account_id`. `auth_mode: "chatgptAuthTokens"` is externally managed and is not refreshed by Codex; API-key, personal-access-token, agent-identity, header, and Bedrock modes likewise do not enter this refresh path. [`AuthDotJson`](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/storage.rs#L38-L60) · [`TokenData`](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/token_data.rs#L10-L25) · [`AuthMode`](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/protocol/src/auth.rs#L6-L33) · [refresh-mode dispatch](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L2780-L2801)

AgentBar's `.codex/accounts/*.auth.json` files and registry are AgentBar-owned snapshots, not a Codex storage mode; upstream recognizes one configured auth store per `CODEX_HOME`. AgentBar currently reads those snapshots, tries bearer tokens, and records a usage-endpoint `401` without refreshing. [AgentBar storage](https://github.com/terrytan95/AgentBar/blob/b2d4e13c9b2b09d31b29eafb7d6585dc05862bd2/Sources/AgentBar/Services/CodexAccountStorage.swift#L51-L105) · [AgentBar usage auth path](https://github.com/terrytan95/AgentBar/blob/b2d4e13c9b2b09d31b29eafb7d6585dc05862bd2/Sources/AgentBar/Services/CodexUsageAPISyncer.swift#L161-L249)

### Refresh endpoint, request, and client identity

The current Codex request is:

```http
POST https://auth.openai.com/oauth/token
Content-Type: application/json

{
  "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
  "grant_type": "refresh_token",
  "refresh_token": "<current refresh token>"
}
```

There is no client secret and no scope field. The response parser accepts optional `id_token`, `access_token`, and `refresh_token`. This JSON body is an OpenAI/Codex implementation detail; generic OAuth 2.0 specifies a UTF-8 form-encoded refresh request, so AgentBar must follow the observed Codex contract rather than assume the generic encoding. [Codex request/response implementation](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L1551-L1662) · [RFC 6749 §6](https://www.rfc-editor.org/rfc/rfc6749.html#section-6)

The stock client ID's source of truth is the `CLIENT_ID` constant in `codex-login`; direct `codex login` passes that same constant into the browser flow. Refresh may instead read `CODEX_APP_SERVER_LOGIN_CLIENT_ID`, and the endpoint may read `CODEX_REFRESH_TOKEN_URL_OVERRIDE`. The auth schema does not persist the issuing client ID, so a third-party reader cannot reliably infer whether a nonstandard client ID created a given token. [`CLIENT_ID` and overrides](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L1664-L1677) · [CLI login construction](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/cli/src/login.rs#L138-L160)

### Rotation and persistence

On success, Codex replaces each token only when that field is present, preserves an existing refresh token when the response omits one, sets `last_refresh` to the current time, saves the whole auth object, and reloads its in-memory state. If a new refresh token is returned, RFC 6749 requires discarding the old one; restoring an older file after this point can trigger reuse detection or make the session unrecoverable. [Codex merge/persist flow](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L1525-L1548) · [Codex refresh-and-reload](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L2957-L2975) · [RFC 6749 §6 rotation rule](https://www.rfc-editor.org/rfc/rfc6749.html#section-6)

OAuth's current security BCP requires replay detection for public clients, commonly by refresh-token rotation: each refresh invalidates the previous token, and reuse can revoke the active token family. [RFC 9700 §4.14.2](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14.2)

### Proactive timing and `401` recovery

Current Codex refreshes when the access-token JWT expires within five minutes. If the JWT has no usable `exp`, it falls back to refreshing when `last_refresh` is older than eight days. A protected-resource `401` enters a guarded reload-then-refresh recovery path. [refresh thresholds](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L180-L186) · [proactive decision](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L2871-L2893) · [`401` recovery state machine](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L1928-L1968)

### Concurrency and writes

Within one `AuthManager`, Codex serializes refreshes with a one-permit semaphore. Before using the authority, it reloads storage, requires the same account ID, and skips refresh if another writer already changed the auth snapshot. This is only in-process coordination; it is not a cross-process lock. [`AuthManager` synchronization](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L1978-L2003) · [guarded refresh](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L2716-L2753)

The upstream file backend creates mode `0600`, truncates the destination, writes, and flushes; it does not use a temporary-file rename or filesystem-wide transaction. OpenAI's operational guidance compensates by requiring one auth file per runner or serialized stream and explicitly forbidding concurrent jobs or machines from sharing it. [`FileAuthStorage.save`](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/storage.rs#L191-L218) · [OpenAI operational rules](https://learn.chatgpt.com/docs/auth/ci-cd-auth#operational-rules-that-matter)

### Terminal versus retryable failures

Current Codex treats any token-endpoint HTTP `401`, plus backend codes `refresh_token_expired`, `refresh_token_reused`, and `refresh_token_invalidated`, as permanent for the current auth snapshot. An account-ID mismatch during guarded reload is also terminal. The permanent result is cached until the auth snapshot changes. [failure classification](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L1580-L1621) · [account mismatch](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L2734-L2753) · [auth-scoped failure cache](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L2453-L2469)

Transport errors, response-decoding errors, persistence errors, and otherwise-unrecognized non-`401` HTTP failures are transient in the current implementation. OAuth's standard `invalid_grant` covers an invalid, expired, revoked, wrong-client, or otherwise mismatched refresh token, so AgentBar should also regard an explicit `invalid_grant` as requiring re-login even if OpenAI changes its proprietary error-code shape. [Codex transient paths](https://github.com/openai/codex/blob/3b45c29062ff0e76e71c91b6753290400e7fa8da/codex-rs/login/src/auth/manager.rs#L1564-L1591) · [RFC 6749 §5.2](https://www.rfc-editor.org/rfc/rfc6749.html#section-5.2)

## AgentBar implementation recommendations

These are recommendations, not claims about OpenAI's public contract.

1. **Keep Codex authoritative for the active session.** Prefer re-reading credentials after Codex's built-in refresh. Do not silently run a model request merely to refresh. If AgentBar directly refreshes inactive account snapshots, label the feature internally as upstream-coupled and gate it to `auth_mode == "chatgpt"` with a nonempty refresh token. Keyring, external-token, API-key, PAT, agent-identity, and Bedrock modes should remain read-only or unsupported.
2. **Use Codex's timing and one retry.** Refresh at `exp <= now + 5 minutes`; use the eight-day `last_refresh` fallback only when `exp` cannot be parsed. On a usage `401`, guarded-reload once, refresh once, then retry that usage request once.
3. **Single-flight per credential family.** Serialize by account, then re-read the canonical file and compare account identity plus the refresh token before sending. If either changed, use the newer state instead of refreshing the stale copy. Do not refresh the active `auth.json` concurrently with Codex; an AgentBar-only lock cannot protect against a Codex process that does not honor it.
4. **Persist rotation before reuse.** Merge only fields returned by the server, retain unknown JSON keys, set `last_refresh`, verify the returned token still belongs to the expected account, and atomically replace a same-directory `0600` file. Never restore the old refresh token after a successful response. For the active account, treat `~/.codex/auth.json` as canonical and update the AgentBar snapshot from it only after the canonical write succeeds; for inactive accounts, update only their snapshot until activation.
5. **Fail closed and explain re-login.** Mark expired, reused, invalidated, explicit `invalid_grant`, wrong-client/account, and unrecoverable `401` results as `needsLogin`; do not loop. Back off transient network/5xx/write failures without discarding the last complete credential bundle.
6. **Promise continuity, not permanence.** The product copy can say AgentBar will refresh eligible Codex logins while the refresh grant remains valid. It must not say “permanent login” or “never sign in again.”

The smallest safe scope is refresh support for AgentBar's inactive, file-backed ChatGPT snapshots plus guarded synchronization from the active Codex file. Full keyring integration or simultaneous AgentBar/Codex refresh ownership should wait for an official OpenAI integration surface.
