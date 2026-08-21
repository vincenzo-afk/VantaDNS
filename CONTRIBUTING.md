# Contributing to VantaDNS

First off, thank you for considering contributing to VantaDNS! It's people like you that make VantaDNS such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

This section guides you through submitting a bug report for VantaDNS. Following these guidelines helps maintainers and the community understand your report, reproduce the behavior, and find related reports.

*   **Check the [troubleshooting guide](docs/troubleshooting.md)** to see if the issue is already documented.
*   **Search the [issue tracker](https://github.com/vincenzo-afk/VantaDNS/issues)** to see if the bug has already been reported.
*   **Use the Bug Report template** when opening a new issue.

### Suggesting Enhancements

This section guides you through submitting an enhancement suggestion for VantaDNS, including completely new features and minor improvements to existing functionality.

*   **Check the [roadmap](README.md#features--roadmap)** to see if the feature is already planned.
*   **Search the [issue tracker](https://github.com/vincenzo-afk/VantaDNS/issues)** to see if the enhancement has already been suggested.
*   **Use the Feature Request template** when opening a new issue.

### Pull Requests

The process which allows for your contributions to be merged into the main codebase:

1.  **Fork the repository** and create your branch from `main`.
2.  **Install the Rust toolchain** (`rustup default stable`).
3.  **Ensure the code builds** and all tests pass (`cargo test`).
4.  **Follow the Rust style guidelines** (run `cargo fmt`).
5.  **Write a clear, descriptive commit message**.
6.  **Open a Pull Request** with a clear description of the changes.

## Development Setup

### Rust Core

```bash
cd dns-core
cargo build --release
cargo test
```

### Android Cross-Compilation

To build the ARM64 Android binary:

```bash
# Requires Android NDK installed
cargo build --release --target aarch64-linux-android
```

See [docs/android-deployment.md](docs/android-deployment.md) for more details.

## Style Guidelines

*   Use `cargo fmt` for formatting.
*   Follow the standard Rust naming conventions.
*   Keep functions small and focused.
*   Document all public APIs.

## Questions?

If you have questions, feel free to open an issue or contact the maintainer at itsmebk2007@gmail.com.
