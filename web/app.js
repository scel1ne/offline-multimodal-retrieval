// Celine Retrieval — web companion.
// Self-contained, offline-first browser app that mirrors the Flutter
// desktop experience: file ingestion, tokenization + TF-IDF scoring,
// per-document occurrence pager with previous/next navigation.

const $ = (id) => document.getElementById(id);
const STOP_WORDS = new Set([
  "the", "and", "for", "with", "this", "that", "from", "file", "into", "uses", "use",
]);

const state = {
  records: [],            // { id, name, kind, type, size, modified, text, tokens, vector }
  query: "",
  typeFilter: "all",
  sortMode: "relevance",
  expanded: null,         // index of expanded result
  matchIndex: {},         // recordId -> current match index
  pdfLib: null,           // lazily loaded
};

// ---------- Init ----------
init();

function init() {
  loadPreferences();
  bindEvents();
  renderLibrary();
  renderResults();
  preloadPdfJs();
}

function preloadPdfJs() {
  // Load PDF.js dynamically. If it fails (e.g. no network, CSP), PDFs
  // gracefully fall back to filename-only indexing.
  const script = document.createElement("script");
  script.type = "module";
  script.textContent = `
    import * as pdfjsLib from "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.0.379/build/pdf.min.mjs";
    pdfjsLib.GlobalWorkerOptions.workerSrc = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.0.379/build/pdf.worker.min.mjs";
    window.__pdfjs = pdfjsLib;
  `;
  script.onload = () => {
    state.pdfLib = window.__pdfjs;
  };
  script.onerror = () => {
    state.pdfLib = null;
  };
  document.head.appendChild(script);
}

// ---------- Preferences ----------
function loadPreferences() {
  try {
    const saved = JSON.parse(localStorage.getItem("celine.prefs") || "{}");
    if (saved.theme) document.body.dataset.theme = saved.theme;
    if (typeof saved.textScale === "number") {
      document.documentElement.style.setProperty("--text-scale", String(saved.textScale));
      $("text-scale").value = String(saved.textScale);
    }
  } catch (_) {}
}

function savePreferences() {
  const prefs = {
    theme: document.body.dataset.theme,
    textScale: Number($("text-scale").value) || 1,
  };
  try { localStorage.setItem("celine.prefs", JSON.stringify(prefs)); } catch (_) {}
}

// ---------- Events ----------
function bindEvents() {
  // Theme
  $("theme-toggle").addEventListener("click", cycleTheme);
  $("contrast-toggle").addEventListener("click", toggleContrast);
  $("text-scale").addEventListener("input", (e) => {
    document.documentElement.style.setProperty("--text-scale", e.target.value);
    savePreferences();
  });

  // File pick
  const fileInput = $("file-input");
  $("choose-btn").addEventListener("click", () => fileInput.click());
  $("dropzone").addEventListener("click", () => fileInput.click());
  fileInput.addEventListener("change", (e) => handleFiles(e.target.files));

  // Drag & drop
  ["dragenter", "dragover"].forEach((ev) =>
    $("dropzone").addEventListener(ev, (e) => {
      e.preventDefault();
      e.stopPropagation();
      $("dropzone").classList.add("dragging");
    })
  );
  ["dragleave", "drop"].forEach((ev) =>
    $("dropzone").addEventListener(ev, (e) => {
      e.preventDefault();
      e.stopPropagation();
      $("dropzone").classList.remove("dragging");
    })
  );
  $("dropzone").addEventListener("drop", (e) => {
    handleFiles(e.dataTransfer.files);
  });

  // Index actions
  $("export-btn").addEventListener("click", exportIndex);
  $("import-btn").addEventListener("click", () => $("import-input").click());
  $("import-input").addEventListener("change", (e) => {
    const file = e.target.files?.[0];
    if (file) importIndex(file);
    e.target.value = "";
  });
  $("clear-btn").addEventListener("click", clearIndex);

  // Search
  const queryInput = $("query");
  queryInput.addEventListener("input", (e) => {
    state.query = e.target.value.trim();
    $("clear-query").hidden = state.query.length === 0;
    state.expanded = null;
    renderResults();
  });
  queryInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      state.query = e.target.value.trim();
      renderResults();
    }
  });
  $("search-btn").addEventListener("click", () => {
    state.query = queryInput.value.trim();
    renderResults();
  });
  $("clear-query").addEventListener("click", () => {
    queryInput.value = "";
    state.query = "";
    $("clear-query").hidden = true;
    state.expanded = null;
    renderResults();
    queryInput.focus();
  });

  // Filters
  document.querySelectorAll('[data-type]').forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll('[data-type]').forEach((b) => {
        b.classList.toggle("active", b === btn);
        b.setAttribute("aria-selected", b === btn ? "true" : "false");
      });
      state.typeFilter = btn.dataset.type;
      state.expanded = null;
      renderResults();
    });
  });
  document.querySelectorAll('[data-sort]').forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll('[data-sort]').forEach((b) => {
        b.classList.toggle("active", b === btn);
        b.setAttribute("aria-selected", b === btn ? "true" : "false");
      });
      state.sortMode = btn.dataset.sort;
      state.expanded = null;
      renderResults();
    });
  });
}

function cycleTheme() {
  const cur = document.body.dataset.theme;
  if (cur === "light") document.body.dataset.theme = "dark";
  else if (cur === "dark") document.body.dataset.theme = "light";
  else if (cur === "contrast") document.body.dataset.theme = "dark-contrast";
  else if (cur === "dark-contrast") document.body.dataset.theme = "contrast";
  savePreferences();
}

function toggleContrast() {
  const cur = document.body.dataset.theme;
  if (cur === "light" || cur === "dark") {
    document.body.dataset.theme = cur === "dark" ? "dark-contrast" : "contrast";
  } else {
    document.body.dataset.theme = cur === "dark-contrast" ? "dark" : "light";
  }
  savePreferences();
}

// ---------- File ingestion ----------
async function handleFiles(fileList) {
  const files = Array.from(fileList || []);
  if (files.length === 0) return;
  showProgress(true);
  setStatus(`Indexing ${files.length} file${files.length === 1 ? "" : "s"}...`);

  const imported = [];
  for (const file of files) {
    try {
      const record = await buildRecord(file);
      imported.push(record);
    } catch (err) {
      console.error(`Failed to index ${file.name}:`, err);
    }
  }

  const byId = new Map(state.records.map((r) => [r.id, r]));
  for (const r of imported) byId.set(r.id, r);
  state.records = Array.from(byId.values());

  showProgress(false);
  setStatus(`${imported.length} file${imported.length === 1 ? "" : "s"} indexed. Library has ${state.records.length} file${state.records.length === 1 ? "" : "s"}.`);
  renderLibrary();
  renderResults();
}

async function buildRecord(file) {
  const lower = file.name.toLowerCase();
  const ext = lower.includes(".") ? lower.split(".").pop() : "";
  const isImage = ["png", "jpg", "jpeg", "gif", "bmp", "webp"].includes(ext);
  const isPdf = ext === "pdf";
  const isDocx = ext === "docx";

  let text = "";
  let kind = "document";
  if (isImage) {
    kind = "image";
    text = file.name;
  } else if (isPdf) {
    kind = "document";
    text = await extractPdfText(file);
  } else if (isDocx) {
    kind = "document";
    text = await extractDocxText(file);
  } else {
    kind = "text";
    text = await file.text();
  }

  if (!text || !text.trim()) text = `${file.name} ${ext} ${file.size} bytes`;
  const cleanText = text.replace(/\s+/g, " ").trim();
  const tokens = tokenize(`${file.name} ${ext} ${cleanText}`);

  return {
    id: `${file.name}:${file.size}:${file.lastModified}`,
    name: file.name,
    kind,
    type: ext || "unknown",
    size: file.size,
    modified: file.lastModified,
    text: cleanText,
    tokens,
    vector: vectorize(tokens),
  };
}

async function extractPdfText(file) {
  if (!state.pdfLib && !window.__pdfjs) {
    await new Promise((resolve) => {
      const t = setInterval(() => {
        if (state.pdfLib || window.__pdfjs) {
          state.pdfLib = state.pdfLib || window.__pdfjs;
          clearInterval(t);
          resolve();
        }
      }, 50);
      setTimeout(() => { clearInterval(t); resolve(); }, 4000);
    });
  }
  const pdfjs = state.pdfLib || window.__pdfjs;
  if (!pdfjs) return "";
  try {
    const buffer = await file.arrayBuffer();
    const pdf = await pdfjs.getDocument({ data: buffer }).promise;
    const pages = [];
    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i);
      const content = await page.getTextContent();
      pages.push(content.items.map((it) => it.str).join(" "));
    }
    return pages.join(" ");
  } catch (err) {
    console.warn("PDF parse failed", err);
    return "";
  }
}

async function extractDocxText(file) {
  try {
    const buffer = await file.arrayBuffer();
    // We use JSZip if available, else try to use a simple regex on the
    // document.xml inside the zip. To stay dependency-free we use a
    // lightweight inline zip reader.
    const text = await readDocxText(buffer);
    return text;
  } catch (err) {
    console.warn("DOCX parse failed", err);
    return "";
  }
}

// Minimal inline zip reader for .docx (deflate + central directory parse).
// DOCX is a zip archive whose primary text lives in word/document.xml.
async function readDocxText(arrayBuffer) {
  const view = new DataView(arrayBuffer);
  // End of central directory record
  const eocdSig = 0x06054b50;
  let eocdOffset = -1;
  for (let i = view.byteLength - 22; i >= 0 && i >= view.byteLength - 65557; i--) {
    if (view.getUint32(i, true) === eocdSig) { eocdOffset = i; break; }
  }
  if (eocdOffset < 0) return "";
  const cdSize = view.getUint32(eocdOffset + 12, true);
  const cdOffset = view.getUint32(eocdOffset + 16, true);

  // Walk central directory to find word/document.xml
  let p = cdOffset;
  let foundOffset = -1;
  let foundCompSize = 0;
  let foundUncompSize = 0;
  let foundMethod = 0;
  while (p < cdOffset + cdSize) {
    if (view.getUint32(p, true) !== 0x02014b50) break;
    const compSize = view.getUint32(p + 20, true);
    const uncompSize = view.getUint32(p + 24, true);
    const fnameLen = view.getUint16(p + 28, true);
    const extraLen = view.getUint16(p + 30, true);
    const commentLen = view.getUint16(p + 32, true);
    const method = view.getUint16(p + 10, true);
    const localHeaderOffset = view.getUint32(p + 42, true);
    const fname = new TextDecoder().decode(new Uint8Array(arrayBuffer, p + 46, fnameLen));
    if (fname === "word/document.xml") {
      foundOffset = localHeaderOffset;
      foundCompSize = compSize;
      foundUncompSize = uncompSize;
      foundMethod = method;
      break;
    }
    p += 46 + fnameLen + extraLen + commentLen;
  }
  if (foundOffset < 0) return "";

  // Local file header
  const localSig = view.getUint32(foundOffset, true);
  if (localSig !== 0x04034b50) return "";
  const fnameLen2 = view.getUint16(foundOffset + 26, true);
  const extraLen2 = view.getUint16(foundOffset + 28, true);
  const dataStart = foundOffset + 30 + fnameLen2 + extraLen2;

  const compressed = new Uint8Array(arrayBuffer, dataStart, foundCompSize);
  let raw;
  if (foundMethod === 0) {
    raw = compressed;
  } else if (foundMethod === 8) {
    // Streamed inflate via DecompressionStream.
    const stream = new Blob([compressed]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
    const buf = await new Response(stream).arrayBuffer();
    raw = new Uint8Array(buf);
  } else {
    return "";
  }
  const xml = new TextDecoder("utf-8", { fatal: false }).decode(raw);
  return xml.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

// ---------- Tokenization / scoring ----------
function tokenize(text) {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .split(/\s+/)
    .map(normalizeToken)
    .filter((t) => t.length > 1 && !STOP_WORDS.has(t));
}

function normalizeToken(token) {
  let v = token.toLowerCase();
  if (v.length > 5 && v.endsWith("ing")) v = v.slice(0, -3);
  else if (v.length > 4 && v.endsWith("ers")) v = v.slice(0, -1);
  else if (v.length > 4 && v.endsWith("er")) v = v.slice(0, -2);
  else if (v.length > 3 && v.endsWith("s")) v = v.slice(0, -1);
  return v;
}

function vectorize(tokens) {
  const v = new Map();
  for (const t of tokens) v.set(t, (v.get(t) || 0) + 1);
  return v;
}

function cosine(a, b) {
  let dot = 0, magA = 0, magB = 0;
  const keys = new Set([...a.keys(), ...b.keys()]);
  for (const k of keys) {
    const av = a.get(k) || 0;
    const bv = b.get(k) || 0;
    dot += av * bv;
    magA += av * av;
    magB += bv * bv;
  }
  if (magA === 0 || magB === 0) return 0;
  return dot / (Math.sqrt(magA) * Math.sqrt(magB));
}

function hasTokenMatch(tokens, query) {
  return tokens.some(
    (t) => t === query || t.startsWith(query) || query.startsWith(t) || t.includes(query)
  );
}

function scoreRecord(record, queryTokens, queryVector) {
  if (queryTokens.length === 0) return 1;
  const hits = queryTokens.filter((q) => hasTokenMatch(record.tokens, q)).length / queryTokens.length;
  const cos = cosine(record.vector, queryVector);
  const nameTokens = tokenize(record.name);
  const nameBoost = queryTokens.some((q) => hasTokenMatch(nameTokens, q)) ? 0.25 : 0;
  return Math.min(1, hits * 0.55 + cos * 0.35 + nameBoost);
}

// ---------- Search ----------
function searchRecords() {
  const qTokens = tokenize(state.query);
  const qVector = vectorize(qTokens);
  let rows = state.records
    .filter((r) => state.typeFilter === "all" || r.kind === state.typeFilter)
    .map((r) => ({ record: r, score: scoreRecord(r, qTokens, qVector) }));
  if (state.query) rows = rows.filter((r) => r.score > 0);
  if (state.sortMode === "name") {
    rows.sort((a, b) => a.record.name.localeCompare(b.record.name));
  } else if (state.sortMode === "date") {
    rows.sort((a, b) => b.record.modified - a.record.modified);
  } else {
    rows.sort((a, b) => b.score - a.score);
  }
  return rows;
}

function findAllMatches(text, query) {
  const clean = text.replace(/\s+/g, " ").trim();
  const qTokens = tokenize(query);
  if (qTokens.length === 0 || clean.length === 0) return [];
  const ranges = [];
  const lower = clean.toLowerCase();
  for (const t of qTokens) {
    if (!t) continue;
    const re = new RegExp(escapeRegExp(t), "gi");
    let m;
    while ((m = re.exec(lower)) !== null) {
      ranges.push({ start: m.index, end: m.index + m[0].length });
      if (m.index === re.lastIndex) re.lastIndex++;
    }
  }
  ranges.sort((a, b) => a.start - b.start);
  // merge overlapping
  const merged = [];
  for (const r of ranges) {
    if (merged.length === 0) merged.push({ ...r });
    else {
      const last = merged[merged.length - 1];
      if (r.start <= last.end) last.end = Math.max(last.end, r.end);
      else merged.push({ ...r });
    }
  }
  return merged;
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// ---------- Rendering ----------
function renderLibrary() {
  const list = $("library-list");
  list.innerHTML = "";
  const count = $("library-count");
  if (state.records.length === 0) {
    count.hidden = true;
  } else {
    count.hidden = false;
    count.textContent = `${state.records.length} file${state.records.length === 1 ? "" : "s"}`;
  }
  $("export-btn").disabled = state.records.length === 0;
  $("clear-btn").disabled = state.records.length === 0;

  for (const r of state.records) {
    const li = document.createElement("li");
    li.className = "record-item";
    li.innerHTML = `
      <div class="record-icon kind-${r.kind}">${iconSvgForKind(r.kind)}</div>
      <div class="record-meta">
        <div class="record-name"></div>
        <div class="record-sub"></div>
      </div>`;
    li.querySelector(".record-name").textContent = r.name;
    li.querySelector(".record-sub").textContent =
      `${r.kind} • ${formatBytes(r.size)} • ${r.tokens.length} terms`;
    list.appendChild(li);
  }
}

function renderResults() {
  const container = $("results");
  const rows = searchRecords();
  const summary = $("results-summary");
  if (state.query) {
    summary.textContent = `${rows.length} result${rows.length === 1 ? "" : "s"} for "${state.query}"`;
  } else {
    summary.textContent = `Showing all ${rows.length} indexed file${rows.length === 1 ? "" : "s"}`;
  }

  container.innerHTML = "";
  if (rows.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.innerHTML = `
      <svg viewBox="0 0 24 24" width="56" height="56" aria-hidden="true">
        <circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="1.6"/>
        <path d="m20 20-3.5-3.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
        <path d="m7 11 8 0M11 7l0 8" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" opacity="0.3"/>
      </svg>
      <p></p>`;
    empty.querySelector("p").textContent = state.records.length === 0
      ? "Add files to start searching."
      : "No matching results. Try a different query.";
    container.appendChild(empty);
    return;
  }

  rows.forEach((row, idx) => {
    container.appendChild(renderResultCard(row, idx));
  });
}

function renderResultCard(row, idx) {
  const record = row.record;
  const matches = findAllMatches(record.text, state.query);
  const totalMatches = matches.length;
  const isExpanded = state.expanded === idx;
  const currentIdx = state.matchIndex[record.id] || 0;
  const safeIdx = Math.max(0, Math.min(currentIdx, matches.length - 1));
  const currentMatch = matches[safeIdx];

  const card = document.createElement("article");
  card.className = `result${isExpanded ? " expanded" : ""}`;
  card.dataset.recordId = record.id;
  card.dataset.idx = String(idx);

  // Summary button
  const summary = document.createElement("button");
  summary.type = "button";
  summary.className = "result-summary";
  summary.setAttribute("aria-expanded", isExpanded ? "true" : "false");
  summary.innerHTML = `
    <div class="result-icon kind-${record.kind}">${iconSvgForKind(record.kind)}</div>
    <div class="result-main">
      <div class="result-title-row">
        <div class="result-name"></div>
        ${totalMatches > 0 ? `<div class="match-count">${totalMatches} match${totalMatches === 1 ? "" : "es"}</div>` : ""}
        <div class="score">${state.query ? `${Math.round(row.score * 100)}%` : "Indexed"}</div>
      </div>
      <div class="result-meta"></div>
    </div>
    <div class="expand-caret">
      <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="m6 9 6 6 6-6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
    </div>`;
  summary.querySelector(".result-name").textContent = record.name;
  summary.querySelector(".result-meta").textContent =
    `${record.kind} • ${(record.type || "").toUpperCase()} • ${formatBytes(record.size)} • ${new Date(record.modified).toLocaleString()}`;

  summary.addEventListener("click", () => {
    if (state.expanded === idx) {
      state.expanded = null;
    } else {
      state.expanded = idx;
      if (state.matchIndex[record.id] === undefined) state.matchIndex[record.id] = 0;
    }
    renderResults();
  });

  card.appendChild(summary);

  if (isExpanded) {
    const pager = renderPager(record, matches, currentMatch, safeIdx);
    card.appendChild(pager);
  }
  return card;
}

function renderPager(record, matches, currentMatch, safeIdx) {
  const wrap = document.createElement("div");
  wrap.className = "pager";

  const inner = document.createElement("div");
  inner.className = "pager-inner";

  const toolbar = document.createElement("div");
  toolbar.className = "pager-toolbar";
  toolbar.innerHTML = `
    <div class="pager-counter">${safeIdx + 1} / ${matches.length}</div>
    <div class="pager-position">Position ${currentMatch.start + 1} of ${record.text.length} characters</div>
    <button class="pager-btn" type="button" aria-label="Previous match" ${matches.length <= 1 ? "disabled" : ""}>
      <svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="m6 14 6-6 6 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
    </button>
    <button class="pager-btn primary" type="button" aria-label="Next match" ${matches.length <= 1 ? "disabled" : ""}>
      <svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="m6 10 6 6 6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
    </button>`;
  const [prevBtn, nextBtn] = toolbar.querySelectorAll("button");
  prevBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    state.matchIndex[record.id] = (safeIdx - 1 + matches.length) % matches.length;
    renderResults();
  });
  nextBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    state.matchIndex[record.id] = (safeIdx + 1) % matches.length;
    renderResults();
  });
  inner.appendChild(toolbar);

  if (matches.length > 0) {
    const progress = document.createElement("div");
    progress.className = "pager-progress";
    progress.style.setProperty("--pos", `${((currentMatch.start) / Math.max(1, record.text.length)) * 100}%`);
    inner.appendChild(progress);
  }

  const snippet = document.createElement("div");
  snippet.className = "snippet";
  if (matches.length > 0) {
    snippet.innerHTML = renderSnippet(record.text, matches, currentMatch);
  } else {
    snippet.textContent = record.text.length > 500 ? record.text.slice(0, 500) : record.text;
  }
  inner.appendChild(snippet);

  if (matches.length > 1) {
    const foot = document.createElement("div");
    foot.className = "pager-foot";
    foot.innerHTML = `
      <div class="track"><div style="width:${((safeIdx + 1) / matches.length) * 100}%"></div></div>
      <div class="pct">${Math.round(((safeIdx + 1) / matches.length) * 100)}%</div>`;
    inner.appendChild(foot);
  }

  wrap.appendChild(inner);
  return wrap;
}

function renderSnippet(clean, matches, current) {
  const radius = 130;
  const start = current.start < radius ? 0 : current.start - radius;
  const end = Math.min(clean.length, current.end + radius);
  const prefix = start > 0 ? `<span class="ellipsis">… </span>` : "";
  const suffix = end < clean.length ? `<span class="ellipsis"> …</span>` : "";
  const body = clean.slice(start, end);

  // Map absolute match ranges that intersect the snippet to snippet-relative
  // positions.
  const local = [];
  for (const m of matches) {
    const s = m.start - start;
    const e = m.end - start;
    if (e <= 0 || s >= body.length) continue;
    const cs = Math.max(0, s);
    const ce = Math.min(body.length, e);
    if (ce <= cs) continue;
    local.push({ s: cs, e: ce, current: m.start === current.start });
  }
  local.sort((a, b) => a.s - b.s);

  let html = prefix;
  let cursor = 0;
  for (const seg of local) {
    if (seg.s > cursor) html += escapeHtml(body.slice(cursor, seg.s));
    const cls = seg.current ? "match current" : "match";
    html += `<span class="${cls}">${escapeHtml(body.slice(seg.s, seg.e))}</span>`;
    cursor = seg.e;
  }
  if (cursor < body.length) html += escapeHtml(body.slice(cursor));
  html += suffix;
  return html;
}

function escapeHtml(s) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// ---------- Misc ----------
function setStatus(msg) { $("status-text").textContent = msg; }
function showProgress(show) { $("progress").hidden = !show; }

function formatBytes(bytes) {
  if (!bytes) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function iconSvgForKind(kind) {
  if (kind === "text") {
    return `<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M5 4h14v3H5V4Zm0 5h10v3H5V9Zm0 5h14v3H5v-3Zm0 5h7v3H5v-3Z" fill="currentColor"/></svg>`;
  }
  if (kind === "document") {
    return `<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M6 2h9l5 5v15a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1Zm8 1.5V8h4.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
  }
  if (kind === "image") {
    return `<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="9" cy="10" r="1.6" fill="currentColor"/><path d="m4 18 5-5 4 4 3-3 4 4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
  }
  return `<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M6 2h9l5 5v15a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1Z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
}

// ---------- Import / export ----------
function exportIndex() {
  const payload = {
    version: 1,
    exportedAt: Date.now(),
    records: state.records.map((r) => ({
      id: r.id, name: r.name, kind: r.kind, type: r.type, size: r.size,
      modified: r.modified, text: r.text, tokens: r.tokens,
      vector: Object.fromEntries(r.vector),
    })),
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "offline-retrieval-index.json";
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  setStatus("Index exported.");
}

async function importIndex(file) {
  try {
    const text = await file.text();
    const data = JSON.parse(text);
    const rows = (data.records || []).map((r) => ({
      ...r,
      vector: new Map(Object.entries(r.vector || {}).map(([k, v]) => [k, Number(v)])),
    }));
    state.records = rows;
    setStatus(`${rows.length} record${rows.length === 1 ? "" : "s"} imported.`);
    renderLibrary();
    renderResults();
  } catch (err) {
    setStatus(`Import failed: ${err.message}`);
  }
}

function clearIndex() {
  state.records = [];
  state.expanded = null;
  state.matchIndex = {};
  setStatus("Index cleared.");
  renderLibrary();
  renderResults();
}
