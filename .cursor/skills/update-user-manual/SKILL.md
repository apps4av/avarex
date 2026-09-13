---
name: update-user-manual
description: >-
  Updates USER_MANUAL.md to match current code, prepends an AvareX Releases
  changelog entry whenever pubspec.yaml version changes, and syncs
  store/whatsnew from that entry. Use when bumping version, editing
  pubspec.yaml, writing release notes, updating USER_MANUAL.md, or
  documenting user-facing AvareX changes.
---

# Update User Manual

Keep `USER_MANUAL.md` accurate against the code, add a release note at the top of **AvareX Releases** for every new `version:` in `pubspec.yaml`, and sync store “What’s new” from that same entry.

Do this in the same turn as a version bump. Do not wait to be asked.

## File Locations

- **Source**: `USER_MANUAL.md` (root directory)
- **PDF output**: `assets/docs/` (converted from source)
- **Play / TestFlight notes**: `store/whatsnew/whatsnew-en-US`

After updating `USER_MANUAL.md`, regenerate the PDF in `assets/docs/`.

## Workflow

```
- [ ] Read version from pubspec.yaml (the X.Y.Z before +build)
- [ ] Read the top changelog version in USER_MANUAL.md
- [ ] Find the last pubspec version change in git (see below)
- [ ] Diff user-facing code since that commit
- [ ] Update manual body sections that no longer match the app
- [ ] If version is new, prepend a changelog block from that diff
- [ ] If version already has an entry, update that entry's bullets
- [ ] Sync store/whatsnew/whatsnew-en-US from the latest AvareX Releases entry
- [ ] Regenerate the PDF
```

## Changes since last pubspec version

Changelog bullets and manual edits come from git history, not from memory or this chat.

1. Read current `version:` from `pubspec.yaml`. Changelog heading is the part before `+` (e.g. `0.0.120` from `0.0.120+120`). Never use the `+` build number, `msix_version`, or snap version.
2. Read HEAD's version:

```bash
git show HEAD:pubspec.yaml | sed -n 's/^version: //p'
```

3. Find the commit that last **changed** the pubspec version (newest first):

```bash
git log --format='%H' -G '^version:' -- pubspec.yaml
```

4. Choose the range start (`SINCE`):

| Working tree vs HEAD | `SINCE` |
|----------------------|---------|
| version **differs** from HEAD (bump not committed yet) | First hash from that log (last committed version change) |
| version **matches** HEAD (bump already committed) | **Second** hash from that log (the previous version change) |

5. Collect this release's changes (include uncommitted work):

```bash
git log --oneline ${SINCE}..HEAD
git diff ${SINCE} -- lib/
```

6. Write changelog and manual only from user-facing app changes in that range (screens, drawers, tabs, map layers, plan/plate/find). Skip CI, store upload, secrets, and pubspec-only edits.

If git history is missing or `SINCE` cannot be found, say so and stop rather than inventing bullets.

## Versions

Source of truth is the current `version:` in `pubspec.yaml`. Changelog headings use **version name only** (e.g. `0.0.120`), never `+120`, `msix_version`, or `snap/snapcraft.yaml`.

Find the current top entry: first `**X.Y.Z**` after `## AvareX Releases`.

| Situation | Action |
|-----------|--------|
| version is new (not the top Releases entry) | Insert a new changelog block immediately under `AvareX Releases` |
| version already is the top entry | Update that entry's bullets; do not add a second block |
| Version was not bumped | Still fix manual body if code/UI changed; do not invent a version |

If this session is bumping the version, add/update the changelog even if the user did not mention the manual.

## Changelog format

Insert **immediately after** `## AvareX Releases`. Copy this shape exactly (blank line after the heading and after the version, period at end of each bullet):

```markdown
## AvareX Releases

**0.0.121**

- Fixed Plan waypoint reorder.
- Bug fixes.

**0.0.120**
```

Bullet rules:

- Short, user-facing. What a pilot sees, not class names or file paths.
- One idea per `- ` line. Start with a verb or concise phrase (`Fixed`, `Added`, `Enable`, `Change`).
- End with a period.
- Use the app's own labels (`MAP`, `PLAN`, `Cloud`, `Brief`).
- Use `Bug fixes.` only for leftover non-user-visible fixes after the real bullets.
- Do not add dates, authors, issue numbers, or build (`+N`) numbers.
- Do not rewrite older entries.

## Play / TestFlight what’s new

After the latest **AvareX Releases** bullets are written or updated, regenerate store notes:

```bash
bash .github/scripts/update-whatsnew.sh
```

That script copies the latest changelog bullets into `store/whatsnew/whatsnew-en-US` (Play’s 500-character limit). CI also runs it before a store upload. Do not hand-edit `whatsnew-en-US`; change the manual changelog and run the script.

## When to Apply (manual body)

After completing code changes that affect:
- New features or screens
- UI controls, buttons, or navigation paths
- Menu entries or drawer items
- Platform-specific availability
- Map layers, chart types, or overlays
- Step-by-step user workflows

## Manual Structure Reference

The `USER_MANUAL.md` follows this organization:

| Section | Content |
|---------|---|
| AvareX Releases | Changelog; newest version first |
| 1 | Before You Start (safety, requirements, onboarding) |
| 2 | Platform Feature Availability table |
| 3 | Main Navigation (tabs, drawers) |
| 4 | MAP Tab (controls, layers, chart types) |
| 5 | Destination Popup |
| 6 | PLATE Tab |
| 7 | PLAN Tab (editor, nav log, actions) |
| 8 | FIND Tab |
| 9 | Drawer Features (Download, Documents, Aircraft, etc.) |
| 10 | Notes Screen |
| 11 | Pro Services |
| 12 | Warnings/Troubleshooting |
| 13 | Data Lifecycle |
| 14 | Quick Feature Path Index |
| 15 | Step-by-Step Use Cases (UC-##) |
| 16 | Resources and Support |
| 17 | Forum FAQ (FAQ-##) |

## Update Workflow (manual body)

### Step 1: Identify change type

Determine what changed:
- **New feature**: Add to relevant section + update Section 14 path index
- **UI change**: Update control descriptions in relevant section
- **Navigation change**: Update Section 3 + affected feature section
- **Platform availability**: Update Section 2 table
- **New use case**: Add UC-## entry in Section 15

### Step 2: Locate affected sections

Read the relevant manual sections:
```
Read USER_MANUAL.md lines for affected sections
```

Cross-reference with:
- Section 14 (Quick Feature Path Index) - always check if paths changed
- Section 2 (Platform Availability) - if feature has platform restrictions

### Step 3: Apply updates

Follow these conventions:

**Formatting:**
- Use `backticks` for: screen names, tab names, button labels, menu items
- Use **bold** for: action verbs in instructions, important notes
- Use tables for: feature availability, layer descriptions, control lists

**Paths format:**
```
MAP → Menu → Download
PLAN → Actions → Brief & File
```

**Control descriptions:**
```markdown
- **Button name**: what it does
- **Control name** (condition): behavior description
```

**Use case format:**
```markdown
### UC-##: Title describing the goal

Brief description when useful.

1. Step with `UI element` reference.
2. Step with **action** emphasis.
3. Continue numbered steps.
```

### Step 4: Verify consistency

Check these items:

- [ ] All new UI paths added to Section 14 index
- [ ] Platform restrictions noted in Section 2 if applicable
- [ ] Terminology matches existing manual (e.g., "drawer" not "sidebar")
- [ ] Cross-references between sections are accurate
- [ ] No duplicate UC-## or FAQ-## numbers

### Step 5: Sync what’s new and regenerate PDF

After updating `USER_MANUAL.md` (body or Releases):

```bash
bash .github/scripts/update-whatsnew.sh
./.cursor/scripts/regenerate_user_manual_pdf.sh
```

## Terminology Reference

Use these terms consistently:

| Use | Avoid |
|-----|-------|
| drawer | sidebar, menu panel |
| tab | page, view |
| long-press | long tap, hold |
| popup | dialog, modal |
| layer | overlay (unless overlay is correct) |
| ownship | own ship, aircraft position |

## Quick Update Examples

**Adding a new map layer:**
1. Add to Section 4.5 layer list
2. Describe what the layer shows
3. Note any dependencies (altitude slider, other layers)

**Adding a drawer menu item:**
1. Add to Section 3.2 drawer list
2. Create new Section 9.X with full description
3. Add path to Section 14 index

**Adding a new screen/feature:**
1. Create appropriate section or subsection
2. Include: how to access, what it does, controls
3. Add to Section 14 path index
4. Consider if UC-## example is needed

**Changing navigation:**
1. Update all affected sections
2. Update Section 14 paths
3. Search manual for old path references

## Do not

- Change `pubspec.yaml` `version:` from this skill unless the user asked for a version bump.
- Reformat the whole `USER_MANUAL.md`.
- Add a changelog when version is unchanged.
- Hand-write `store/whatsnew/whatsnew-en-US`; always generate it from `USER_MANUAL.md`.
