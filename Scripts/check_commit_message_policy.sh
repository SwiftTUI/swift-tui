#!/usr/bin/env sh

set -eu

if [ "$#" -ne 1 ]; then
  >&2 echo "usage: $0 <commit-message-file>"
  exit 2
fi

commit_message_file=$1

if [ ! -f "$commit_message_file" ]; then
  >&2 echo "Commit message file does not exist: $commit_message_file"
  exit 2
fi

violations=$(
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }

    function normalize_identity(s) {
      s = tolower(s)
      gsub(/[^a-z0-9]+/, " ", s)
      return trim(s)
    }

    function blocked_display_name(name, raw) {
      raw = normalize_identity(name)
      name = raw

      if (raw == "replit agent") return 1
      sub(/ (ai|assistant|bot|chatbot)$/, "", name)

      if (name ~ /^(openai )?(chatgpt|chat gpt)( [0-9]+[a-z]?)*$/) return 1
      if (name ~ /^(openai )?gpt( [0-9]+[a-z]?)*$/) return 1
      if (name ~ /^(openai )?codex( (cli|code))?$/) return 1
      if (name ~ /^(openai|anthropic)$/) return 1
      if (name ~ /^(anthropic )?claude( (sonnet|opus|haiku|code|[0-9]+[a-z]?))*$/) return 1
      if (name ~ /^(google )?(gemini|bard)( ([0-9]+[a-z]?|flash|pro|ultra))*$/) return 1
      if (name ~ /^(github )?copilot( (chat|code))?$/) return 1
      if (name ~ /^perplexity$/) return 1
      if (name ~ /^(meta )?llama( [0-9]+[a-z]?)?$/) return 1
      if (name ~ /^(mistral|mixtral)( [0-9]+[a-z]?)?$/) return 1
      if (name ~ /^deepseek( [a-z0-9]+)*$/) return 1
      if (name ~ /^qwen( [0-9]+[a-z]?)*$/) return 1
      if (name ~ /^(xai )?grok( [0-9]+[a-z]?)?$/) return 1
      if (name ~ /^(meta ai|ollama|cursor|windsurf|devin|amazon q|amazon q developer|q developer)$/) return 1
      if (name ~ /^(tabnine|cody|sourcegraph cody)$/) return 1

      return 0
    }

    function extract_email(entry, candidate) {
      candidate = entry
      if (match(candidate, /<[^>]+>/)) {
        candidate = substr(candidate, RSTART + 1, RLENGTH - 2)
      } else if (match(candidate, /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z0-9.-]+/)) {
        candidate = substr(candidate, RSTART, RLENGTH)
      } else {
        candidate = ""
      }
      return tolower(trim(candidate))
    }

    function blocked_email(email, local, compact) {
      if (email == "") return 0

      local = email
      sub(/@.*/, "", local)
      compact = local
      gsub(/[^a-z0-9]+/, "", compact)

      if (compact ~ /^(chatgpt|gpt([0-9]+[a-z]?)?|openai|codex)$/) return 1
      if (compact ~ /^(claude(sonnet|opus|haiku|code|[0-9]+[a-z]?)?|anthropic)$/) return 1
      if (compact ~ /^(gemini|bard|copilot|githubcopilot)$/) return 1
      if (compact ~ /^(perplexity|llama([0-9]+[a-z]?)?|mistral|mixtral)$/) return 1
      if (compact ~ /^(deepseek(r[0-9]+|v[0-9]+)?|qwen([0-9]+[a-z]?)?|grok|xai)$/) return 1
      if (compact ~ /^(ollama|cursor|windsurf|devin|replitagent)$/) return 1
      if (compact ~ /^(amazonq|qdeveloper|tabnine|cody|sourcegraphcody)$/) return 1

      return 0
    }

    /^[[:space:]]*#/ { next }

    {
      lower = tolower($0)
      if (lower !~ /^[[:space:]]*co-authored-by[[:space:]]*:/) next

      entry = lower
      sub(/^[[:space:]]*co-authored-by[[:space:]]*:[[:space:]]*/, "", entry)

      display_name = entry
      sub(/[[:space:]]*<.*/, "", display_name)

      email = extract_email(entry)

      if (blocked_display_name(display_name) || blocked_email(email)) {
        printf "%d: %s\n", NR, $0
      }
    }
  ' "$commit_message_file"
)

if [ -n "$violations" ]; then
  >&2 echo "AI model identities must not be added as Co-authored-by trailers."
  >&2 echo "Remove the AI Co-authored-by entry from the commit message."
  >&2 echo ""
  >&2 echo "Offending trailer lines:"
  >&2 printf '%s\n' "$violations"
  exit 1
fi
