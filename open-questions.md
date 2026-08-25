# Open questions

## PDF indexing UX

Upstream's PDF indexing (`indexPDFTab` in `vendor/hister/webui/ext/src/background/background.ts`) works in Safari — verified against multiple real-world PDFs (extracted text of 400 B, 3 KB, 7 KB, 12 KB stored in the local hister index).

**How it works**: on `chrome.tabs.onUpdated` when a `.pdf` URL completes loading, the background does `fetch(tab.url, {credentials: 'include'})`, base64-encodes the bytes, and POSTs to hister's `/api/add_pdf`. Server extracts text.

**Known warts (all pre-existing upstream, not Safari-specific):**

- **Popup "Reindex" button on PDFs shows "Reindex failed."** Uses the content-script path (`content.ts:extract()`) which rejects non-HTML content types. Even when the background silently auto-indexed the PDF on load, the manual button lies. Small popup-side patch upstream would fix it — detect `unsupported_content_type` response, show "PDFs are indexed automatically on load" instead of the generic error.
- **Double fetch.** Safari fetches the PDF for viewing; background fetches again for indexing. Cost is bandwidth on large PDFs. Was investigated (declarativeNetRequest redirect + `<embed>` blob URL viewer) and abandoned — Safari's dnr doesn't reliably intercept `main_frame` navigations, webNavigation doesn't fire without explicit per-site permission, and the complexity wasn't worth avoiding the double fetch. See git history circa "strip viewer-hook" for details.
- **URL-extension detection only** (`pathname.endsWith('.pdf')`). Misses PDFs served with `Content-Disposition: attachment` from HTML-looking URLs. Fine for common cases (arxiv, research papers, docs).
- **One-time URLs may fail** (S3 pre-signed, magic-link downloads) — the background's second fetch gets a 403/expired-token. Same bug as any re-fetch approach.
