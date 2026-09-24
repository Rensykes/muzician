# Product

## Register

product

## Users

Independent songwriters and musicians who primarily write on guitar and piano. They may be holding an instrument, rehearsing, or sketching on a phone or tablet. They want to capture a chord, lyric, melody, or groove quickly, then develop it into a song without losing the original idea.

## Product Purpose

Muzician is a songwriting workspace that connects guitar and piano exploration, music theory, lyrics, arrangement, and demo playback. Success means a musician can move from an initial musical idea to a structured, audible draft and shareable output while staying oriented and keeping their work safe.

This is the initial product context inferred from the existing app and the user's stated focus. Treat it as the working direction for planning and implementation, and revise it when product intent changes.

Writer supports section-level melody and guitar-strum patterns that can move
into Song as note tracks. Writer audio lanes remain part of the section sketch
and are not included in that import. Both Writer and Song provide bounded,
project-scoped undo and redo so a draft can be explored and recovered. Native
Song Bundles carry an arrangement and its referenced audio sources between
devices; Web explains that bundle import and export are unsupported because its
audio repository is filesystem-backed.

## Brand Personality

Creative, clear, musician-first. Muzician should feel encouraging and musically literate, with theory presented as practical help rather than a test. The product should support play and experimentation while keeping the user's own decisions in control.

## Anti-references

- A general-purpose DAW interface that exposes studio complexity before a song idea exists.
- A theory textbook or quiz app that interrupts writing to explain concepts out of context.
- Generic AI songwriting that replaces the user's voice or silently changes their work.
- A productivity dashboard that makes projects, counts, or status more prominent than the music.
- Hidden gestures as the only way to discover important editing actions.

## Design Principles

1. **Start from the idea.** Make it quick to capture or continue a song before asking the user to configure a workspace.
2. **Keep instruments close to composition.** Guitar and piano exploration should feed the current song directly.
3. **Show theory in context.** Chord, scale, key, and voicing information should support a musical decision and remain optional.
4. **Make the draft audible.** Let users hear changes in the section or arrangement they are writing.
5. **Protect creative work.** Keep drafts recoverable with undo and redo, communicate save state clearly, and confirm project replacement before it begins.

## Accessibility & Inclusion

Design for touch-first use on phones and tablets, with readable text, scalable layouts, accessible labels for controls, keyboard support where available, and reduced reliance on color alone. Important actions should have visible affordances and forgiving recovery. Verify compact and wide layouts, including landscape, when changing user-facing screens.
