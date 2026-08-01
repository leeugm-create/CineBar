# CineBar Pre-merge Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Address the approved Build 18 pre-merge review findings without changing deployment state.

**Architecture:** Keep all changes local and narrowly scoped: centralize website response headers at the worker boundary, keep Share and appcast metadata consistent, and make publisher release notes an explicit reviewed input. Preserve the existing signed appcast pipeline and atomic temp-file replacement.

**Tech Stack:** Cloudflare Workers, Next.js/TypeScript, Node test runner, Bash, Sparkle, Swift.

## Global Constraints

- Do not deploy, release, merge, or modify GitHub state.
- Preserve the untracked `dist/CineBar-0.8.3-test-build-18-universal.zip` artifact.
- Keep Build 16 migration guidance pointing to GitHub Releases.
- Tests precede each production behavior change; record the expected RED failure.
- Retain atomic appcast replacement and XML escaping.

---

### Task 1: Website security headers and public content

**Files:**
- Modify: `CineBarWebsite/tests/worker-security.test.mjs`, `CineBarWebsite/tests/content.test.mjs`
- Modify: `CineBarWebsite/worker/index.ts`, `CineBarWebsite/app/page.tsx`

- [ ] Add tests that assert the audited header set on HTML, health, and static/appcast responses, then observe RED.
- [ ] Add content tests for test.2 current-version guidance and anonymous per-device community ratings, then observe RED.
- [ ] Apply the shared header policy and visible copy, then run both suites GREEN.

### Task 2: Share update manifest

**Files:**
- Modify: `CineBarShare/tests/share-worker.test.mjs`
- Modify: `CineBarShare/worker.js`

- [ ] Update manifest assertions to Build 18 test.2/appcast metadata and observe RED.
- [ ] Change only the manifest payload needed for consistency, retaining Build 16 manual-migration guidance.
- [ ] Run Share tests GREEN.

### Task 3: Sparkle publisher notes input

**Files:**
- Modify: `CineBar/Tools/tests/publish_sparkle_update.test.mjs`
- Modify: `CineBar/Tools/publish_sparkle_update.sh`

- [ ] Add tests requiring reviewed structured/file release notes, escaping, and unchanged appcast on rejected input; observe RED.
- [ ] Add minimal argument/input parsing and XML list construction while preserving atomic publishing.
- [ ] Run publisher tests GREEN.

### Task 4: Repository hygiene and final gates

**Files:**
- Modify: `.gitignore`, tracked `dist/*.zip` entries, trailing-whitespace spec markdown files
- Create: `.superpowers/sdd/2026-07-30-cinebar-sparkle-updates/premerge-fixes-report.md`

- [ ] Remove only the five tracked historical ZIPs from Git index while keeping the current untracked Build 18 ZIP on disk.
- [ ] Correct ignore rules and whitespace, then run requested component, Sparkle, Swift, diff, and secret-scan gates.
- [ ] Record command outcomes/counts and commit all intended fixes locally.
