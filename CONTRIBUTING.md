# Contributing to RDataCraft

Contributions that improve scientific correctness, accessibility, documentation,
interoperability and reliable desktop behavior are welcome. Please follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Report a problem or propose a change

Search the [issues](https://github.com/AlvinAi-cloud/RDataCraft/issues) first.
Include your app version, operating system and CPU, steps to reproduce, expected
behavior and the smallest synthetic example that demonstrates the problem.
Screenshots and relevant error messages help. Remove credentials, identifiers,
private study data and personal file paths before sharing logs or studies.

For a numerical issue, describe the experimental units, design, method, settings,
expected result and a reproducible R calculation or primary reference. Distinguish
observations, technical replicates, independent biological replicates and paired
measurements. Suggest substantial changes in an issue before implementing them.

For a security or other sensitive report, request a private contact channel from
the maintainer without posting the vulnerability, personal data or credentials.
If no private contact is available, open an issue titled **Private contact
requested**, containing only the request to arrange a private channel.

## Develop and submit

The canonical repository keeps one development branch, `main`. Submit a pull
request from your fork, or attach a patch to an issue. Maintainers integrate
accepted changes into `main`; no additional permanent release branch is needed.
Keep a change focused and preserve unrelated UI behavior and user studies.

See [README.md](README.md) and [PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md) for
platform prerequisites and native build instructions. On macOS, the usual setup
and source checks are:

```sh
python3 scripts/bootstrap.py
python3 scripts/test.py --require-node
```

On Windows, install the prerequisites described in the platform guide, then run
`Rscript --vanilla scripts/install.R` followed by `python scripts/test.py
--require-node`. Bundled R libraries are specific to an operating system and CPU.
Do not copy a runtime from another platform.

For a focused change, run the relevant existing tests first. Add regression
coverage when it demonstrates a meaningful bug or statistical requirement.
Numerical changes should use reproducible benchmarks, cover missing data and
non-estimable cases, and verify multiplicity, uncertainty and assumptions where
applicable. Never replace a failed calculation with a plausible-looking result.

In your pull request or patch, describe the problem, resulting behavior, checks
actually run and any limitations. Include real screenshots for UI changes and
state the OS tested. Do not claim Windows or Apple Silicon execution based on
an Intel Mac test. Disclose substantial AI assistance; review generated code and
verify its calculations and licensing before submitting it.

## Release and licensing

Only maintainers publish releases. GitHub Actions builds and validates all three
installers from the same `main` commit; source, notices, checksums and validation
must match that commit. A failed check needs investigation, not a weaker gate.
See [RELEASE.md](RELEASE.md).

Application contributions are provided under the project's existing GPL-3.0
license. Keep third-party license notices and document new dependencies. Do not
submit proprietary application code, copied artwork, credentials, private studies
or runtime binaries. Changing the project's license requires a separate review.
