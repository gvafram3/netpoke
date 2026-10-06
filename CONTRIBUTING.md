# Contributing to NetPoke

NetPoke is an open-source extension of [Slowpoke](https://github.com/atlas-brown/slowpoke). Contributions are welcome in the form of bug reports, bug fixes, and support for further I/O resources (for example disk I/O) or further benchmarks.

Issues that concern Slowpoke itself, and are not specific to NetPoke's egress hold or experiment harness, are best reported to the [Slowpoke repository](https://github.com/atlas-brown/slowpoke/issues).

## Bug Report

- **Open an issue** describing the problem:
  - Specify the environment (cloud provider, instance type, kernel version, Kubernetes setup, overlay network).
  - Describe the point of failure (e.g., cluster setup, kernel checks, image build, execution, prediction accuracy).
  - Include relevant error messages and logs (for experiment runs: the `<arm>_rep<N>.log` file and the output of `summarize_runs.py`).
- **Propose a fix** via a pull request:
  - Refer to an open issue that clearly describes the problem.
  - Follow the existing coding and directory conventions.
  - Keep changes minimal and scoped.

## Never commit

Private keys (`*.pem`), cloud credentials, and `evaluation/netpoke/cluster/config.env` (it holds your machines' addresses). `.gitignore` blocks these; check `git status` before every commit.
