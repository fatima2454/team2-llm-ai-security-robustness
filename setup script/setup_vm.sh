#!/usr/bin/env bash
# Team 2 VM setup: Ubuntu 24.04, systemd, Ollama and embedded ChromaDB.
# Usage: sudo bash setup_vm.sh --model gpt-oss|gemma2|both
# RAG only: sudo bash setup_vm.sh --chromadb-only
# Optional version pins: OLLAMA_VERSION, CHROMADB_VERSION, REQUESTS_VERSION.
# Without pins, initial installation uses available releases.
set -Eeuo pipefail
trap 'echo "ERROR at line $LINENO. Resolve the error and rerun." >&2' ERR
MODEL=""; APP_DIR=""; APP_USER="${SUDO_USER:-}"
RAG_ONLY=0; SKIP_DRIVER=0; RESET=0; SAMPLE=0; TEST_MODEL=0
usage() {
  cat <<'HELP'
Usage: sudo bash setup_vm.sh --model gpt-oss|gemma2|both [options]
  --chromadb-only        Configure Python and RAG only
  --app-user USER        Existing non-root application user
  --app-dir PATH         Absolute application directory
  --skip-driver         Skip NVIDIA driver installation
  --reset-rag           Delete and rebuild ONLY rag_corpus
  --with-sample-corpus  Seed synthetic sample if corpus is empty
  --test-model          Run a generation per selected model
  --help                Show help
Put UTF-8 .txt or .md files in APP_DIR/data/corpus, then rerun
with --chromadb-only. Ingestion synchronizes this collection to that directory.
HELP
}
while (($#)); do
  case "$1" in
    --model|--app-dir|--app-user)
      (($# >= 2)) || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in --model) MODEL="$2";; --app-dir) APP_DIR="$2";; --app-user) APP_USER="$2";; esac
      shift 2;;
    --chromadb-only) RAG_ONLY=1; shift;;
    --skip-driver) SKIP_DRIVER=1; shift;;
    --reset-rag) RESET=1; shift;;
    --with-sample-corpus) SAMPLE=1; shift;;
    --test-model) TEST_MODEL=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; exit 2;;
  esac
done
[[ $EUID == 0 ]] || { echo "Run using sudo bash." >&2; exit 1; }
[[ -n "$APP_USER" && "$APP_USER" != root ]] || { echo "Specify --app-user EXISTING_USER" >&2; exit 2; }
id "$APP_USER" >/dev/null
USER_HOME=$(getent passwd "$APP_USER" | cut -d: -f6)
APP_GROUP=$(id -gn "$APP_USER")
APP_DIR="${APP_DIR:-$USER_HOME/team2-llm-security}"
[[ "$APP_DIR" == /* && "$APP_DIR" != / && "$APP_DIR" != *$'\n'* ]] || { echo "Invalid app directory" >&2; exit 2; }
if (( ! RAG_ONLY )); then
  case "$MODEL" in gpt-oss|gemma2|both) ;; *) usage; exit 2;; esac
fi
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || { echo "Requires Ubuntu 24.04." >&2; exit 1; }
[[ -d /run/systemd/system ]] || { echo "A systemd VM is required." >&2; exit 1; }
as_user() { sudo -u "$APP_USER" env HOME="$USER_HOME" "$@"; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl python3 python3-venv python3-pip
for d in "$APP_DIR" "$APP_DIR/scripts" "$APP_DIR/config" "$APP_DIR/data" "$APP_DIR/data/corpus" "$APP_DIR/data/chroma"; do
  install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" "$d"
done
if (( ! RAG_ONLY )); then
  if (( ! SKIP_DRIVER )) && ! nvidia-smi >/dev/null 2>&1; then
    apt-get install -y ubuntu-drivers-common
    ubuntu-drivers install
    modprobe nvidia || true
    if ! nvidia-smi >/dev/null 2>&1; then
      echo "Driver not active. Reboot VM, then rerun; Secure Boot may require configuration." >&2
      exit 1
    fi
  fi
  if ! command -v ollama >/dev/null || [[ -n "${OLLAMA_VERSION:-}" ]]; then
    INSTALLER=$(mktemp)
    trap 'rm -f "${INSTALLER:-}"' EXIT
    curl --fail --silent --show-error --location https://ollama.com/install.sh -o "$INSTALLER"
    # Executes upstream installer as root; review before use.
    if [[ -n "${OLLAMA_VERSION:-}" ]]; then
      env OLLAMA_VERSION="$OLLAMA_VERSION" sh "$INSTALLER"
    else
      sh "$INSTALLER"
    fi
    rm -f "$INSTALLER"
    trap - EXIT
  fi
  mkdir -p /etc/systemd/system/ollama.service.d
  cat >/etc/systemd/system/ollama.service.d/team2.conf <<'SERVICE'
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
SERVICE
  systemctl daemon-reload
  systemctl enable ollama
  systemctl restart ollama
  READY=0
  for i in {1..60}; do
    if curl -fsS http://127.0.0.1:11434/api/version >/dev/null; then READY=1; break; fi
    sleep 2
  done
  (( READY )) || { echo "Ollama not ready; inspect journalctl -u ollama." >&2; exit 1; }
  TAGS=()
  [[ "$MODEL" != gemma2 ]] && TAGS+=(gpt-oss:20b)
  [[ "$MODEL" != gpt-oss ]] && TAGS+=(gemma2:27b)
  for tag in "${TAGS[@]}"; do
    env OLLAMA_HOST=127.0.0.1:11434 ollama pull "$tag"
  done
fi
VENV="$APP_DIR/venv"
[[ -x "$VENV/bin/python" ]] || as_user python3 -m venv "$VENV"
if [[ ! -f "$APP_DIR/config/requirements-installed.txt" || -n "${CHROMADB_VERSION:-}${REQUESTS_VERSION:-}" ]]; then
  CHROMA_SPEC=chromadb; REQUESTS_SPEC=requests
  [[ -z "${CHROMADB_VERSION:-}" ]] || CHROMA_SPEC="chromadb==$CHROMADB_VERSION"
  [[ -z "${REQUESTS_VERSION:-}" ]] || REQUESTS_SPEC="requests==$REQUESTS_VERSION"
  as_user "$VENV/bin/python" -m pip install "$CHROMA_SPEC" "$REQUESTS_SPEC"
fi
as_user "$VENV/bin/python" -m pip check
as_user "$VENV/bin/python" -m pip freeze | as_user tee "$APP_DIR/config/requirements-installed.txt" >/dev/null
cat <<'PY' | as_user tee "$APP_DIR/scripts/rag_setup.py" >/dev/null
import hashlib
import importlib.metadata as md
import json
import os
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path
import chromadb
import requests
from chromadb.utils.embedding_functions import DefaultEmbeddingFunction

root = Path(os.environ['APP_DIR'])
config = root / 'config'
manifest_path = config / 'environment_manifest.json'
client = chromadb.PersistentClient(path=str(root / 'data/chroma'))
name = 'rag_corpus'
if os.environ.get('RESET_RAG') == '1':
    if name in [getattr(c, 'name', c) for c in client.list_collections()]:
        client.delete_collection(name)
collection = client.get_or_create_collection(name=name, embedding_function=DefaultEmbeddingFunction())
corpus = root / 'data/corpus'
paths = sorted(p for p in corpus.rglob('*') if p.is_file() and p.suffix.lower() in {'.txt', '.md'})
if not paths and os.environ.get('SAMPLE') == '1':
    (corpus / 'SAMPLE_ONLY.txt').write_text('SYNTHETIC SAMPLE ONLY. Team 2 studies prompt injection in local LLM and RAG systems.\n', encoding='utf-8')
    paths = [corpus / 'SAMPLE_ONLY.txt']
records = []
file_hashes = {}
for path in paths:
    text = path.read_text(encoding='utf-8')
    relative = path.relative_to(corpus).as_posix()
    file_hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    for start in range(0, len(text), 700):
        chunk = text[start:start + 800].strip()
        if not chunk:
            continue
        key = hashlib.sha256(f'{relative}:{start}:{chunk}'.encode()).hexdigest()
        records.append((key, chunk, {'source': relative, 'offset': start}))
for start in range(0, len(records), 64):
    batch = records[start:start + 64]
    collection.upsert(ids=[r[0] for r in batch], documents=[r[1] for r in batch], metadatas=[r[2] for r in batch])
# Collection belongs exclusively to this loader. Synchronize only after upserts.
wanted = {r[0] for r in records}
stale = [key for key in collection.get(include=[])['ids'] if key not in wanted]
for start in range(0, len(stale), 500):
    collection.delete(ids=stale[start:start + 500])
if collection.count():
    result = collection.query(query_texts=['What does this corpus describe?'], n_results=min(3, collection.count()))
else:
    result = {'status': 'skipped', 'reason': 'empty corpus'}
    print('Add UTF-8 .txt/.md corpus files and rerun --chromadb-only.')
(config / 'retrieval_smoke_test.json').write_text(json.dumps(result, indent=2))
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
manifest.update({
    'updated_utc': datetime.now(timezone.utc).isoformat(),
    'platform': platform.platform(), 'python': platform.python_version(),
    'packages': {p: md.version(p) for p in ('chromadb', 'requests')},
    'rag': {'mode': 'embedded PersistentClient; no Chroma HTTP server',
            'collection': name, 'path': str(root / 'data/chroma'),
            'embedding': 'DefaultEmbeddingFunction/all-MiniLM-L6-v2',
            'chunk_chars': 800, 'overlap_chars': 100, 'top_k': 3,
            'chunks': collection.count(), 'corpus_sha256': file_hashes},
})
try:
    version = requests.get('http://127.0.0.1:11434/api/version', timeout=10)
    version.raise_for_status()
    tags = requests.get('http://127.0.0.1:11434/api/tags', timeout=30)
    tags.raise_for_status()
    manifest['ollama'] = {'version': version.json(), 'models': tags.json(), 'observed_utc': datetime.now(timezone.utc).isoformat()}
except requests.RequestException as exc:
    manifest['ollama_probe_error'] = str(exc)
try:
    manifest['gpu'] = subprocess.check_output(['nvidia-smi', '--query-gpu=name,memory.total,driver_version', '--format=csv,noheader'], text=True, stderr=subprocess.STDOUT).strip()
except (FileNotFoundError, subprocess.CalledProcessError):
    manifest['gpu'] = 'nvidia-smi unavailable'
manifest_path.write_text(json.dumps(manifest, indent=2))
print(f'Chroma ready: {collection.count()} chunks. Manifest: {manifest_path}')
PY
as_user env APP_DIR="$APP_DIR" RESET_RAG="$RESET" SAMPLE="$SAMPLE" "$VENV/bin/python" "$APP_DIR/scripts/rag_setup.py"
if (( ! RAG_ONLY && TEST_MODEL )); then
  for tag in "${TAGS[@]}"; do
    as_user env TAG="$tag" "$VENV/bin/python" - <<'PY'
import os
import requests
response = requests.post('http://127.0.0.1:11434/api/generate', json={
    'model': os.environ['TAG'], 'prompt': 'Reply with a short greeting.',
    'stream': False, 'keep_alive': 0,
    'options': {'num_ctx': 8192, 'num_predict': 64, 'temperature': 0}}, timeout=1800)
response.raise_for_status()
result = response.json()
if result.get('error'):
    raise RuntimeError(result['error'])
print(os.environ['TAG'], result.get('response', ''), result.get('thinking', ''))
PY
  done
fi
printf '\nSetup complete. App directory: %s\n' "$APP_DIR"
printf 'Activate Python: source "%s/venv/bin/activate"\n' "$APP_DIR"
printf 'No firewall changes. Ollama uses loopback; Chroma is embedded.\n'
