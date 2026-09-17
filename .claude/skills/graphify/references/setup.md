[← Back to SKILL.md](../SKILL.md)

# Setup & Interpreter Management

## Step 1 - Ensure graphify is installed

Detect whether graphify is already installed and available in the current environment:

```bash
# Detect Python with graphify — uv/pipx-aware (fixes #831)
PYTHON=""
for candidate in \
    "$(which graphify 2>/dev/null | xargs -I{} head -n1 {} 2>/dev/null | sed "s/^#\!//")" \
    "$(which python3 2>/dev/null)" \
    "$(which python 2>/dev/null)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -c "import graphify" 2>/dev/null; then
        PYTHON="$candidate"
        break
    fi
done
```

If not found, install via pipx or pip:
```bash
pipx install graphify-ai || pip install graphify-ai
```

## Interpreter Pinning

Save the detected Python interpreter path so all subsequent subcommands and hooks read the exact binary:
```bash
mkdir -p graphify-out
echo "$PYTHON" > graphify-out/.graphify_python
```

Save scan root so `graphify update` knows where to look:
```bash
pwd > graphify-out/.graphify_root
```

## Interpreter Guard for Subcommands

Always execute subcommands through the pinned interpreter recorded in `graphify-out/.graphify_python`:
```bash
PYTHON="$(cat graphify-out/.graphify_python 2>/dev/null || which python3)"
"$PYTHON" -m graphify query "<question>"
```

## Troubleshooting

### PowerShell 5.1: Vertical Scrolling Stops Working

> [!NOTE]
> On Windows PowerShell 5.1, executing external CLI output may reset the buffer height. Run this snippet to restore scrolling:
> ```powershell
> $host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size($host.UI.RawUI.BufferSize.Width, 9999)
> ```
