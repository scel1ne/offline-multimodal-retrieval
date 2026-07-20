# Accessibility User Guide

**Author:** Celine Song
**Status:** Week 5 draft
**Last updated:** 2026-07-20

## Overview

The Offline Local Retrieval UI is designed to support keyboard navigation,
screen-reader labels, adjustable text size, and high-contrast viewing.

## Keyboard Use

| Action | Control |
|---|---|
| Move through controls | Tab / Shift+Tab |
| Start a search | Focus the search field, type a query, then press Enter or activate Search |
| Clear indexed files | Navigate to Clear and activate the button |
| Import or export an index | Navigate to Import or Export and activate the button |

## Visual Preferences

Use the theme button to switch between light and dark presentation. Use the
font-size slider to increase or reduce UI text size while staying in the same
workspace.

## Screen Reader Notes

The main Library and Search areas are exposed with visible headings. Status
updates use live-region semantics so assistive technologies can announce
important changes such as empty search results or indexing progress.

## Current Limitations

Native file picker dialogs depend on the operating system. Manual VoiceOver
validation on macOS is recommended before final delivery.
