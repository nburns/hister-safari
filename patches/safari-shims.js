// Safari compatibility shim, prepended to background.js at build time.
//
// Upstream background.js uses OffscreenCanvas + createImageBitmap inside the
// service worker to derive greyscale toolbar icons at runtime. Safari's MV3
// service worker does not reliably support OffscreenCanvas, so we intercept
// chrome.action.setIcon and swap runtime-generated ImageData for prebuilt
// grey/normal PNGs shipped in assets/icons/. The prebuilt icons are copied
// into the bundle by scripts/build.sh.
//
// Detection: an imageData-based setIcon call is the runtime-generated path.
// A path-based call is the caller's own choice and passes through untouched.

(function installIconShim() {
  if (typeof chrome === 'undefined' || !chrome.action || !chrome.action.setIcon) return;

  const normalIconPaths = {
    16: 'assets/icons/icon-16.png',
    32: 'assets/icons/icon-32.png',
  };
  const greyIconPaths = {
    16: 'assets/icons/icon-grey-16.png',
    32: 'assets/icons/icon-grey-32.png',
  };

  // A single pixel from the 16x16 grey icon is enough to distinguish grey vs
  // normal ImageData in buildIcons(): the grey path zeroes the chroma
  // channels so R === G === B for every pixel.
  function looksGrey(imageData) {
    const d = imageData.data;
    for (let i = 0; i < d.length; i += 4) {
      if (d[i] !== d[i + 1] || d[i + 1] !== d[i + 2]) return false;
    }
    return true;
  }

  const originalSetIcon = chrome.action.setIcon.bind(chrome.action);

  chrome.action.setIcon = function shimmedSetIcon(details, callback) {
    if (details && details.imageData) {
      const sample = details.imageData[16] || Object.values(details.imageData)[0];
      const path = sample && looksGrey(sample) ? greyIconPaths : normalIconPaths;
      const forwarded = { path, tabId: details.tabId };
      return originalSetIcon(forwarded, callback);
    }
    return originalSetIcon(details, callback);
  };
})();
