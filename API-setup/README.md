# API setup

Session setup for the Perplexity Agent API. This does not replace `setup script/setup_vm.sh`. It does not install the GPU, Ollama, or ChromaDB, and it does not call the API during host setup.

The generator uses `POST https://api.perplexity.ai/v1/agent` with no tools and no effort level. Effort levels turn web search on by default ([Effort](https://docs.perplexity.ai/docs/agent-api/effort.md)).

## One-time console setup

1. Open [API Keys](https://console.perplexity.ai/project/keys) and create a key. The full value is shown once ([API key management](https://docs.perplexity.ai/docs/admin/api-key-management.md)).
2. Store it in SSM Parameter Store as a SecureString named `/team2/perplexity/api-key`. Do not commit it, write it to a file, or paste it into chat.
3. Add credits on the [Billing page](https://console.perplexity.ai/project/billing). An empty balance returns `402` ([FAQ](https://docs.perplexity.ai/docs/resources/faq.md)).

## On the VM

From the repository root, after an SSM session starts:

```bash
source API-setup/setup_api.sh
bash API-setup/setup_api.sh --check
```

`source` keeps the key in that shell. `--check` prints `key present` and an HTTP status only. `200` means the key worked. The request body is `model` plus `input`; it does not enable web search ([Agent API quickstart](https://docs.perplexity.ai/docs/agent-api/quickstart.md)).

If the parameter name differs:

```bash
export PPLX_SSM_PARAMETER="/your/parameter/name"
export AWS_REGION="us-east-1"
source API-setup/setup_api.sh
```

## Troubleshooting

| What you see | What to do |
| --- | --- |
| `key present` disappears in the next command | The script was executed, not sourced. Run `source API-setup/setup_api.sh`. |
| `ParameterNotFound` | The SSM name or `AWS_REGION` does not match the parameter. |
| `AccessDeniedException` | The instance role needs `ssm:GetParameter` on that parameter, and `kms:Decrypt` if a customer-managed key encrypts it. |
| `HTTP 401` | The key is missing, revoked, or not in the `Authorization: Bearer` header. Create a new key. Do not paste the old one into chat ([FAQ](https://docs.perplexity.ai/docs/resources/faq.md)). |
| `HTTP 402` | API credits are exhausted. Add credits in the [billing console](https://console.perplexity.ai/project/billing). API credits are separate from Computer credits ([API platform](https://www.perplexity.ai/help-center/en/articles/10354842-what-is-the-perplexity-api-platform)). |
| `HTTP 429` | Wait for the `Retry-After` value the script prints, then run `--check` again ([rate limits](https://docs.perplexity.ai/docs/admin/rate-limits-usage-tiers.md)). |
| `HTTP 400` | The smoke-test model id is stale. Set `PPLX_SMOKE_MODEL` to an id from the [models page](https://docs.perplexity.ai/docs/agent-api/models.md). The default is `openai/gpt-5.6-sol`. |
| Check hangs, then fails | Outbound HTTPS to `api.perplexity.ai` is blocked, or the call exceeded 180 seconds. Confirm egress on port 443. |
| Key appears in the terminal | Stop. You used `bash -x`, `echo`, or `env`. Rotate the key in the [API Console](https://console.perplexity.ai/project/keys), update SSM, and do not commit the scrollback. |

Do not enable `web_search` for generation. Tool calls are billed separately from tokens ([pricing](https://docs.perplexity.ai/docs/getting-started/pricing.md)).
