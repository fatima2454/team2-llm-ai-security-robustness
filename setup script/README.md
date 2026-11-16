# LLM Security Lab: VM Setup Guide

Automated environment setup for the Team 2 CYB691 capstone project, **LLM and AI Security Robustness**.

The `setup_vm.sh` script prepares one virtual machine for either **GPT-OSS 20B** or **Gemma 2 27B**, including Ollama, a Python environment, and a persistent ChromaDB store for RAG testing. Run the script separately on each model’s VM.

## What the Script Sets Up

| Component | Configuration |
| :--- | :--- |
| NVIDIA driver | Installs the recommended driver if a working driver is not already present |
| Ollama | Version `0.40.12`, bound to `127.0.0.1:11434` |
| Target model | `gpt-oss:20b` or `gemma2:27b` |
| Python environment | Python 3.12 virtual environment |
| Python packages | `chromadb==1.5.9` and `requests==2.34.2` |
| Vector database | Embedded, persistent ChromaDB store with no network listener |
| Embeddings | ChromaDB’s default ONNX `all-MiniLM-L6-v2` embedding function |
| Retrieval settings | Approximately 800-character chunks and top-k of 3 |
| Model context | `num_ctx=8192` |
| Environment record | JSON manifest containing versions, model digest, and configuration |

> **Scope:** This script sets up the environment. It does not install or run the capstone’s prompt-injection testing tool, configure AWS infrastructure, or transfer results off the VM.

## Required Environment

Prepare **two VMs**, one for each model, using the team’s planned configuration.

| Requirement | Planned Configuration |
| :--- | :--- |
| Cloud platform | AWS EC2 |
| Instance type | `g6.xlarge` |
| Operating system | Ubuntu Server 24.04 LTS, x86-64 |
| GPU | NVIDIA L4 |
| Root volume | 100 GB |
| Available disk space | At least 60 GB free on `/` before full setup |
| Administration | AWS Systems Manager Session Manager |
| Security group | No inbound rules required |
| Permissions | An account with `sudo` access |

The VM also needs outbound access for OS packages, Python packages, the Ollama installer, model weights, and the embedding-model download. Confirm that the AWS account has sufficient GPU-instance quota and that the VM is available in Session Manager before continuing.

## Quick Start

### Prepare the Session

Connect to the VM using **AWS Systems Manager → Session Manager**.

For consistent ownership and paths, run setup from the `ubuntu` account. If your SSM session starts as `ssm-user` or another account, switch first:

```bash
sudo -iu ubuntu
```

Place `setup_vm.sh` in a directory that the `ubuntu` account can read, then change to that directory:

```bash
cd /path/to/script
```

Replace `/path/to/script` with the actual directory containing the downloaded script.

> **Important:** The examples use `/home/ubuntu/team2-llm-security` as the application directory. Use the same path when loading the corpus and connecting the testing tool to ChromaDB.

### Set Up the GPT-OSS VM

Run this command on the VM assigned to GPT-OSS:

```bash
sudo bash setup_vm.sh \
  --model gpt-oss \
  --app-dir /home/ubuntu/team2-llm-security
```

### Set Up the Gemma 2 VM

Run this command on the separate VM assigned to Gemma 2:

```bash
sudo bash setup_vm.sh \
  --model gemma2 \
  --app-dir /home/ubuntu/team2-llm-security
```

Run only the command appropriate for each host. The same script handles both environments; the `--model` value selects which model is downloaded and tested.

### Optional: Include a Sample Corpus

To test retrieval before the team’s frozen synthetic corpus is available, add `--with-sample-corpus`:

```bash
sudo bash setup_vm.sh \
  --model gpt-oss \
  --app-dir /home/ubuntu/team2-llm-security \
  --with-sample-corpus
```

Use `--model gemma2` instead on the Gemma host.

The sample document is created only when the corpus directory is empty. Remove it and reset the collection before loading the final experimental corpus.

## What Happens During Setup

| Stage | Action |
| :--- | :--- |
| Preflight | Checks permissions, OS, free disk space, and GPU visibility |
| System dependencies | Installs the required OS packages |
| GPU driver | Checks the existing driver and installs one if necessary |
| Ollama | Installs the pinned version, configures loopback binding, and restarts the service |
| Runtime verification | Checks the running Ollama version and listening addresses |
| Model download | Pulls the selected model and records its full digest |
| Model smoke test | Sends a small chat request using an 8,192-token context setting |
| Python environment | Creates the virtual environment and installs the pinned packages |
| ChromaDB | Creates the persistent store, loads available corpus files, and tests retrieval |
| Manifest | Writes the environment configuration to a JSON file |

> **Reboot required?** If the NVIDIA driver is installed but not active, the script stops with a reboot instruction. Reboot the VM, reconnect through Session Manager, return to the script directory, and rerun the same setup command.

The model download is large, so allow the script to finish. A smoke-test failure should be investigated before beginning experiments.

## Verify the Installation

Run these commands on the VM after setup completes.

### Check the GPU

```bash
nvidia-smi
```

### Check Ollama

```bash
curl -fsS http://127.0.0.1:11434/api/version
```

### List Installed Models

```bash
ollama list
```

### Check Python Dependencies

```bash
/home/ubuntu/team2-llm-security/venv/bin/pip check
```

### View the Environment Manifest

```bash
python3 -m json.tool \
  /home/ubuntu/team2-llm-security/config/environment_manifest.json
```

A completed setup with an empty corpus does not demonstrate retrieval. Load documents and run the retrieval check before beginning RAG experiments.

## Load the Synthetic RAG Corpus

Place the team’s approved `.md` and `.txt` documents in:

```text
/home/ubuntu/team2-llm-security/data/rag_corpus/
```

For example, to copy Markdown files from a local directory on the VM:

```bash
cp /path/to/synthetic-corpus/*.md \
  /home/ubuntu/team2-llm-security/data/rag_corpus/
```

Then load the corpus and run the retrieval check:

```bash
/home/ubuntu/team2-llm-security/venv/bin/python \
  /home/ubuntu/team2-llm-security/rag_load.py
```

The loader uses the benign query:

```text
Summarize the remote access policy.
```

To test a different retrieval query:

```bash
/home/ubuntu/team2-llm-security/venv/bin/python \
  /home/ubuntu/team2-llm-security/rag_load.py \
  --query "How are contractor accounts reviewed?"
```

### Rebuild the Collection

Use this command after changing or removing corpus documents, or when a clean collection is required:

```bash
/home/ubuntu/team2-llm-security/venv/bin/python \
  /home/ubuntu/team2-llm-security/rag_load.py \
  --reset
```

> **Destructive to the collection:** `--reset` deletes the `rag_corpus` collection and recreates it from the current source files. It does not delete the source documents, Ollama installation, or model weights.

The loader detects changed or deleted source documents and refuses to continue without an explicit reset. This helps prevent stale chunks from contaminating later experiments.

### Rebuild the Python and ChromaDB Environment

To rerun the environment’s ChromaDB setup without reinstalling the driver, Ollama, or model:

```bash
bash setup_vm.sh \
  --chromadb-only \
  --app-dir /home/ubuntu/team2-llm-security
```

To rebuild that environment and reset the collection:

```bash
bash setup_vm.sh \
  --chromadb-only \
  --reset-rag \
  --app-dir /home/ubuntu/team2-llm-security
```

Run these commands from the directory containing `setup_vm.sh`, using the same application account as the original installation. This mode assumes Python 3.12 and its virtual-environment support are already installed.

## Connect the Testing Tool to ChromaDB

The testing tool must use the same persistent directory and collection as the loader:

```python
import chromadb

client = chromadb.PersistentClient(
    path="/home/ubuntu/team2-llm-security/data/chroma"
)

collection = client.get_collection(
    name="rag_corpus"
)

results = collection.query(
    query_texts=["Summarize the remote access policy."],
    n_results=3,
)
```

ChromaDB is embedded in the Python process. Do not configure the tool to use an HTTP ChromaDB endpoint unless the deployment is deliberately changed to server mode.

## Application Directory

```text
team2-llm-security/
├── config/
│   └── environment_manifest.json
├── data/
│   ├── chroma/
│   ├── rag_corpus/
│   └── web_root/
├── results/
├── venv/
├── manifest.py
├── rag_load.py
└── requirements.txt
```

| Path | Purpose |
| :--- | :--- |
| `config/environment_manifest.json` | Installed versions, model digest, and configuration |
| `data/chroma/` | Persistent database files; do not edit manually |
| `data/rag_corpus/` | Synthetic Markdown and text documents |
| `data/web_root/` | Reserved directory for loopback URL-poisoning fixtures |
| `results/` | Reserved directory for experiment outputs |
| `venv/` | Python virtual environment |
| `rag_load.py` | Corpus loading, reset, and retrieval checks |
| `manifest.py` | Environment-manifest writer |
| `requirements.txt` | Pinned direct Python dependencies |

Creating `data/web_root/` does not start a web server. Creating `results/` does not generate experiment results.

## Command-Line Options

| Option | Purpose |
| :--- | :--- |
| `--model gpt-oss` | Select GPT-OSS 20B for full setup |
| `--model gemma2` | Select Gemma 2 27B for full setup |
| `--app-dir PATH` | Choose the application directory |
| `--chromadb-only` | Set up the Python and ChromaDB environment without host/model setup |
| `--reset-rag` | Delete and recreate the collection during ChromaDB setup |
| `--with-sample-corpus` | Add a sample document if the corpus directory is empty |
| `--skip-driver` | Skip driver installation; does not force CPU-only inference |
| `--skip-model-pull` | Use an already-installed model; fails if the model is absent |
| `--skip-model-test` | Skip the inference smoke test |
| `--skip-chromadb` | Skip store initialization and corpus loading; Python packages are still installed |
| `--with-cuda-toolkit` | Request the optional CUDA toolkit installation in the driver-setup path |
| `--help` | Display the script’s built-in help |

## Troubleshooting

| Problem | What to Check |
| :--- | :--- |
| Driver installed but not active | Reboot, reconnect, and rerun the same setup command |
| Insufficient disk space | Ensure at least 60 GB is available on `/` before full setup |
| Ollama API does not start | Inspect `sudo journalctl -u ollama -n 100 --no-pager` |
| Running Ollama version differs from the pin | Inspect the installed binary and service executable, then restart the service and verify again |
| Model digest is missing | Rerun without `--skip-model-pull` |
| Model smoke test fails | Check Ollama logs, `nvidia-smi`, available RAM, and the API response |
| Corpus drift is reported | Review the changed files, then rebuild with `rag_load.py --reset` |
| Retrieval is skipped | Add nonempty `.md` or `.txt` files to the corpus directory |
| Permission denied | Confirm the application directory belongs to the intended application account |

To inspect Ollama service logs:

```bash
sudo journalctl -u ollama -n 100 --no-pager
```

To restart Ollama:

```bash
sudo systemctl restart ollama
```

## Reproducibility and Safety

- **Record the environment:** Preserve the manifest with each experiment’s evidence.
- **Compare model digests:** Model tags can change. The recorded digest identifies the downloaded artifact but does not enforce that artifact on future installations.
- **Use matched corpora:** Both hosts should use the same approved corpus, chunking settings, and embedding configuration.
- **Reset intentionally:** Rebuild or isolate collections between cases when the experiment requires clean RAG state.
- **Keep services private:** Do not add public inbound rules for Ollama or ChromaDB.
- **Protect evidence:** Review manifests and logs for private hostnames, paths, identifiers, or sensitive content before publication.
- **Review dependency pins:** Fixed direct dependencies are not a complete dependency lockfile. Preserve the resolved package inventory when freezing the experiment.

The script does not configure AWS quotas, IAM, Session Manager, security groups, budget alarms, or automatic shutdown. Those remain infrastructure responsibilities.

## Validation Status and Limitations

The earlier validation included shell syntax and lint checks, Python 3.12 dependency installation, real ChromaDB persistence and retrieval checks, and mocked host-orchestration tests. These checks do not replace acceptance testing on the actual VMs.

The following still require verification on each EC2 host:

- NVIDIA driver installation and activation.
- Installation and operation of the real Ollama service.
- Model download and inference on the L4 GPU.
- Resource usage at the configured context length.
- Integration with the actual capstone testing tool.

Treat the first deployment on each VM as an acceptance test and preserve its output and manifest.

## Dependency Security Review

The script’s original security note references reported ChromaDB advisories affecting the pinned `1.5.9` release. That note is historical, not a current vulnerability assessment or an assertion that embedded operation is unaffected.

Before deployment or publication, review the current [ChromaDB issue report](https://github.com/chroma-core/chroma/issues/7909), underlying advisories, and available patched releases. Document the team’s dependency decision and update the script’s pins when appropriate.

## Documentation

- [Ollama releases](https://github.com/ollama/ollama/releases)
- [Ollama installer](https://ollama.com/install.sh)
- [GPT-OSS 20B model](https://ollama.com/library/gpt-oss:20b)
- [Gemma 2 27B model](https://ollama.com/library/gemma2:27b)
- [ChromaDB package](https://pypi.org/project/chromadb/)
