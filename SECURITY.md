# Security Policy

This repository holds Team 2's CYB 691 capstone test harness for prompt
injection research against locally hosted LLMs (`prompt_tool.py` v1.0, the
technique specifications, the synthetic RAG corpus, and setup scripts). It is
an authorized academic research tool, not a production service.

## Supported versions

| Version | Status |
| --- | --- |
| Week 12 release (`v1.0-week12`) and current `main` | Supported |
| Earlier commits | Not supported |

## Reporting a vulnerability or sensitive data

Please do not open a public issue that contains exploit details, credentials,
or any data that looks real.

1. Preferred: use GitHub private vulnerability reporting from this
   repository's **Security** tab ("Report a vulnerability").
2. If that option is unavailable, open a short public issue titled
   "Security contact request" with no technical details, and a maintainer
   will reach out.

Report anything that exposes secrets, account or instance identifiers, IP
addresses, raw run logs, or canary values, as well as bugs that could send the
live canary off the target host, fetch an external URL, or bind Ollama to a
non-loopback address. We aim to acknowledge reports within 3 business days
during the Fall 2026 semester.

## What this repository does and does not contain

- All canaries, markers, companies, and documents are synthetic. Canaries are
  minted locally per case (`CANARY-` plus 8 hex characters) and appear only in
  the target model's system message and the VM-side log.
- Raw logs (`results/runs.jsonl`, `replays/`, frozen JSONL files) stay on the
  team VMs and are not committed. Published results are sanitized notes.
- No API keys, AWS account IDs, instance IDs, or IP addresses belong in this
  repository. If you find one, report it as above.

## Security assumptions for running the harness

- **Isolated host.** Run only on a VM you own and are authorized to test.
  Ollama must listen on `127.0.0.1:11434` only. Do not open port 11434 or SSH
  in the security group; the team uses AWS SSM Session Manager.
- **Credentials.** The Perplexity Agent API key is loaded from AWS SSM
  Parameter Store by `API-setup/setup_api.sh` into the current shell only.
  Never paste it into code, config, logs, or chat. `replay` and `status` need
  no key.
- **Privileges.** `setup_vm.sh` requires `sudo` to install packages, the
  NVIDIA driver, and Ollama. `prompt_tool.py` runs as an unprivileged user.
- **Network.** The tool contacts only local Ollama and, for `generate` and
  `smoke`, the Perplexity Agent API. URL-poisoning cases are restricted to
  `https://example.test/` and are never fetched.
- **Content.** Test objectives are harmless proxies (leak a synthetic canary,
  emit a marker string). Do not adapt the harness to elicit real harmful
  content or to target systems or models you do not control.

## Known limitations

- Retrieved RAG chunks are appended as plain text with no delimiter hardening;
  this is the intended undefended baseline, not a recommended design.
- Results are single-reviewer first reads on two specific model builds and do
  not establish that either model is safe in other deployments.
- Python dependencies are pinned in `requirements.txt`; the Ollama server
  version is not pinned unless `OLLAMA_VERSION` is set.
