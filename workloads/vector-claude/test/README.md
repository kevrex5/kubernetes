# Vector Local Testing

Test the Vector configuration locally without deploying to Kubernetes.

## Quick Start

### Option 1: Docker (Recommended)

```bash
# Run Vector with local test config
docker run -it --rm \
  -v $(pwd)/test:/etc/vector:ro \
  -p 8686:8686 \
  timberio/vector:0.35.0 \
  --config /etc/vector/vector-local.yaml

# In another terminal, send test messages
cat test/test-messages.txt | docker exec -i <container_id> vector tap
```

### Option 2: Docker with stdin

```bash
# Interactive mode - paste messages directly
docker run -it --rm \
  -v $(pwd)/test:/etc/vector:ro \
  timberio/vector:0.35.0 \
  --config /etc/vector/vector-local.yaml

# Then paste test messages from test-messages.txt
```

### Option 3: Local Vector Binary

```bash
# Install Vector (macOS)
brew install vector

# Install Vector (Linux)
curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | bash

# Run with test config
vector --config test/vector-local.yaml

# Paste test messages or pipe them in
cat test/test-messages.txt | vector --config test/vector-local.yaml
```

## Validate Config Syntax

```bash
# Check config is valid YAML and Vector can parse it
docker run --rm \
  -v $(pwd)/test:/etc/vector:ro \
  timberio/vector:0.35.0 \
  validate /etc/vector/vector-local.yaml

# Or with local binary
vector validate test/vector-local.yaml
```

## Test VRL Expressions

Use Vector's VRL REPL to test individual transforms:

```bash
# Start VRL REPL
docker run -it --rm timberio/vector:0.35.0 vrl

# Or with local binary
vector vrl

# Then test expressions:
# > .message = "<14>1 2024-01-15T10:30:00Z firewall01 CEF 1234 - - CEF:0|Cisco|ASA|9.12|302013|Built connection|5|src=192.168.1.100"
# > parsed = parse_syslog!(.message)
# > parsed
```

## Test Specific VRL Functions

```bash
# Test CEF parsing
echo 'parse_cef!("CEF:0|Cisco|ASA|9.12|302013|Built TCP connection|5|src=192.168.1.100 dst=10.0.0.50")' | vector vrl

# Test syslog parsing
echo 'parse_syslog!("<14>1 2024-01-15T10:30:00Z myhost myapp 1234 - - Test message")' | vector vrl
```

## Expected Output

### CEF Message (Azure Format)
```json
{
  "DeviceVendor": "Cisco",
  "DeviceProduct": "ASA",
  "DeviceVersion": "9.12",
  "DeviceEventClassID": "302013",
  "Activity": "Built inbound TCP connection",
  "LogSeverity": "5",
  "SourceIP": "192.168.1.100",
  "DestinationIP": "10.0.0.50",
  "SourcePort": 54321,
  "DestinationPort": 443,
  "Protocol": "TCP",
  "DeviceAction": "allow",
  "CommunicationDirection": "0",
  "ReceivedBytes": 1500,
  "SentBytes": 500,
  "TimeGenerated": "2024-01-15T10:30:00.000Z",
  "AdditionalExtensions": ""
}
```

### CEF with Custom Fields
```json
{
  "DeviceVendor": "PaloAlto",
  "DeviceProduct": "Firewall",
  ...
  "AdditionalExtensions": "customField1=value1;customField2=value2;myExtension=testValue"
}
```

## Debugging

### Check Vector Health
```bash
curl http://localhost:8686/health
```

### View GraphQL Playground
Open http://localhost:8686/playground in browser (when api.playground=true)

### Get Component Status
```bash
curl -s http://localhost:8686/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ components { componentId componentType } }"}' | jq
```

## Test Full Config (with TLS disabled)

To test the full production config locally, extract it and modify:

```bash
# Extract config from Helm
helm template test . | grep -A1000 "vector.yaml: |" | tail -n +2 | sed 's/^    //' > /tmp/vector-full.yaml

# Edit to disable TLS and use console sinks
# Then run:
vector --config /tmp/vector-full.yaml
```
