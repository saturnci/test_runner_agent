# SaturnCI API-Triggered Test Runs Specification

## Overview

This specification describes the new API-triggered test run model for SaturnCI, implementing the Dependency Inversion Principle at the architectural level.

### Current Model (Push)
- SaturnCI orchestrates everything
- User's project is passive (just config files)
- Test runner agent controls execution flow

### New Model (Pull)
- User's project triggers test runs via API
- User controls when and how tests run
- SaturnCI provides services (API, runners, results storage)

## Architecture Goals

1. **Minimal Risk**: Start with smallest possible change to existing infrastructure
2. **Backward Compatibility**: Existing workflows continue working unchanged
3. **Progressive Enhancement**: Gradually shift control from SaturnCI to user
4. **User Control**: Users decide when to trigger tests and eventually how to run them

---

## Phase 1: API-Triggered Runs (Steel Thread)

### What Changes
- ✅ Add new API endpoint: `POST /api/v1/test_runs`
- ✅ Add new API endpoint: `GET /api/v1/test_runs/:id`
- ✅ Users can trigger runs via curl/API

### What Stays the Same
- ✅ Test runner agent (`lib/test_runner_agent.rb`) - no changes
- ✅ Script execution (`lib/script.rb`) - no changes
- ✅ Existing runner infrastructure - works as before
- ✅ Current workflows - continue functioning

### How It Works

```
User's Script (GitHub Actions, local, etc.)
    ↓
    POST /api/v1/test_runs (creates run)
    ↓
SaturnCI API (creates test_suite_run, assigns to runners)
    ↓
Test Runner Agent (polls, gets assignment via existing flow)
    ↓
execute_script (runs tests exactly as before)
    ↓
User's Script (polls GET /api/v1/test_runs/:id until complete)
```

---

## Authentication

### Phase 1: Basic Auth (Reuse Existing Tokens)

Users authenticate using existing SATURNCI_USER_ID and SATURNCI_USER_API_TOKEN.

**Example:**
```bash
curl -X POST "https://app.saturnci.com/api/v1/test_runs" \
  -u "${SATURNCI_USER_ID}:${SATURNCI_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"repo":"myorg/myrepo","commit":"abc123"}'
```

**Credentials:**
- Users get `SATURNCI_USER_ID` and `SATURNCI_USER_API_TOKEN` from SaturnCI settings
- Same credentials used by test runner agents
- Stored as secrets in GitHub Actions / CI system

### Future: Project-Scoped Tokens

Later phases may introduce:
- Project-specific API tokens
- Token scopes (read-only, trigger-only, admin)
- Automatic token rotation

---

## API Endpoints

### POST /api/v1/test_runs

Create a new test run.

**Authentication:** Basic Auth (`SATURNCI_USER_ID:SATURNCI_USER_API_TOKEN`)

**Request:**
```json
{
  "repo": "owner/repo",           // Required: GitHub repo
  "commit": "abc123def",           // Required: Git commit SHA
  "branch": "main",                // Optional: Branch name
  "number_of_concurrent_runs": 4,  // Optional: Default from project settings
  "rspec_seed": 12345              // Optional: Default random
}
```

**Response (201 Created):**
```json
{
  "run_id": "12345",
  "test_suite_run_id": "67890",
  "status": "pending",
  "created_at": "2025-01-15T10:30:00Z",
  "repo": "owner/repo",
  "commit": "abc123def",
  "branch": "main"
}
```

**Response (400 Bad Request):**
```json
{
  "error": "Invalid repository format",
  "details": "Repository must be in format 'owner/repo'"
}
```

**Response (401 Unauthorized):**
```json
{
  "error": "Authentication failed"
}
```

---

### GET /api/v1/test_runs/:id

Get status and results of a test run.

**Authentication:** Basic Auth (`SATURNCI_USER_ID:SATURNCI_USER_API_TOKEN`)

**Response (200 OK) - Pending:**
```json
{
  "run_id": "12345",
  "status": "pending",
  "created_at": "2025-01-15T10:30:00Z",
  "started_at": null,
  "completed_at": null
}
```

**Response (200 OK) - Running:**
```json
{
  "run_id": "12345",
  "status": "running",
  "created_at": "2025-01-15T10:30:00Z",
  "started_at": "2025-01-15T10:30:15Z",
  "completed_at": null,
  "progress": {
    "tests_started": true,
    "tests_completed": false
  }
}
```

**Response (200 OK) - Completed:**
```json
{
  "run_id": "12345",
  "status": "completed",
  "created_at": "2025-01-15T10:30:00Z",
  "started_at": "2025-01-15T10:30:15Z",
  "completed_at": "2025-01-15T10:35:42Z",
  "result": "passed",  // "passed" | "failed"
  "summary": {
    "total_examples": 150,
    "failed_examples": 0,
    "pending_examples": 2
  },
  "results_url": "https://app.saturnci.com/runs/12345/results"
}
```

**Response (404 Not Found):**
```json
{
  "error": "Run not found"
}
```

---

## User Scripts

### Minimal Bash Script

```bash
#!/bin/bash
# .saturnci/trigger.sh
#
# Usage: Run this script from GitHub Actions or locally
# Requires: SATURNCI_USER_ID and SATURNCI_API_TOKEN environment variables

set -e

API_HOST="${SATURNCI_API_HOST:-https://app.saturnci.com}"
REPO="${GITHUB_REPOSITORY:-myorg/myrepo}"
COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD)}"
BRANCH="${GITHUB_REF_NAME:-$(git branch --show-current)}"

echo "Triggering SaturnCI test run..."
echo "  Repo: $REPO"
echo "  Commit: $COMMIT"
echo "  Branch: $BRANCH"

# Create test run
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "${API_HOST}/api/v1/test_runs" \
  -u "${SATURNCI_USER_ID}:${SATURNCI_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"repo\": \"${REPO}\",
    \"commit\": \"${COMMIT}\",
    \"branch\": \"${BRANCH}\"
  }")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "201" ]; then
  echo "Error creating test run (HTTP $HTTP_CODE):"
  echo "$BODY"
  exit 1
fi

RUN_ID=$(echo "$BODY" | jq -r '.run_id')
echo "Test run created: $RUN_ID"
echo "View at: ${API_HOST}/runs/${RUN_ID}"

# Poll for completion
echo "Waiting for test run to complete..."
while true; do
  RESPONSE=$(curl -s \
    "${API_HOST}/api/v1/test_runs/${RUN_ID}" \
    -u "${SATURNCI_USER_ID}:${SATURNCI_API_TOKEN}")

  STATUS=$(echo "$RESPONSE" | jq -r '.status')

  case "$STATUS" in
    "pending"|"running")
      echo "  Status: $STATUS"
      sleep 5
      ;;
    "completed")
      RESULT=$(echo "$RESPONSE" | jq -r '.result')
      echo "Test run completed: $RESULT"

      if [ "$RESULT" = "passed" ]; then
        echo "✓ All tests passed"
        exit 0
      else
        echo "✗ Tests failed"
        echo "$RESPONSE" | jq '.summary'
        exit 1
      fi
      ;;
    "failed")
      echo "Test run failed"
      exit 1
      ;;
    *)
      echo "Unknown status: $STATUS"
      exit 1
      ;;
  esac
done
```

### GitHub Actions Workflow

```yaml
name: Tests
on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Trigger SaturnCI
        run: bash .saturnci/trigger.sh
        env:
          SATURNCI_USER_ID: ${{ secrets.SATURNCI_USER_ID }}
          SATURNCI_API_TOKEN: ${{ secrets.SATURNCI_API_TOKEN }}
          SATURNCI_API_HOST: ${{ secrets.SATURNCI_API_HOST || 'https://app.saturnci.com' }}
```

---

## Error Handling

### Network Failures

User scripts should handle:
- Connection timeouts
- Temporary API unavailability
- Rate limiting

**Example:**
```bash
# Retry logic
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  RESPONSE=$(curl -s -w "\n%{http_code}" ... || echo "000")
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

  if [ "$HTTP_CODE" = "201" ]; then
    break
  elif [ "$HTTP_CODE" = "503" ] || [ "$HTTP_CODE" = "000" ]; then
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Retry $RETRY_COUNT/$MAX_RETRIES..."
    sleep $((RETRY_COUNT * 2))
  else
    echo "Fatal error: HTTP $HTTP_CODE"
    exit 1
  fi
done
```

### Timeout Handling

```bash
# Timeout after 30 minutes
TIMEOUT=1800
START_TIME=$(date +%s)

while true; do
  ELAPSED=$(($(date +%s) - START_TIME))
  if [ $ELAPSED -gt $TIMEOUT ]; then
    echo "Test run timed out after ${TIMEOUT}s"
    exit 1
  fi

  # Poll for status...
  sleep 5
done
```

---

## Migration Path

### Phase 1: API-Triggered Runs (Current Spec)
- Users can trigger runs via API
- All execution still controlled by SaturnCI
- Zero changes to test runner agent

### Phase 2: User-Controlled Setup (Future)
- User's repo contains `.saturnci/run.sh`
- Script controls setup steps (bundle install, db setup, etc.)
- SaturnCI executes user's script
- Gradually shift responsibility to user

### Phase 3: Full User Control (Future)
- User script controls everything including test execution
- User decides how to chunk tests, what to run
- SaturnCI provides SDK/helpers (bash functions, Ruby gem)
- Maximum flexibility for users

### Phase 4: Ruby SDK (Future)
```ruby
# .saturnci/run.rb
require 'saturnci'

SaturnCI.run do |config|
  config.setup do
    system("bundle install")
    system("rails db:test:prepare")
  end

  config.test do |chunk|
    system("bundle exec rspec #{chunk.files.join(' ')}")
  end
end
```

---

## Implementation Checklist

### Backend API (Not in this repo)
- [ ] Add `POST /api/v1/test_runs` endpoint
- [ ] Add `GET /api/v1/test_runs/:id` endpoint
- [ ] Implement authentication validation
- [ ] Create test_suite_run and assignments (reuse existing code)
- [ ] Add API documentation to docs site

### Test Runner Agent (This repo)
- [ ] No changes needed for Phase 1!
- [ ] Add integration tests for API-triggered flow

### Documentation
- [x] Create SPEC.md (this file)
- [ ] Create example user scripts directory
- [ ] Update README with new capabilities
- [ ] Create migration guide for existing users

### Testing
- [ ] Test API endpoint with curl
- [ ] Test GitHub Actions workflow
- [ ] Test error scenarios (invalid repo, auth failures)
- [ ] Test concurrent runs
- [ ] Verify backward compatibility

---

## Open Questions

1. **Rate Limiting**: Should we limit how many runs a user can trigger per hour?
2. **Webhook Support**: Should we add webhooks instead of polling?
3. **Cancel API**: Should we add `DELETE /api/v1/test_runs/:id` to cancel runs?
4. **Logs Streaming**: Should the API support streaming logs while running?
5. **Project Validation**: Should we validate that the user has access to the repo?

---

## Success Criteria

Phase 1 is successful when:
- ✅ Users can trigger runs via curl from any environment
- ✅ GitHub Actions workflow using API works reliably
- ✅ Existing non-API workflows continue working
- ✅ No changes needed to test runner agent
- ✅ Documentation is clear and complete
- ✅ At least one production user migrates successfully

---

## Security Considerations

1. **Token Storage**: Users must store credentials as secrets (GitHub Secrets, env vars)
2. **HTTPS Only**: All API calls must use HTTPS
3. **Token Rotation**: Consider implementing token rotation in Phase 2
4. **Repository Validation**: Verify user has access to the repository they're triggering
5. **Rate Limiting**: Prevent abuse via rate limits on test run creation

---

## Performance Considerations

1. **Polling Interval**: Recommend 5-second polling to balance responsiveness vs load
2. **API Response Time**: `POST /test_runs` should return quickly (< 500ms)
3. **Runner Assignment**: Use existing assignment logic, no performance impact
4. **Concurrent Runs**: No limit change from current system

---

*Last Updated: 2025-01-22*
*Version: 1.0 (Phase 1 - Steel Thread)*
