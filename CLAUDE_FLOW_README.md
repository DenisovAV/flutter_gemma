# Claude Flow - Automated Refactoring Guide

## Overview

This project uses [claude-flow](https://www.npmjs.com/package/claude-flow) to automate the TDD-based refactoring from URL schemes to type-safe enum architecture.

## Prerequisites

```bash
# Install Node.js (if not installed)
# https://nodejs.org/

# Install claude-flow globally
npm install -g claude-flow

# Or use npx (no installation needed)
npx claude-flow --version
```

## Setup

### 1. Set Anthropic API Key

```bash
# Option 1: Environment variable
export ANTHROPIC_API_KEY="sk-ant-api03-..."

# Option 2: .env file (create in project root)
echo "ANTHROPIC_API_KEY=sk-ant-api03-..." > .env

# Verify it's set
echo $ANTHROPIC_API_KEY
```

### 2. Verify Configuration

```bash
# Check if config is valid
claude-flow validate

# Dry-run (shows what will happen without executing)
claude-flow run --dry-run
```

## Running the Refactoring

### Full Automated Run

```bash
# Run all phases automatically
claude-flow run

# This will execute:
# - Phase 1: ModelSource enum (tests + implementation)
# - Phase 2: Source handlers with DI
# - Phase 3: Services & Service Registry
# - Phase 4: Modern API + Legacy adapter
# - Phase 5: Final validation + docs
```

### Interactive Mode (Recommended for First Time)

```bash
# Confirm each step before executing
claude-flow run --interactive

# You'll see:
# → About to execute: phase1-create-model-source-tests
#   Continue? [y/N]
```

### Resume After Interruption

```bash
# If stopped or failed, resume from last checkpoint
claude-flow resume

# Or resume from specific step
claude-flow run --from phase2-implement-network-handler
```

### Run Specific Phase

```bash
# Run only Phase 1 (ModelSource enum)
claude-flow run --from phase1-create-model-source-tests --to phase1-refactor-model-source

# Run only Phase 2 (Handlers)
claude-flow run --from phase2-create-handler-interfaces --to phase2-implement-handler-registry

# Run only Phase 3 (Services & DI)
claude-flow run --from phase3-implement-file-system-service --to phase3-create-integration-tests

# Run only Phase 4 (Modern API)
claude-flow run --from phase4-implement-value-objects --to phase4-create-legacy-compatibility-tests

# Run only Phase 5 (Validation)
claude-flow run --from phase5-run-all-tests --to phase5-final-verification
```

## Monitoring Progress

### Check Status

```bash
# Current execution status
claude-flow status

# Output:
# Status: Running
# Current phase: phase2-implement-network-handler
# Progress: 8/30 steps (27%)
# Elapsed: 15m 32s
# Estimated remaining: 42m
```

### View Logs

```bash
# Tail logs in real-time
tail -f .claude-flow.log

# View logs for specific step
claude-flow logs phase2-implement-network-handler

# Full log history
cat .claude-flow.log
```

### View History

```bash
# Show all past runs
claude-flow history

# Show specific run details
claude-flow history <run-id>
```

## Handling Failures

### If a Step Fails

```bash
# View the error
claude-flow logs <failed-step>

# Fix manually if needed, then resume
# Edit the files, run tests, fix issues...

# Mark step as complete manually and continue
claude-flow skip <failed-step>
claude-flow resume

# Or retry the failed step
claude-flow retry <failed-step>
```

### Rollback Changes

```bash
# Restore from backup (if enabled)
claude-flow rollback

# Restore to specific checkpoint
claude-flow rollback --to phase1-refactor-model-source
```

## Manual Verification Points

Even with automation, verify these manually:

### After Phase 1 (ModelSource)
```bash
flutter test test/core/model_source_test.dart
# All tests should pass ✅
```

### After Phase 2 (Handlers)
```bash
flutter test test/core/handlers/source_handler_test.dart
# All handler tests should pass ✅
```

### After Phase 3 (DI)
```bash
flutter test test/integration/
# Integration tests should pass ✅
```

### After Phase 4 (Modern API)
```bash
flutter test test/migration/legacy_compatibility_test.dart
# Legacy API should still work ✅
```

### After Phase 5 (Final)
```bash
flutter test                    # All tests pass
flutter analyze                 # Zero issues
cd example && flutter run       # Example app works
```

## Troubleshooting

### Issue: API Rate Limits

```bash
# If you hit rate limits, add delays
# Edit .claude-flow.yaml:
settings:
  retry_delay: 30  # Increase delay between retries
```

### Issue: Tests Fail After Implementation

```bash
# Run the specific test to see error
flutter test test/core/model_source_test.dart -r expanded

# Fix the implementation
# Re-run: claude-flow retry <step-name>
```

### Issue: Analysis Errors

```bash
# See specific errors
flutter analyze --verbose

# Fix imports, formatting, etc.
dart format .

# Continue
claude-flow resume
```

### Issue: Network Errors

```bash
# Check internet connection
ping anthropic.com

# Check API key
echo $ANTHROPIC_API_KEY

# Retry with exponential backoff
claude-flow run --max-retries 5
```

## Configuration Customization

### Change Model

Edit `.claude-flow.yaml`:
```yaml
model: claude-sonnet-4-5  # or claude-opus-4-5 for more complex tasks
```

### Adjust Parallelism

```yaml
settings:
  parallel: true  # Run independent steps in parallel (faster but riskier)
```

### Change Checkpoint Frequency

```yaml
settings:
  checkpoint_interval: 1  # Save after every step (safer)
```

### Disable Notifications

```yaml
notifications:
  on_step_complete: []  # Disable step completion notifications
```

## Best Practices

### 1. Start with Dry-Run
```bash
claude-flow run --dry-run
# Review what will happen before executing
```

### 2. Use Interactive Mode First Time
```bash
claude-flow run --interactive
# Understand each step before automatic execution
```

### 3. Monitor Tests Continuously
```bash
# In separate terminal
watch -n 5 "flutter test --reporter compact"
```

### 4. Commit Checkpoints
```bash
# After each successful phase
git add .
git commit -m "Phase X complete - <description>"
```

### 5. Keep Backups
```bash
# Backup before starting
git stash
git checkout -b refactoring-backup

# Return to main
git checkout main
```

## Expected Timeline

With `claude-flow` automation:

- **Phase 1** (ModelSource): ~15-30 minutes
- **Phase 2** (Handlers): ~30-60 minutes
- **Phase 3** (DI): ~30-45 minutes
- **Phase 4** (Modern API): ~45-60 minutes
- **Phase 5** (Validation): ~15-30 minutes

**Total**: ~2.5-4 hours (vs 5 weeks manual!)

## Verification Checklist

After completion, verify:

- [ ] All tests pass: `flutter test`
- [ ] Zero analysis issues: `flutter analyze`
- [ ] Example app builds: `cd example && flutter build apk --debug`
- [ ] Example app runs: `cd example && flutter run`
- [ ] Documentation updated: check `docs/` and `CLAUDE.md`
- [ ] Legacy API works: test old API methods
- [ ] New API works: test Modern API examples
- [ ] No regressions: compare with old behavior

## Getting Help

### Claude Flow Issues
- GitHub: https://github.com/anthropics/claude-flow (if exists)
- NPM: https://www.npmjs.com/package/claude-flow

### Project Issues
- Check: `docs/IMPLEMENTATION_ORCHESTRATOR.md`
- Check: `docs/SOLID_ANALYSIS.md`
- Check: `docs/MODERN_API_DESIGN.md`

## Advanced Usage

### Custom Validation

Add custom validation to steps in `.claude-flow.yaml`:

```yaml
- name: my-custom-step
  # ...
  validation:
    - command: flutter test test/my_test.dart
      expect: success
    - command: dart run custom_validator.dart
      expect: success
```

### Conditional Steps

```yaml
- name: conditional-step
  condition: "{{ env.RUN_OPTIONAL == 'true' }}"
  # Only runs if RUN_OPTIONAL env var is set
```

### Environment Variables

```yaml
- name: step-with-env
  env:
    CUSTOM_VAR: "value"
  # Available in validation commands
```

## FAQ

**Q: Can I pause and resume later?**
A: Yes! Use `Ctrl+C` to stop, then `claude-flow resume` to continue.

**Q: How much does this cost?**
A: Depends on Anthropic API pricing. Estimate: ~$5-15 for full run with Claude Sonnet.

**Q: What if I don't trust automation?**
A: Use `--dry-run` and `--interactive` modes. Review each step before execution.

**Q: Can I run only tests without implementation?**
A: Yes, specify step ranges: `--from phase1-create-model-source-tests --to phase1-create-model-source-tests`

**Q: Will this break my existing code?**
A: No! All changes maintain 100% backward compatibility via Legacy adapter.

---

**Ready to start?**

```bash
# Quick start
export ANTHROPIC_API_KEY="sk-ant-..."
claude-flow run --interactive
```

Good luck! 🚀
