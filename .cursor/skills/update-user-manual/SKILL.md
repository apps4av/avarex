---
name: update-user-manual
description: Update USER_MANUAL.md when code changes affect app features, UI, or APIs. Use after implementing new features, modifying existing functionality, changing navigation paths, adding/removing screens, or altering platform availability.
---

# Update User Manual

## File Locations

- **Source**: `USER_MANUAL.md` (root directory)
- **PDF output**: `assets/docs/` (converted from source)

After updating `USER_MANUAL.md`, regenerate the PDF in `assets/docs/`.

## When to Apply

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
|---------|---------|
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

## Update Workflow

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

### Step 5: Regenerate PDF

After updating `USER_MANUAL.md`, convert it to PDF and place in `assets/docs/`.

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
