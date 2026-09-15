# Contributing

Run `make test` and `make bundle` before opening a pull request. Include the problem, expected behavior, actual behavior, macOS version, app version, and Codex version.

For account-specific problems, describe only the window durations and which fields were missing. Do not paste raw account responses, emails, account IDs, auth files, browser cookies, or tokens. Use synthetic fixtures for tests and screenshots.

Core changes should preserve missing values, handle weekly-only and multiple-bucket responses, and avoid assuming a plan-to-window mapping. Any new network behavior or stored data must be documented.

Useful contributions: compatibility checks on other macOS versions, accessibility improvements, localization corrections, and clearly scoped bug fixes. Please describe the user need before adding a large feature.
