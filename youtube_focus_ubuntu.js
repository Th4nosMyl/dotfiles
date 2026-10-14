// ==UserScript==
// @name         YouTube – Ubuntu Focus (learning mode)
// @namespace    ubuntu-yt
// @version      2.2
// @description  Ubuntu/Yaru deep-dark theme + tools that make YouTube a learning tool
// @match        https://www.youtube.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

/* ==========================================================
   YouTube – Ubuntu Focus  (all-in-one, portable)
   • One file: theme (CSS) + features (JS), no dependencies.
   • Pasted into Enhancer for YouTube -> Custom script
     (tick "Automatically execute...") or in Tampermonkey /
     Violentmonkey (the header above makes it a userscript).
   • Change behaviour ONLY in the CONFIG block below.
   • Distraction hiding (home feed, Shorts, comments, sidebar,
     end screens) is left to the Unhook extension on purpose.
   • Best with YouTube's own dark theme turned on.

   v2.2 changes
   • Removed the break reminder and the daily limit.
     The watch-time counter (Alt+Shift+D) is still there.

   v2.1 changes
   • Toasts work even with theme: false (own base CSS).
   • Uses the main player's <video> (ignores hover previews).
   • Search filter can be cleared; applied once per query.
   • Watch time kept in memory, saved every 15 s and on exit;
     several tabs add up correctly instead of overwriting.
   • Search filter runs on YouTube navigation, not on every
     DOM change.
   • Shortcut letters work in upper or lower case.
   • Transcript button found with a Greek UI too.
   • Clearer message when copying fails ("press again").
   ========================================================== */
(() => {
  "use strict";
  if (window.__ubuntuYT) return; // never run twice
  window.__ubuntuYT = true;

  /* ==================== CONFIG ==================== */
  const CONFIG = {
    // Look
    theme: true,                 // inject the Ubuntu deep-dark CSS
    orangeLogo: true,            // red YouTube logo -> Ubuntu orange
    orangeFavicon: true,         // orange tab icon

    // Search = the front door. Results open pre-filtered:
    //   "video" -> videos only (no Shorts, channels, playlists, movies)
    //   "long"  -> videos longer than 20 min (lectures, deep dives)
    //   "none"  -> don't touch search
    // You can still remove the filter by hand for that search.
    searchFilter: "video",

    // Watch page
    autoExpandDescription: true, // open the description automatically

    // Keyboard shortcuts (Alt + Shift + <key>)
    // Note: on Windows / some Linux setups Alt+Shift also switches
    // keyboard language. If that bothers you, change the layout
    // switch shortcut in your OS settings.
    keys: {
      timestamp: "T",       // copy "- [12:34] Title — link?t=754" (for your notes)
      copyTranscript: "X",  // copy the whole transcript (notes / summaries)
      transcript: "P",      // open the transcript panel
      today: "D",           // show today's total watch time
    },
  };

  const ORANGE = "#E95420";
  const STORE = "ubuntuYT:";

  /* ==================== BASE CSS (always on) ==================== */
  const BASE_CSS = `
/* ---------- Toast (Ubuntu notification bubble) ---------- */
#ub-toast {
  position: fixed;
  left: 24px;
  bottom: 24px;
  z-index: 2147483647;
  max-width: 380px;
  padding: 12px 16px;
  background: var(--ub-surface, #141414);
  color: #fff;
  border: 1px solid var(--ub-border, #2e2e2e);
  border-left: 4px solid var(--ub-orange, #e95420);
  border-radius: 8px;
  font: 500 14px/1.4 "Ubuntu", "Cantarell", "Segoe UI", sans-serif;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6);
  opacity: 0;
  transform: translateY(8px);
  pointer-events: none;
  transition: opacity 0.2s ease, transform 0.2s ease;
}

#ub-toast.ub-show {
  opacity: 1;
  transform: translateY(0);
}
`;

  /* ==================== THEME (CSS) ==================== */
  const THEME_CSS = `
/* ---------- Core color tokens (YouTube's own variables) ---------- */
html,
html[dark],
[dark] {
  --ub-orange: #e95420;
  --ub-orange-light: #f47b4f;
  --ub-bg: #0a0a0a;
  --ub-surface: #141414;
  --ub-raised: #1e1e1e;
  --ub-border: #2e2e2e;
  --ub-text: #ffffff;
  --ub-text-2: #c4c4c4;
  --ub-text-3: #8f8f8f;

  --yt-spec-base-background: var(--ub-bg) !important;
  --yt-spec-raised-background: var(--ub-surface) !important;
  --yt-spec-menu-background: var(--ub-surface) !important;
  --yt-spec-inverted-background: #f2f2f2 !important;
  --yt-spec-additive-background: rgba(255, 255, 255, 0.06) !important;
  --yt-spec-outline: var(--ub-border) !important;
  --yt-spec-shadow: rgba(0, 0, 0, 0.5) !important;
  --yt-spec-general-background-a: var(--ub-bg) !important;
  --yt-spec-general-background-b: var(--ub-bg) !important;
  --yt-spec-general-background-c: var(--ub-surface) !important;

  --yt-spec-text-primary: var(--ub-text) !important;
  --yt-spec-text-secondary: var(--ub-text-2) !important;
  --yt-spec-text-disabled: var(--ub-text-3) !important;

  --yt-spec-call-to-action: var(--ub-orange-light) !important;
  --yt-spec-themed-blue: var(--ub-orange-light) !important;
  --yt-spec-static-brand-red: var(--ub-orange) !important;
  --yt-spec-brand-icon-active: var(--ub-orange) !important;
  --yt-spec-brand-link-text: var(--ub-orange-light) !important;
  --yt-spec-brand-button-background: var(--ub-orange) !important;

  --yt-spec-button-chip-background: var(--ub-raised) !important;
  --yt-spec-button-chip-background-hover: #262626 !important;
  --yt-spec-badge-chip-background: var(--ub-raised) !important;
  --yt-spec-10-percent-layer: rgba(255, 255, 255, 0.1) !important;
  --yt-spec-touch-response: #ffffff !important;
  --yt-spec-suggested-action: rgba(233, 84, 32, 0.18) !important;
  --yt-spec-filled-button-text: #ffffff !important;
  --yt-spec-selected-nav-text: var(--ub-text) !important;
}

/* ---------- Page & font ---------- */
html,
body,
ytd-app,
#content.ytd-app {
  background: var(--ub-bg) !important;
  font-family: "Ubuntu", "Cantarell", "Segoe UI", sans-serif !important;
}

body,
ytd-app,
input,
button,
textarea,
yt-formatted-string,
#video-title,
#channel-name,
.ytd-video-meta-block,
.yt-core-attributed-string {
  font-family: "Ubuntu", "Cantarell", "Segoe UI", sans-serif !important;
}

/* ---------- Top bar (like the GNOME top panel) ---------- */
ytd-masthead,
#masthead-container,
ytd-masthead #container.ytd-masthead {
  background: #050505 !important;
  border-bottom: 1px solid var(--ub-border) !important;
}

/* Logo accent */
ytd-masthead #logo-icon svg g:first-child path:first-child,
ytd-topbar-logo-renderer #logo-icon path[fill="#F00"],
ytd-topbar-logo-renderer #logo-icon path[fill="#FF0000"],
ytd-topbar-logo-renderer #logo-icon path[fill="red"] {
  fill: var(--ub-orange) !important;
}

/* ---------- Search box ---------- */
yt-searchbox .ytSearchboxComponentInputBox,
ytd-searchbox #container.ytd-searchbox,
form.ytd-searchbox {
  background: var(--ub-bg) !important;
  border: 1px solid var(--ub-border) !important;
  border-radius: 8px 0 0 8px !important;
}

yt-searchbox .ytSearchboxComponentInputBoxHasFocus,
ytd-searchbox[has-focus] #container.ytd-searchbox {
  border-color: var(--ub-orange) !important;
  box-shadow: 0 0 0 1px var(--ub-orange) !important;
}

yt-searchbox .ytSearchboxComponentSearchButton,
#search-icon-legacy.ytd-searchbox {
  background: var(--ub-raised) !important;
  border: 1px solid var(--ub-border) !important;
  border-radius: 0 8px 8px 0 !important;
}

yt-searchbox .ytSearchboxComponentSearchButton:hover,
#search-icon-legacy.ytd-searchbox:hover {
  background: var(--ub-orange) !important;
  border-color: var(--ub-orange) !important;
}

/* ---------- Sidebar (Ubuntu dock feel) ---------- */
ytd-guide-renderer,
ytd-mini-guide-renderer,
tp-yt-app-drawer,
#guide-inner-content,
#guide-content {
  background: #050505 !important;
}

ytd-guide-entry-renderer,
ytd-mini-guide-entry-renderer {
  border-radius: 8px !important;
}

ytd-guide-entry-renderer:hover,
ytd-mini-guide-entry-renderer:hover {
  background: var(--ub-raised) !important;
}

/* Active item: orange bar on the left, like the Ubuntu dock */
ytd-guide-entry-renderer[active] > #endpoint,
ytd-guide-entry-renderer[active] {
  background: rgba(233, 84, 32, 0.16) !important;
  box-shadow: inset 3px 0 0 var(--ub-orange) !important;
}

ytd-guide-entry-renderer[active] yt-icon,
ytd-guide-entry-renderer[active] .title {
  color: var(--ub-orange-light) !important;
  fill: var(--ub-orange-light) !important;
}

/* ---------- Filter chips ---------- */
yt-chip-cloud-chip-renderer,
ytd-feed-filter-chip-bar-renderer #chips-wrapper {
  --yt-chip-background: var(--ub-raised);
}

yt-chip-cloud-chip-renderer,
yt-chip-cloud-chip-renderer #chip-container,
.ytChipShapeChip {
  background: var(--ub-raised) !important;
  border-radius: 8px !important;
  color: var(--ub-text) !important;
}

yt-chip-cloud-chip-renderer:hover,
.ytChipShapeChip:hover {
  background: #262626 !important;
}

yt-chip-cloud-chip-renderer[selected],
yt-chip-cloud-chip-renderer[chip-style="STYLE_DEFAULT"][selected] #chip-container,
.ytChipShapeActive,
.ytChipShapeChip.ytChipShapeActive {
  background: var(--ub-orange) !important;
  color: #ffffff !important;
}

ytd-feed-filter-chip-bar-renderer,
ytd-feed-filter-chip-bar-renderer #chips-wrapper {
  background: var(--ub-bg) !important;
  border-bottom: 1px solid var(--ub-border) !important;
}

/* ---------- Video cards ---------- */
ytd-rich-item-renderer,
ytd-video-renderer,
ytd-compact-video-renderer {
  --ytd-rich-item-row-gap: 24px;
}

ytd-thumbnail,
ytd-thumbnail a,
.yt-thumbnail-view-model,
yt-thumbnail-view-model,
ytd-playlist-thumbnail,
.yt-core-image--content-mode-scale-aspect-fill {
  border-radius: 8px !important;
}

ytd-thumbnail:hover,
yt-thumbnail-view-model:hover {
  outline: 2px solid var(--ub-orange) !important;
  outline-offset: -2px;
}

#video-title.ytd-rich-grid-media,
#video-title.ytd-video-renderer,
h3.ytd-rich-grid-media a {
  color: var(--ub-text) !important;
  font-weight: 500 !important;
}

a:hover #video-title,
#video-title:hover {
  color: var(--ub-orange-light) !important;
}

/* Duration badge */
ytd-thumbnail-overlay-time-status-renderer,
.badge-shape-wiz--thumbnail-default,
.yt-badge-shape--thumbnail-default {
  background: rgba(5, 5, 5, 0.9) !important;
  border-radius: 4px !important;
}

/* Watched-progress bar on thumbnails */
ytd-thumbnail-overlay-resume-playback-renderer #progress {
  background: var(--ub-orange) !important;
}

/* ---------- Video player ---------- */
.html5-video-player,
.html5-video-container {
  background: #000 !important;
}

/* Progress / scrubber */
.ytp-play-progress,
.ytp-swatch-background-color {
  background: var(--ub-orange) !important;
}

.ytp-scrubber-button,
.ytp-scrubber-container .ytp-scrubber-button {
  background: var(--ub-orange) !important;
}

.ytp-load-progress {
  background: rgba(255, 255, 255, 0.35) !important;
}

.ytp-hover-progress {
  background: rgba(233, 84, 32, 0.4) !important;
}

/* Chapter markers / heatmap */
.ytp-heat-map-path {
  fill: var(--ub-orange) !important;
  opacity: 0.35;
}

/* Player menus & tooltips */
.ytp-popup,
.ytp-settings-menu,
.ytp-tooltip-text-wrapper .ytp-tooltip-text,
.ytp-tooltip-text {
  background: rgba(10, 10, 10, 0.96) !important;
  border: 1px solid var(--ub-border);
  border-radius: 8px !important;
}

.ytp-menuitem:hover,
.ytp-panel-menu .ytp-menuitem[aria-checked="true"] {
  background: rgba(233, 84, 32, 0.2) !important;
}

.ytp-menuitem[aria-checked="true"] .ytp-menuitem-label {
  color: var(--ub-orange-light) !important;
}

.ytp-menuitem-toggle-checkbox {
  background: var(--ub-border) !important;
}

.ytp-menuitem[aria-checked="true"] .ytp-menuitem-toggle-checkbox {
  background: var(--ub-orange) !important;
}

/* Autoplay switch */
.ytp-autonav-toggle-button[aria-checked="true"]::after,
.ytp-autonav-toggle-button-container .ytp-autonav-toggle-button[aria-checked="true"] {
  background-color: var(--ub-orange) !important;
}

/* Volume slider */
.ytp-volume-slider-handle,
.ytp-volume-slider-handle::before {
  background: var(--ub-orange) !important;
}

/* ---------- Enhancer for YouTube controls ---------- */
.eyt-cinema-mode,
#eyt-controls,
.enhancer-for-youtube {
  --eyt-accent: var(--ub-orange);
}

.ytp-button.eyt-button:hover,
.ytp-button[class*="eyt"]:hover {
  color: var(--ub-orange-light) !important;
}

/* Enhancer's on-screen indicators (volume/speed pop-up) */
#eyt-volume-indicator,
#eyt-speed-indicator,
.eyt-osd,
[id^="eyt-"][class*="osd"] {
  background: rgba(10, 10, 10, 0.92) !important;
  border: 1px solid var(--ub-orange) !important;
  border-radius: 8px !important;
  color: #fff !important;
}

/* ---------- Buttons ---------- */
/* Subscribe */
ytd-subscribe-button-renderer yt-button-shape button,
yt-subscribe-button-view-model button,
.yt-spec-button-shape-next--filled.yt-spec-button-shape-next--mono {
  border-radius: 8px !important;
}

/* Subscribed / secondary buttons */
.yt-spec-button-shape-next--tonal,
ytd-button-renderer .yt-spec-button-shape-next--tonal {
  background: var(--ub-raised) !important;
  border-radius: 8px !important;
}

.yt-spec-button-shape-next--tonal:hover {
  background: #262626 !important;
}

/* Blue call-to-action buttons → orange */
.yt-spec-button-shape-next--call-to-action,
.yt-spec-button-shape-next--filled.yt-spec-button-shape-next--call-to-action {
  background: var(--ub-orange) !important;
  color: #fff !important;
}

.yt-spec-button-shape-next--call-to-action:hover {
  background: var(--ub-orange-light) !important;
}

.yt-spec-button-shape-next--call-to-action-text,
.yt-spec-button-shape-next--text.yt-spec-button-shape-next--call-to-action {
  color: var(--ub-orange-light) !important;
}

/* Like/dislike pill */
yt-smartimation .yt-spec-button-shape-next,
segmented-like-dislike-button-view-model .yt-spec-button-shape-next {
  background: var(--ub-raised) !important;
}

/* ---------- Watch page ---------- */
ytd-watch-flexy,
ytd-watch-flexy[theater],
#columns.ytd-watch-flexy,
#primary.ytd-watch-flexy,
#secondary.ytd-watch-flexy {
  background: var(--ub-bg) !important;
}

/* Description box */
ytd-watch-metadata #description,
#description-inner,
ytd-text-inline-expander {
  background: var(--ub-surface) !important;
  border-radius: 8px !important;
}

ytd-watch-metadata #description:hover {
  background: var(--ub-raised) !important;
}

/* Links in descriptions/comments */
#description a,
ytd-comment-view-model a,
yt-attributed-string a,
.yt-core-attributed-string__link {
  color: var(--ub-orange-light) !important;
}

/* Comments */
ytd-comments,
ytd-comment-thread-renderer {
  background: transparent !important;
}

#comment-teaser,
ytd-comment-simplebox-renderer #simple-box {
  border-radius: 8px !important;
}

/* Comment input underline */
tp-yt-paper-input-container .underline .focused-line,
#underline .style-scope.ytd-comment-simplebox-renderer,
ytd-commentbox #contenteditable-root:focus {
  border-color: var(--ub-orange) !important;
  background-color: var(--ub-orange) !important;
}

/* Up-next / recommendations */
ytd-compact-video-renderer:hover #video-title,
yt-lockup-view-model:hover a {
  color: var(--ub-orange-light) !important;
}

ytd-playlist-panel-renderer,
ytd-playlist-panel-renderer #container,
ytd-playlist-panel-renderer .header {
  background: var(--ub-surface) !important;
  border-radius: 8px !important;
  border: 1px solid var(--ub-border) !important;
}

ytd-playlist-panel-video-renderer[selected] {
  background: rgba(233, 84, 32, 0.2) !important;
}

/* Live chat */
yt-live-chat-renderer,
#chat-container,
ytd-live-chat-frame {
  background: var(--ub-bg) !important;
  border-radius: 8px !important;
  border-color: var(--ub-border) !important;
}

/* ---------- Menus, popups, dialogs ---------- */
ytd-popup-container tp-yt-paper-dialog,
tp-yt-iron-dropdown .dropdown-content,
ytd-menu-popup-renderer,
ytd-multi-page-menu-renderer,
ytd-simple-menu-header-renderer,
yt-dropdown-menu tp-yt-paper-listbox,
ytd-searchbox-suggestions,
.sbsb_a,
yt-searchbox .ytSearchboxComponentSuggestionsContainer {
  background: var(--ub-surface) !important;
  border: 1px solid var(--ub-border) !important;
  border-radius: 8px !important;
}

tp-yt-paper-item:hover,
ytd-menu-service-item-renderer:hover,
ytd-compact-link-renderer:hover,
.sbsb_c:hover,
.sbsb_d {
  background: rgba(233, 84, 32, 0.18) !important;
}

/* Toggle switches */
tp-yt-paper-toggle-button[checked] .toggle-bar,
tp-yt-paper-toggle-button[checked] .toggle-button {
  background: var(--ub-orange) !important;
}

/* Tabs (channel pages, etc.) */
tp-yt-paper-tab.iron-selected,
yt-tab-shape[tab-title][aria-selected="true"],
.yt-tab-shape-wiz--selected {
  color: var(--ub-text) !important;
}

tp-yt-paper-tabs #selectionBar,
.yt-tab-shape-wiz__tab-bar,
yt-tab-group-shape #selectionBar {
  background: var(--ub-orange) !important;
  border-color: var(--ub-orange) !important;
}

/* ---------- Loading bar & spinners ---------- */
yt-page-navigation-progress #progress,
#progress.yt-page-navigation-progress {
  background: var(--ub-orange) !important;
}

tp-yt-paper-spinner .spinner-layer,
tp-yt-paper-spinner-lite .spinner-layer {
  border-color: var(--ub-orange) !important;
}

/* ---------- Focus & selection ---------- */
::selection {
  background: var(--ub-orange) !important;
  color: #ffffff !important;
}

a:focus-visible,
button:focus-visible,
[tabindex]:focus-visible {
  outline: 2px solid var(--ub-orange-light) !important;
  outline-offset: 2px;
}

/* ---------- Scrollbars (Yaru style) ---------- */
* {
  scrollbar-color: #3a3a3a var(--ub-bg);
}

::-webkit-scrollbar {
  width: 12px;
  height: 12px;
}

::-webkit-scrollbar-track {
  background: var(--ub-bg) !important;
}

::-webkit-scrollbar-thumb {
  background: #3a3a3a !important;
  border: 3px solid var(--ub-bg);
  border-radius: 8px;
}

::-webkit-scrollbar-thumb:hover {
  background: var(--ub-orange) !important;
}

/* ---------- Misc dividers ---------- */
ytd-guide-section-renderer,
#dividers,
.ytd-guide-section-renderer,
ytd-menu-renderer[has-flexible-items] {
  border-color: var(--ub-border) !important;
}

hr,
#border.ytd-watch-metadata {
  border-color: var(--ub-border) !important;
  background-color: var(--ub-border) !important;
}


/* ==========================================================
   EXTRA: more Ubuntu / GNOME / Yaru feel
   ========================================================== */

/* GNOME-panel style top bar: pure black with a thin orange edge */
ytd-masthead,
#masthead-container {
  background: #000000 !important;
  border-bottom: 1px solid var(--ub-border) !important;
  box-shadow: 0 1px 0 rgba(233, 84, 32, 0.55) !important;
}

/* Icon buttons: rounded squares (Yaru) instead of circles */
yt-icon-button,
ytd-button-renderer yt-icon-button,
.yt-spec-button-shape-next--icon-button,
#guide-button,
button.yt-spec-button-shape-next--size-m.yt-spec-button-shape-next--icon-button {
  border-radius: 8px !important;
}

yt-icon-button:hover,
.yt-spec-button-shape-next--icon-button:hover {
  background: rgba(233, 84, 32, 0.18) !important;
}

yt-icon-button:hover yt-icon,
.yt-spec-button-shape-next--icon-button:hover yt-icon {
  color: var(--ub-orange-light) !important;
  fill: var(--ub-orange-light) !important;
}

/* Sidebar as a dock: floating rounded entries with spacing */
ytd-guide-entry-renderer #endpoint,
ytd-mini-guide-entry-renderer #endpoint {
  border-radius: 8px !important;
  margin: 1px 6px !important;
}

ytd-guide-entry-renderer:hover #endpoint {
  background: var(--ub-raised) !important;
}

ytd-guide-section-renderer #guide-section-title,
ytd-guide-section-renderer h3 {
  color: var(--ub-text-3) !important;
  font-weight: 500 !important;
}

/* Windows-like cards: subtle border like Yaru windows */
ytd-rich-grid-media,
ytd-video-renderer,
ytd-compact-video-renderer,
ytd-channel-renderer,
ytd-playlist-renderer,
yt-lockup-view-model {
  border-radius: 8px !important;
}

ytd-thumbnail,
yt-thumbnail-view-model,
ytd-playlist-thumbnail {
  border: 1px solid var(--ub-border) !important;
  box-sizing: border-box;
  overflow: hidden;
}

/* Channel avatars: subtle border */
yt-img-shadow.ytd-video-owner-renderer img,
#avatar img,
yt-img-shadow#avatar img {
  border: 1px solid var(--ub-border) !important;
}

/* Checkboxes / radios / sliders in Yaru orange */
tp-yt-paper-checkbox[checked] #checkbox,
tp-yt-paper-checkbox #checkbox.checked {
  background-color: var(--ub-orange) !important;
  border-color: var(--ub-orange) !important;
}

tp-yt-paper-radio-button[checked] #onRadio,
tp-yt-paper-radio-button[checked] #offRadio {
  background-color: var(--ub-orange) !important;
  border-color: var(--ub-orange) !important;
}

tp-yt-paper-slider .slider-knob-inner,
tp-yt-paper-slider .slider-bar-container .slider-progress,
tp-yt-paper-slider #sliderBar #primaryProgress {
  background-color: var(--ub-orange) !important;
  border-color: var(--ub-orange) !important;
}

/* Notification badge & LIVE badge */
yt-icon-badge-shape .yt-icon-badge-shape__badge,
ytd-notification-topbar-button-renderer #notification-count,
.yt-spec-icon-badge-shape--type-notification .yt-spec-icon-badge-shape__badge {
  background: var(--ub-orange) !important;
  color: #fff !important;
}

ytd-badge-supported-renderer.badge-style-type-live-now,
.badge-style-type-live-now-alternate,
.yt-badge-shape--live {
  background: var(--ub-orange) !important;
  color: #fff !important;
}

/* Player: deeper control-bar gradient */
.ytp-gradient-bottom,
.ytp-gradient-top {
  background-image: linear-gradient(to top, rgba(0, 0, 0, 0.85), rgba(0, 0, 0, 0)) !important;
}

.ytp-chrome-controls .ytp-button:hover {
  color: var(--ub-orange-light) !important;
}

.ytp-chrome-controls .ytp-button:hover svg {
  fill: var(--ub-orange-light) !important;
}

/* Text inputs everywhere (comments, playlists, dialogs) */
input,
textarea,
tp-yt-paper-input-container input,
#contenteditable-root {
  caret-color: var(--ub-orange) !important;
}

tp-yt-paper-input[focused] .input-content,
tp-yt-paper-input-container.paper-input-focused .underline .focused-line {
  border-color: var(--ub-orange) !important;
  background: var(--ub-orange) !important;
}

/* Toasts / snackbars */
tp-yt-paper-toast,
yt-notification-action-renderer,
ytd-notification-action-renderer {
  background: var(--ub-surface) !important;
  border: 1px solid var(--ub-orange) !important;
  border-radius: 8px !important;
  color: #fff !important;
}

/* Premium / upsell bits */
ytd-mealbar-promo-renderer,
.ytd-mealbar-promo-renderer {
  background: var(--ub-surface) !important;
  border-radius: 8px !important;
}

/* Keyboard focus ring like Ubuntu (orange) */
*:focus-visible {
  outline: 2px solid var(--ub-orange-light) !important;
  outline-offset: 1px !important;
}

/* ---------- Transcript: comfortable reading ---------- */
ytd-transcript-segment-renderer .segment-text,
transcript-segment-view-model .yt-core-attributed-string {
  font-size: 15px !important;
  line-height: 1.65 !important;
  color: var(--ub-text, #fff) !important;
}

ytd-transcript-segment-renderer .segment-timestamp,
transcript-segment-view-model .ytwTranscriptSegmentViewModelTimestamp {
  color: var(--ub-orange-light, #f47b4f) !important;
}

ytd-transcript-segment-renderer:hover,
transcript-segment-view-model:hover {
  background: rgba(233, 84, 32, 0.14) !important;
  border-radius: 8px !important;
}
`;

  /* ==================== helpers ==================== */
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  async function waitFor(fn, timeout = 4000, step = 150) {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
      const r = fn();
      if (r) return r;
      await sleep(step);
    }
    return null;
  }

  const load = (k, d) => {
    try {
      const v = localStorage.getItem(STORE + k);
      return v === null ? d : JSON.parse(v);
    } catch (e) {
      return d;
    }
  };
  const save = (k, v) => {
    try {
      localStorage.setItem(STORE + k, JSON.stringify(v));
    } catch (e) {}
  };

  const sessionGet = (k) => {
    try {
      return sessionStorage.getItem(STORE + k);
    } catch (e) {
      return null;
    }
  };
  const sessionSet = (k, v) => {
    try {
      sessionStorage.setItem(STORE + k, v);
    } catch (e) {}
  };

  function injectStyle(id, css) {
    let el = document.getElementById(id);
    if (!el) {
      el = document.createElement("style");
      el.id = id;
      (document.head || document.documentElement).appendChild(el);
    }
    if (el.textContent !== css) el.textContent = css;
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (e) {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.cssText = "position:fixed;opacity:0";
      document.body.appendChild(ta);
      ta.select();
      let ok = false;
      try {
        ok = document.execCommand("copy");
      } catch (_) {}
      ta.remove();
      return ok;
    }
  }

  const pad = (n) => String(n).padStart(2, "0");
  function stamp(sec) {
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    return (h ? h + ":" + pad(m) : String(m)) + ":" + pad(s);
  }
  function fmtDuration(sec) {
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    return h ? `${h}ω ${pad(m)}λ` : `${m}λ`;
  }

  const videoId = () => new URLSearchParams(location.search).get("v");
  const videoTitle = () =>
    document.title.replace(/^\(\d+\)\s*/, "").replace(/\s*-\s*YouTube$/, "");

  // The main player's video only (ignores hover previews on the feed).
  const mainVideo = () =>
    document.querySelector("#movie_player video.html5-main-video") ||
    document.querySelector("#movie_player video");

  /* ==================== toast ==================== */
  let toastTimer = null;
  function toast(msg) {
    injectStyle("ubuntu-yt-base", BASE_CSS);
    let el = document.getElementById("ub-toast");
    if (!el) {
      el = document.createElement("div");
      el.id = "ub-toast";
      el.setAttribute("role", "status");
      el.setAttribute("aria-live", "polite");
      document.body.appendChild(el);
    }
    el.textContent = msg;
    requestAnimationFrame(() => el.classList.add("ub-show"));
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove("ub-show"), 4500);
  }

  /* ==================== look ==================== */
  function paintLogo() {
    document
      .querySelectorAll("ytd-topbar-logo-renderer svg path, #logo-icon svg path")
      .forEach((p) => {
        const f = (p.getAttribute("fill") || "").toLowerCase();
        if (f === "#f00" || f === "#ff0000" || f === "red") {
          p.setAttribute("fill", ORANGE);
          p.style.fill = ORANGE;
        }
      });
  }

  const FAVICON =
    "data:image/svg+xml," +
    encodeURIComponent(
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
         <rect width="32" height="32" rx="8" fill="${ORANGE}"/>
         <path d="M13 10l9 6-9 6z" fill="#fff"/>
       </svg>`
    );

  function paintFavicon() {
    document.querySelectorAll('link[rel~="icon"]').forEach((l) => {
      if (l.href !== FAVICON) l.href = FAVICON;
    });
  }

  /* ==================== search filter ==================== */
  // YouTube's "sp" parameter encodes the filter (base64 protobuf).
  const SEARCH_SP = { video: "EgIQAQ==", long: "EgQQARgC" };

  function applySearchFilter() {
    const sp = SEARCH_SP[CONFIG.searchFilter];
    if (!sp || location.pathname !== "/results") return;
    const url = new URL(location.href);
    const q = url.searchParams.get("search_query") || "";
    if (url.searchParams.has("sp")) {
      sessionSet("sq", q); // a filter is set (ours or yours): remember this query
      return;
    }
    // Already filtered this exact search once -> you removed the filter on purpose.
    if (sessionGet("sq") === q) return;
    sessionSet("sq", q);
    url.searchParams.set("sp", sp);
    location.replace(url.toString());
  }

  /* ==================== watch page ==================== */
  let lastExpandedUrl = "";
  function expandDescription() {
    if (!location.pathname.startsWith("/watch")) return;
    if (lastExpandedUrl === location.href) return;
    const btn = document.querySelector("ytd-watch-metadata ytd-text-inline-expander #expand");
    if (btn && btn.offsetParent !== null) {
      btn.click();
      lastExpandedUrl = location.href;
    }
  }

  /* ==================== notes: timestamp ==================== */
  async function copyTimestamp() {
    const id = videoId();
    const v = mainVideo();
    if (!location.pathname.startsWith("/watch") || !id || !v) {
      return toast("Δεν υπάρχει βίντεο εδώ");
    }
    const t = Math.floor(v.currentTime);
    const line = `- [${stamp(t)}] ${videoTitle()} — https://youtu.be/${id}?t=${t}`;
    toast(
      (await copyText(line))
        ? `Αντιγράφηκε: [${stamp(t)}] ${videoTitle()}`
        : "Αποτυχία αντιγραφής, πάτα ξανά"
    );
  }

  /* ==================== transcript ==================== */
  const SEG = "ytd-transcript-segment-renderer, transcript-segment-view-model";
  const PANEL =
    'ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-searchable-transcript"]';
  const TRANSCRIPT_BTN = [
    "ytd-video-description-transcript-section-renderer button",
    "button[aria-label='Show transcript']",
    "button[aria-label*='ranscript' i]",
    "button[aria-label*='μεταγραφ' i]",
    "button[aria-label*='απομαγνητοφ' i]",
  ].join(", ");

  const panelOpen = () => {
    const p = document.querySelector(PANEL);
    return !!p && p.getAttribute("visibility") === "ENGAGEMENT_PANEL_VISIBILITY_EXPANDED";
  };

  async function openTranscript() {
    if (!location.pathname.startsWith("/watch")) {
      toast("Άνοιξε πρώτα ένα βίντεο");
      return false;
    }
    if (panelOpen()) {
      if (document.querySelector(SEG)) return true;
      // Panel open but still loading: just wait for it.
      if (await waitFor(() => document.querySelector(SEG), 5000)) return true;
    }

    const expand = document.querySelector("ytd-watch-metadata ytd-text-inline-expander #expand");
    if (expand && expand.offsetParent !== null) expand.click();

    const btn = await waitFor(() => document.querySelector(TRANSCRIPT_BTN));
    if (!btn) {
      toast("Δεν βρέθηκε transcript για αυτό το βίντεο");
      return false;
    }
    btn.click();

    const seg = await waitFor(() => document.querySelector(SEG), 5000);
    if (!seg) {
      toast("Το transcript δεν φόρτωσε");
      return false;
    }
    return true;
  }

  async function copyTranscript() {
    const wasReady = panelOpen() && !!document.querySelector(SEG);
    if (!wasReady) toast("Φόρτωση transcript…");
    if (!(await openTranscript())) return;

    const lines = [...document.querySelectorAll(SEG)]
      .map((seg) => {
        const ts = seg.querySelector(".segment-timestamp, .ytwTranscriptSegmentViewModelTimestamp");
        const tx = seg.querySelector(".segment-text, .yt-core-attributed-string") || seg;
        return `${(ts && ts.textContent.trim()) || ""} ${tx.textContent.trim()}`.trim();
      })
      .filter(Boolean);

    if (!lines.length) return toast("Το transcript είναι κενό");

    const header = `${videoTitle()}\nhttps://youtu.be/${videoId()}\n\n`;
    const ok = await copyText(header + lines.join("\n"));
    toast(
      ok
        ? `Transcript αντιγράφηκε (${lines.length} γραμμές)`
        : `Το transcript φόρτωσε. Πάτα ξανά Alt+Shift+${CONFIG.keys.copyTranscript.toUpperCase()} για αντιγραφή`
    );
  }

  /* ==================== watch-time counter ==================== */
  // Only counts; no reminders or limits.
  const today = () => new Date().toLocaleDateString("sv-SE"); // YYYY-MM-DD, local

  let currentDay = today();
  let stored = storedSeconds(); // today's total saved so far (all tabs)
  let pending = 0;              // seconds counted in this tab, not saved yet
  let flushCounter = 0;

  function storedSeconds() {
    const day = load("day", { d: today(), s: 0 });
    return day.d === today() ? day.s : 0;
  }

  // Adds this tab's seconds to the stored total (so several tabs add up).
  function flush() {
    if (!pending) return;
    const day = load("day", { d: today(), s: 0 });
    if (day.d !== today()) {
      day.d = today();
      day.s = 0;
    }
    day.s += pending;
    save("day", day);
    stored = day.s;
    pending = 0;
  }

  const todayTotal = () => stored + pending;

  function tick() {
    // New day: start from zero.
    if (today() !== currentDay) {
      flush();
      currentDay = today();
      stored = storedSeconds();
    }

    if (document.visibilityState !== "visible") return;

    const v = mainVideo();
    if (!v || v.paused || v.ended) return;

    pending += 1;
    if (++flushCounter >= 15) {
      flushCounter = 0;
      flush();
    }
  }

  function showToday() {
    flush();
    stored = storedSeconds();
    toast(`Σήμερα: ${fmtDuration(todayTotal())} βίντεο`);
  }

  /* ==================== shortcuts ==================== */
  const keyCode = (k) => "Key" + String(k || "").toUpperCase();

  function onKey(e) {
    if (!e.altKey || !e.shiftKey || e.ctrlKey || e.metaKey) return;
    const t = e.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;

    const k = CONFIG.keys;
    const code = e.code;
    if (code === keyCode(k.timestamp)) copyTimestamp();
    else if (code === keyCode(k.copyTranscript)) copyTranscript();
    else if (code === keyCode(k.transcript)) openTranscript();
    else if (code === keyCode(k.today)) showToday();
    else return;
    e.preventDefault();
    e.stopPropagation();
  }

  /* ==================== main loop ==================== */
  // Light work, safe to repeat often (YouTube re-renders parts of the page).
  function run() {
    try {
      injectStyle("ubuntu-yt-base", BASE_CSS);
      if (CONFIG.theme) injectStyle("ubuntu-yt-theme", THEME_CSS);
      if (CONFIG.orangeLogo) paintLogo();
      if (CONFIG.orangeFavicon) paintFavicon();
      if (CONFIG.autoExpandDescription) expandDescription();
    } catch (err) {
      console.warn("[Ubuntu YouTube]", err);
    }
  }

  // Once per page change (YouTube is a single-page app).
  function onNavigate() {
    try {
      applySearchFilter();
    } catch (err) {
      console.warn("[Ubuntu YouTube]", err);
    }
    run();
  }

  document.addEventListener("keydown", onKey, true);
  document.addEventListener("yt-navigate-finish", onNavigate);
  setInterval(tick, 1000);

  // Save watch time when the tab is hidden or closed.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") flush();
  });
  window.addEventListener("pagehide", flush);

  let timer = null;
  new MutationObserver(() => {
    if (timer) return;
    timer = setTimeout(() => {
      timer = null;
      run();
    }, 400);
  }).observe(document.documentElement, { childList: true, subtree: true });

  onNavigate();
})();
