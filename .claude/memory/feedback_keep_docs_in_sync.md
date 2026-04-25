---
name: Keep README in sync with script/code changes
description: When you add a script or change behavior, update the README in the same turn — don't wait to be told.
type: feedback
---

When adding a new script, flag, or behavior change, update README/docs in the same turn. Don't wait to be asked.

**Why:** A new script (`scripts/setup-dockerhub-creds.sh`) was added without README coverage, and a later attempt placed the documentation at the end of the README near Teardown — which made no sense for a step that runs right after bootstrap. Lab convention: docs land alongside the code change, in the section a reader would naturally hit when they need it.

**How to apply:**
- After adding a new script or flag: README gets a section in the same response. Don't ask "want me to document this?" — just do it.
- Place documentation where a reader would *encounter the need*, not as a trailing appendix. New steps go inline with the milestone they belong to (e.g., a follow-up to bootstrap goes inside the Milestone-1 section, not in a "Teardown" or "Misc" tail).
- Same applies to the file map — list new scripts there.
