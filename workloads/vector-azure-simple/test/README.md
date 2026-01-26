# Vector Azure Simple - Testing Guide

Efficient methods to validate Vector configuration before deploying to Kubernetes.

## Quick Validation

### 1. Validate Rendered Config (Fast - No Docker)

```bash
# Render the Helm template to extract vector.yaml
cd workloads/vector-azure-simple
helm template test . | grep -A1000 "vector.yaml: |" | head -n -1 | tail -n +2 | sed 's/^    //' > test/rendered-vector.yaml

# Validate with Docker
docker run --rm \
  -v $(pwd)/test:/etc/vector:ro \
  timberio/vector:0.52.0-alpine \
  validate /etc/vector/rendered-vector.yaml
```

### 2. Local Test Config (Best for Development)

Use the simplified `vector-local.yaml` which replaces secrets/TLS with test-friendly alternatives:

```bash
# Validate local test config
docker run --rm \
  -v $(pwd)/test:/etc/vector:ro \
  timberio/vector:0.52.0-alpine \
  validate /etc/vector/vector-local.yaml
```

### 3. Interactive Testing

```bash
# Run Vector interactively to test message parsing
docker run -it --rm \
  -v $(pwd)/test:/etc/vector:ro \
  -p 8686:8686 \
  timberio/vector:0.52.0-alpine \
  --config /etc/vector/vector-local.yaml

# In another terminal, send test messages:
cat test/test-messages.txt
# Copy/paste messages into the Vector terminal
```

## One-Liner Validation Script

```bash
# Run the validate script
./test/validate.sh
```

## Test VRL Transforms Individually

Use Vector's VRL REPL to test transform logic:

```bash
# Start VRL REPL
docker run -it --rm timberio/vector:0.52.0-alpine vrl

# Test syslog parsing
> .message = "<14>1 2024-01-15T10:30:00Z firewall01 app 1234 - - Test message"
> parsed = parse_syslog!(.message)
> parsed

# Test severity mapping
> severity = 3
> if severity <= 2 { "Critical" } else if severity <= 4 { "Error" } else if severity == 5 { "Warning" } else { "Information" }
```

## Verify Specific Components

### Check API Health (After Vector is Running)

```bash
curl http://localhost:8686/health
```

### View Component Graph

```bash
curl -s http://localhost:8686/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ components { componentId componentType } }"}' | jq
```

## Test Scenarios

| Test | Command | Expected |
|------|---------|----------|
| Config syntax | `vector validate config.yaml` | Exit code 0 |
| Syslog parsing | Send test message via stdin | Parsed JSON output |
| Severity mapping | Test various priority values | Correct Azure severity |
| Health endpoint | `curl :8686/health` | `{"ok":true}` |

## Troubleshooting

### "missing field" errors
- Check that all required sinks have their configuration
- Ensure environment variables are set (or use test config)

### TLS errors
- Use `vector-local.yaml` which doesn't require TLS
- Or provide test certificates

### Azure auth errors
- Use `vector-local.yaml` which outputs to console instead
- Test real Azure sink only in cluster with proper secrets
