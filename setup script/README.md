# Team 2 VM Setup: Ollama and ChromaDB

Environment setup for the CYB691 capstone project, **LLM and AI Security Robustness**.

The `setup_vm.sh` script prepares an Ubuntu 24.04 VM with Ollama, selected local models, a Python virtual environment, and a persistent ChromaDB store for RAG testing.

> **Script version:** This guide describes the revised script supporting `--app-user`, `--model both`, and opt-in `--test-model`. It does not describe the older fixed-version script.

## Table of Contents

- [Important Script Correction](#important-script-correction)
- [Environment Requirements](#environment-requirements)
- [Quick Start](#quick-start)
- [What Setup Does](#what-setup-does)
- [Optional Version Pins](#optional-version-pins)
- [Loading the RAG Corpus](#loading-the-rag-corpus)
- [Files and Directories](#files-and-directories)
- [Connecting the Testing Tool](#connecting-the-testing-tool)
- [Command-Line Options](#command-line-options)
- [Verification and Troubleshooting](#verification-and-troubleshooting)
- [Safety and Validation Limits](#safety-and-validation-limits)

## Important Script Correction

The pasted script contains Markdown-formatted URLs in two `curl` commands. Shell scripts require plain URLs, not Markdown links.

Before running the script, make sure the installer command reads:

```bash
curl --fail --silent --show-error --location \
  https://ollama.com/install.sh -o "$INSTALLER"
```

Inside the existing Ollama readiness loop, the API check must read:

```bash
if curl -fsS http://127.0.0.1:11434/api/version >/dev/null; then
  READY=1
  break
fi
```

Check the corrected script’s syntax:

```bash
bash -n setup_vm.sh
```

No output means Bash found no syntax errors. This does not verify runtime behavior, dependency compatibility, or GPU readiness.

## Environment Requirements

| Item | Requirement or Project Configuration |
| :--- | :--- |
| Operating system | Ubuntu 24.04 |
| Init system | systemd |
| Privileges | Root through `sudo`, including ChromaDB-only mode |
| Application account | An existing non-root account, such as `ubuntu` |
| Project VM | AWS EC2 `g6.xlarge` with an NVIDIA L4 |
| Storage plan | 100 GB root volume; verify available space before downloading models |
| Administration | AWS Systems Manager Session Manager |
| Network | Outbound access for packages, Ollama, model weights, and embedding downloads |

The script rejects unsupported operating systems and hosts without systemd. It does not check free disk space or configure AWS quotas, IAM, Session Manager, security groups, or budget controls.

> **Security:** Run this environment on team-controlled VMs using synthetic data. The local workflow does not require inbound security-group rules, and the script does not change firewall settings.

## Quick Start

Connect to the VM through AWS Systems Manager Session Manager. Place the corrected `setup_vm.sh` on the VM and change to its directory:

```bash
cd /path/to/script
```

Replace `/path/to/script` with the actual directory containing the script.

Check that the intended application account exists:

```bash
id ubuntu
```

The commands below explicitly use `ubuntu` as the application user so the SSM login account does not determine file ownership.

### GPT-OSS Host

Run this command on the VM assigned to GPT-OSS:

```bash
sudo bash setup_vm.sh \
  --model gpt-oss \
  --app-user ubuntu \
  --app-dir /home/ubuntu/team2-llm-security \
  --test-model
```

### Gemma 2 Host

Run this command on the separate VM assigned to Gemma 2:

```bash
sudo bash setup_vm.sh \
  --model gemma2 \
  --app-user ubuntu \
  --app-dir /home/ubuntu/team2-llm-security \
  --test-model
```

The two-host experiment uses one VM per model. The same script handles both hosts.

### Both Models on One Host

The script also supports installing both models:

```bash
sudo bash setup_vm.sh \
  --model both \
  --app-user ubuntu \
  --app-dir /home/ubuntu/team2-llm-security \
  --test-model
```

This is an alternative deployment, not the team’s two-host arrangement. The script configures Ollama for one loaded model and one parallel request, but does not verify that either model fits the available GPU memory, RAM, or storage.

> **Model testing is optional:** The script runs generation tests only when `--test-model` is supplied. Completing setup without that option does not demonstrate inference readiness.

## What Setup Does

| Stage | Behavior |
| :--- | :--- |
| Validation | Requires root, a non-root application user, an absolute application path, Ubuntu 24.04, and systemd |
| System packages | Updates apt metadata and installs certificates, curl, Python, venv support, and pip |
| Directories | Creates the application directories with the selected user as owner |
| NVIDIA driver | Installs a driver if `nvidia-smi` fails, unless `--skip-driver` is supplied |
| Ollama installation | Installs Ollama if absent, or reruns the installer when `OLLAMA_VERSION` is supplied |
| Ollama service | Configures loopback binding, one loaded model, and one parallel request; enables and restarts the service |
| Readiness | Waits for a successful response from the local Ollama version endpoint |
| Models | Pulls `gpt-oss:20b`, `gemma2:27b`, or both |
| Python environment | Creates a venv if needed, installs packages when required, runs `pip check`, and records `pip freeze` |
| ChromaDB | Synchronizes the collection with the source corpus |
| Evidence | Writes retrieval results and the environment manifest |
| Optional test | Runs one generation request per selected model with `--test-model` |

### Driver Reboot

If the driver is installed but not active, the script stops and requests a reboot. Reboot the VM, reconnect through Session Manager, and rerun the same command.

Secure Boot configuration may also require attention. The script does not reboot the VM automatically.

### Ollama Configuration

The script writes:

```text
/etc/systemd/system/ollama.service.d/team2.conf
```

With these settings:

```ini
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
```

The script checks API availability, not actual listening addresses. Review the effective configuration and listeners, especially if other Ollama service overrides already exist.

### Optional Generation Test

With `--test-model`, each selected model receives a request using:

| Setting | Value |
| :--- | :--- |
| Endpoint | `/api/generate` |
| Prompt | `Reply with a short greeting.` |
| Context | `8192` |
| Prediction limit | `64` |
| Temperature | `0` |
| Keep alive | `0` |
| Request timeout | `1800` seconds |

The script raises errors for HTTP failures and API error fields. It prints the response and thinking fields, but does not require a nonempty answer or evaluate correctness.

The context setting applies only to this test request. The script does not configure a service-wide context default.

## Optional Version Pins

The revised script does not contain fixed Ollama, ChromaDB, or requests version pins.

| Environment Variable | Purpose |
| :--- | :--- |
| `OLLAMA_VERSION` | Requests a specific Ollama version through the upstream installer |
| `CHROMADB_VERSION` | Requests `chromadb==VERSION` |
| `REQUESTS_VERSION` | Requests `requests==VERSION` |

To specify reviewed versions through `sudo`, use this pattern and replace every placeholder:

```bash
sudo env \
  OLLAMA_VERSION="REPLACE_WITH_REVIEWED_VERSION" \
  CHROMADB_VERSION="REPLACE_WITH_REVIEWED_VERSION" \
  REQUESTS_VERSION="REPLACE_WITH_REVIEWED_VERSION" \
  bash setup_vm.sh \
    --model gpt-oss \
    --app-user ubuntu \
    --app-dir /home/ubuntu/team2-llm-security \
    --test-model
```

Version behavior:

- **Fresh installation:** Without pins, package installation resolves available releases.
- **Existing Ollama:** Retained when no `OLLAMA_VERSION` is supplied.
- **Existing Python environment:** Package installation is skipped when `config/requirements-installed.txt` exists and neither Python package pin is supplied.
- **Partial Python pins:** Supplying either Python package pin triggers installation of both package specifications; the other specification remains unpinned.
- **Verification:** The script records observed versions but does not compare the running Ollama version with the requested version.

Review package compatibility and security before choosing pins. The package inventory is a record of the installed environment, not an automatically enforced lockfile.

## Loading the RAG Corpus

Place approved UTF-8 `.txt` and `.md` files in:

```text
/home/ubuntu/team2-llm-security/data/corpus/
```

Subdirectories are supported.

Run the following command to synchronize the corpus:

```bash
sudo bash setup_vm.sh \
  --chromadb-only \
  --app-user ubuntu \
  --app-dir /home/ubuntu/team2-llm-security
```

> **ChromaDB-only still requires sudo:** This mode also performs apt update/install steps. It skips driver setup, Ollama installation and service configuration, model pulls, and generation tests.

### How Synchronization Works

| Behavior | Details |
| :--- | :--- |
| Collection | `rag_corpus` |
| Storage | Embedded `PersistentClient` |
| Embedding function | `DefaultEmbeddingFunction`, identified as `all-MiniLM-L6-v2` |
| Chunk size | 800-character windows |
| Chunk interval | 700 characters |
| Overlap | 100 characters before whitespace trimming |
| Record IDs | Hash of relative path, offset, and chunk text |
| Updates | Upserts current chunks, then deletes stale records |
| Retrieval test | Up to three results for `What does this corpus describe?` |

Changed and deleted source files are synchronized automatically. An explicit reset is not required simply because the corpus changed.

> **Important:** This loader exclusively manages `rag_corpus`. Synchronization deletes records not represented by its current source files, including records added separately by another tool.

If the source corpus is empty, synchronization removes existing collection records and skips retrieval, unless sample seeding is requested.

### Reset the Collection

To delete and recreate only `rag_corpus` before ingestion:

```bash
sudo bash setup_vm.sh \
  --chromadb-only \
  --app-user ubuntu \
  --app-dir /home/ubuntu/team2-llm-security \
  --reset-rag
```

This does not delete source documents or other collections.

### Add a Sample Document

To seed a sample when no eligible corpus files exist:

```bash
sudo bash setup_vm.sh \
  --chromadb-only \
  --app-user ubuntu \
  --app-dir /home/ubuntu/team2-llm-security \
  --with-sample-corpus
```

The sample file is named `SAMPLE_ONLY.txt`. Remove it before loading the final experimental corpus, then rerun synchronization to remove its chunks.

## Files and Directories

```text
team2-llm-security/
├── config/
│   ├── environment_manifest.json
│   ├── requirements-installed.txt
│   └── retrieval_smoke_test.json
├── data/
│   ├── chroma/
│   └── corpus/
├── scripts/
│   └── rag_setup.py
└── venv/
```

| Path | Purpose |
| :--- | :--- |
| `data/corpus/` | Source Markdown and text documents |
| `data/chroma/` | Persistent database files; do not edit manually |
| `scripts/rag_setup.py` | Generated ingestion, retrieval, and manifest helper |
| `config/requirements-installed.txt` | Package inventory generated by `pip freeze` |
| `config/retrieval_smoke_test.json` | Retrieved records or an empty-corpus skip reason |
| `config/environment_manifest.json` | Environment, corpus, package, Ollama, and GPU observations |
| `venv/` | Application Python virtual environment |

This script does not create `results/`, `data/web_root/`, a root-level `requirements.txt`, `rag_load.py`, or a separate `manifest.py`.

## Connecting the Testing Tool

Run application code as the configured application account. For the examples in this guide:

```bash
sudo -iu ubuntu
source /home/ubuntu/team2-llm-security/venv/bin/activate
```

Use the same persistent path, collection, and embedding function:

```python
import chromadb
from chromadb.utils.embedding_functions import DefaultEmbeddingFunction

client = chromadb.PersistentClient(
    path="/home/ubuntu/team2-llm-security/data/chroma"
)

collection = client.get_collection(
    name="rag_corpus",
    embedding_function=DefaultEmbeddingFunction(),
)

if collection.count():
    results = collection.query(
        query_texts=["What does this corpus describe?"],
        n_results=min(3, collection.count()),
    )
    print(results)
else:
    print("Load corpus documents before querying.")
```

ChromaDB runs embedded without an HTTP server. Initial use of the default embedding function can require an outbound model download.

## Command-Line Options

| Option | Description |
| :--- | :--- |
| `--model gpt-oss` | Pull GPT-OSS 20B |
| `--model gemma2` | Pull Gemma 2 27B |
| `--model both` | Pull both models |
| `--chromadb-only` | Configure Python, synchronize the corpus, and record the environment without host/model setup |
| `--app-user USER` | Existing non-root application user; otherwise defaults to `SUDO_USER` |
| `--app-dir PATH` | Absolute application directory; defaults to the selected user’s home plus `/team2-llm-security` |
| `--skip-driver` | Skip driver installation; does not force CPU inference |
| `--reset-rag` | Delete and recreate only `rag_corpus` |
| `--with-sample-corpus` | Seed a sample if no eligible corpus files exist |
| `--test-model` | Run generation tests in full setup mode |
| `--help`, `-h` | Show built-in help |

The older flags `--skip-model-pull`, `--skip-model-test`, `--skip-chromadb`, and `--with-cuda-toolkit` are not supported.

The generated Python helper does not accept `--query` or `--reset` arguments. Use the shell script’s documented options.

## Verification and Troubleshooting

### Check GPU and Models

```bash
nvidia-smi
```

```bash
curl -fsS http://127.0.0.1:11434/api/version
ollama list
```

### Inspect the Service

```bash
sudo systemctl cat ollama
sudo journalctl -u ollama -n 100 --no-pager
```

If `ss` is installed, inspect listening addresses:

```bash
sudo ss -ltnp
```

The setup script does not explicitly install that diagnostic utility.

### Check Python Packages

```bash
sudo -u ubuntu \
  /home/ubuntu/team2-llm-security/venv/bin/python \
  -m pip check
```

### View Recorded Evidence

```bash
sudo -u ubuntu python3 -m json.tool \
  /home/ubuntu/team2-llm-security/config/environment_manifest.json
```

```bash
sudo -u ubuntu python3 -m json.tool \
  /home/ubuntu/team2-llm-security/config/retrieval_smoke_test.json
```

### Common Problems

| Problem | Recommended Action |
| :--- | :--- |
| Syntax error near `(` | Replace Markdown links in the shell script with plain URLs |
| Application user rejected | Specify an existing non-root account with `--app-user` |
| OS or systemd check fails | Use an Ubuntu 24.04 systemd VM |
| Driver is not active | Reboot as instructed, check Secure Boot if needed, and rerun |
| Ollama is not ready | Inspect service status, logs, and existing service overrides |
| Package check fails | Resolve the dependency conflict reported by pip |
| Retrieval is skipped | Add nonempty UTF-8 `.txt` or `.md` documents and synchronize again |
| Separately inserted chunks disappear | The loader removes records not represented by its corpus |
| Model generation fails | Inspect API errors, service logs, storage, RAM, and GPU state |

## Safety and Validation Limits

- **Environment evidence:** The manifest records platform/Python information, installed package versions, corpus hashes, RAG settings, collection size, available Ollama API information, and GPU observations.
- **Model identity:** The raw Ollama model-list response is recorded when available, but the script does not enforce an expected digest.
- **Probe history:** A failed Ollama probe can leave older successful data in the manifest alongside an error. A later successful probe does not remove an older error field. Review timestamps and fields together.
- **GPU observations:** A failed GPU probe replaces the GPU field with `nvidia-smi unavailable`.
- **Private information:** Review manifests and retrieval output for host details, paths, and document content before publication.
- **Dependency review:** Reassess security and compatibility when selecting versions; this guide does not establish that any selected release is vulnerability-free.
- **Validation status:** This README describes the revised script supplied in the conversation. Tests previously reported for the older script do not validate this revision.

Before experiments, verify both real VMs, freeze the corpus and dependency choices, compare model identities, and preserve acceptance-test evidence. A `Setup complete` message alone does not prove GPU inference readiness, retrieval quality, strict loopback enforcement, or experimental reproducibility.
