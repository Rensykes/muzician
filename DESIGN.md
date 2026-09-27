---
name: Muzician
description: A songwriting workspace connecting guitar, piano, and song arrangement.
colors:
  background: "#0A0A1E"
  gradient-violet: "#1A1034"
  gradient-indigo: "#16213E"
  gradient-blue: "#0F3460"
  surface: "#0A0F1E"
  dialog: "#161B2E"
  text-primary: "#F1F5F9"
  text-secondary: "#94A3B8"
  text-muted: "#8B9DC3"
  text-dim: "#334155"
  accent-sky: "#38BDF8"
  accent-teal: "#4ECDC4"
  accent-violet: "#A78BFA"
  accent-purple: "#C084FC"
  accent-emerald: "#34D399"
  accent-orange: "#FB923C"
  accent-red: "#F87171"
  glass-fill: "#08FFFFFF"
  glass-border: "#12FFFFFF"
typography:
  display:
    fontFamily: "Flutter Material default"
    fontSize: "32px"
    fontWeight: 800
  title:
    fontFamily: "Flutter Material default"
    fontSize: "20px"
    fontWeight: 700
  body:
    fontFamily: "Flutter Material default"
    fontSize: "14px"
    fontWeight: 400
  label:
    fontFamily: "Flutter Material default"
    fontSize: "11px"
    fontWeight: 600
rounded:
  sm: "10px"
  md: "14px"
  lg: "16px"
  sheet: "20px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  2xl: "28px"
  3xl: "36px"
components:
  icon-button:
    textColor: "{colors.text-secondary}"
    size: "44px"
    height: "44px"
  status-chip:
    backgroundColor: "{colors.glass-fill}"
    textColor: "{colors.text-primary}"
    rounded: "999px"
    padding: "5px 10px"
  glass-panel:
    backgroundColor: "{colors.glass-fill}"
    rounded: "{rounded.md}"
  dialog:
    backgroundColor: "{colors.dialog}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.lg}"
---

# Design System: Muzician

## 1. Overview

**Creative North Star: "The Songwriter's Workbench"**

Muzician is used with an instrument nearby: a songwriter checks a chord shape, captures a lyric, and listens back in the same session. The current interface uses a dark, layered canvas with compact controls so the musical surface remains central. This document records the existing visual language; it does not mandate that every screen use glass effects or prevent a future light theme.

The interface should feel focused, tactile, and musically legible. Keep high information density inside instrument and timeline workspaces, and use clearer grouping around the primary action. Prefer familiar Flutter controls and direct manipulation over decorative treatment.

**Key Characteristics:**
- Dark blue-violet surfaces with restrained semantic accents.
- Compact typography with larger screen titles and concise labels.
- Rounded panels, chips, and dialogs with subtle borders.
- Accent colors indicate musical or interaction state.

## 2. Colors

The palette is a deep indigo canvas with distinct accents for selection, harmony, roots, warnings, and errors.

### Primary
- **Sky accent** (#38BDF8): selected controls, primary actions, active navigation, and note selection.
- **Teal accent** (#4ECDC4): scale highlights and secondary musical emphasis.

### Secondary
- **Violet accent** (#A78BFA): chord highlights.
- **Purple accent** (#C084FC): supporting emphasis where the existing UI uses it.
- **Emerald accent** (#34D399): root-note emphasis and positive musical state.

### Neutral
- **Scaffold night** (#0A0A1E): deepest app canvas, with a blue-violet vertical gradient used on major surfaces.
- **Panel ink** (#0A0F1E): compact panels and navigation surfaces.
- **Dialog slate** (#161B2E): raised dialog background.
- **Primary text** (#F1F5F9): titles and high-priority content.
- **Secondary text** (#94A3B8): supporting copy and controls.
- **Muted text** (#8B9DC3): less prominent labels.
- **Dim text** (#334155): disabled or very low-emphasis content; check contrast before using for essential text.
- **Orange** (#FB923C) and **red** (#F87171): warning and destructive/error states.

### Named Rules
**The Semantic Accent Rule.** Use accent color to communicate selection, musical role, or action state. Do not make color the only way to distinguish a note or control.

## 3. Typography

**Display Font:** Flutter Material default; no custom font family is configured.
**Body Font:** Flutter Material default.
**Label/Mono Font:** No separate label or monospace family is configured.

**Character:** Compact and neutral, keeping note names and musical structure readable without a decorative display face. The values below are representative sizes used across screens, not a single enforced text scale.

### Hierarchy
- **Display** (weight 800, 32px): primary screen headings on roomy layouts.
- **Headline** (weight 700, 20px): compact app-bar titles and secondary headings.
- **Title** (weight 700, 16–18px): dialogs and section headings.
- **Body** (regular, 13–14px): supporting descriptions and action content.
- **Label** (weight 600, 10–12px): navigation, chips, transport readouts, and compact control labels.

### Named Rules
**The Instrument Label Rule.** Keep note labels concise, but preserve readable sizing and text scaling around the instrument canvas.

## 4. Elevation

Depth currently comes mainly from tonal layering, translucent panel fills, and fine borders. Dialogs use a modest shadow and sit on a distinct slate surface. Reserve stronger elevation for transient overlays and dialogs; do not add blur or shadow to every panel.

### Shadow Vocabulary
- **Dialog elevation**: theme elevation 16 with a soft black shadow, used for modal dialogs.
- **Undo toast**: a broad, low-opacity shadow separates the temporary recovery action from the canvas.

### Named Rules
**The Layered Surface Rule.** Use a small surface-color shift and border to establish hierarchy before adding shadow.

## 5. Components

Components use familiar touch targets and low-contrast containers. Keep control states consistent across Fretboard, Piano, Roll, Song, and Writer.

### Buttons
- **Interactive controls:** at least 44×44px touch area, including pattern-grid steps; give them concise semantic labels and keyboard activation when available.
- **Icon buttons:** 44×44px touch area, 22px icon, secondary text color by default, with a tooltip or semantic label.
- **Dialog actions:** normal actions use secondary text; primary actions use sky; destructive actions use red.
- **Focus and disabled states:** preserve a visible keyboard-focus indication and sufficient contrast; disabled color must not carry essential information.
- **Undo and redo:** expose them in each workspace's overflow menu with clear text labels and disabled states. A temporary Writer delete snackbar may offer the same history undo action.

### Chips
- **Status chips:** translucent white fill, fine white border, pill radius, compact single-line label.
- **Musical state chips:** use sky, teal, violet, emerald, orange, or red according to the state they represent; pair color with a label or shape cue.

### Cards / Containers
- **Glass panels:** near-transparent white fill, subtle white border, 14px radius, and restrained padding. Use to group related controls, not as a wrapper around every element.
- **Dialogs:** slate surface, 16px radius, thin border, 16px elevation; keep actions clearly separated from content.

### Inputs / Fields
- Follow Material input behavior and labels. Show errors next to the field or action that needs attention and preserve entered work when correcting an error.
- Confirm replacement of a non-empty Song before opening the bundle picker; explain that a successful import can be undone.

### Navigation and Instrument Surfaces
- Keep the current workspace identifiable and the instrument canvas visually dominant.
- Instrument labels and highlights must remain readable at compact widths and with text scaling enabled.
- Expose essential gestures with visible controls or contextual help.

### Named Rules
**The Empty-State Hierarchy Rule.** Name the empty state, surface the contextually likely next action, preserve an alternate creation action, and state transfer boundaries in brief copy.

## 6. Do's and Don'ts

### Do
- Use the semantic accent mapping consistently across features.
- Group related tools and reveal advanced controls when they become relevant.
- Keep touch actions close to the musical object they affect.
- Verify compact and wide layouts, including landscape, when changing a visible screen.
- Pair color-coded musical states with text, shape, or position cues.

### Don't
- Add glass blur, glow, gradient text, or shadow as decoration.
- Use the dark palette by habit on surfaces where a musician needs more contrast or daylight readability; validate the use context.
- Put every action in an icon-only button without a tooltip or semantic name.
- Add dense theory controls to the main writing surface when they are not needed for the current decision.
