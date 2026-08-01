# CineBar Second Pre-merge Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the second review round without deployment, publishing, merging, or GitHub mutation.

**Architecture:** Keep appcast generation atomic but construct its escaped HTML description from text-only release notes; restore the legacy JSON migration manifest while checking it against the application and appcast metadata; and narrow CSP to demonstrated runtime needs.

**Tech Stack:** Bash, Node test runner, Cloudflare Workers, Next.js/TypeScript, Sparkle, Swift.

## Global Constraints

- Tests precede each production change and must fail for the intended behavior.
- Do not deploy, push, merge, publish a release, or mutate GitHub state.
- Keep Build 18 metadata and preserve atomic appcast replacement.
- Treat user-supplied notes only as text content, never markup.

---

### Task 1: Text-only Sparkle release notes

**Files:**
- Modify: `CineBar/Tools/tests/publish_sparkle_update.test.mjs`
- Modify: `CineBar/Tools/publish_sparkle_update.sh`

- [ ] Add a failing XML-structure test with a `<script>` note.
- [ ] Generate doubly escaped description text so XML parsing yields only `ul`/`li` markup and note text is not markup.
- [ ] Run publisher tests GREEN, including atomic rejection tests.

### Task 2: Build 18 migration manifest and CSP

**Files:**
- Modify: `CineBarShare/tests/share-worker.test.mjs`, `CineBarWebsite/tests/worker-security.test.mjs`
- Modify: `CineBarShare/worker.js`, `CineBarWebsite/worker/index.ts`

- [ ] Add failing assertions for the legacy migration endpoint and CSP exclusions.
- [ ] Restore `0.8.3` GitHub Releases migration JSON and remove unsupported CSP directives.
- [ ] Run Share and Website tests GREEN.

### Task 3: Site installation disclosure and verification

**Files:**
- Modify: `CineBarWebsite/tests/content.test.mjs`, `CineBarWebsite/app/page.tsx`

- [ ] Add a failing assertion for independent-signature versus Apple-notarization disclosure.
- [ ] Add visible bounded copy and rerun content tests GREEN.
- [ ] Run all requested component, Sparkle, Swift, diff, and secret-scan gates before local commit.
