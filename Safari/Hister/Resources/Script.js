function show(enabled, useSettingsInsteadOfPreferences) {
    if (useSettingsInsteadOfPreferences) {
        document.getElementsByClassName('state-on')[0].innerText = "The extension is on. Click the Hister toolbar icon to confirm the server URL, then browse as usual — visited pages are indexed automatically, same as the Chrome and Firefox extensions.";
        document.getElementsByClassName('state-off')[0].innerText = "The extension is off. Turn it on in the Extensions section of Safari Settings to start indexing pages you visit.";
        document.getElementsByClassName('state-unknown')[0].innerText = "Enable the extension in Safari Settings, then click the toolbar icon to set your Hister server URL (default http://127.0.0.1:4433/).";
        document.getElementsByClassName('open-preferences')[0].innerText = "Quit and Open Safari Settings…";
    }

    if (typeof enabled === "boolean") {
        document.body.classList.toggle(`state-on`, enabled);
        document.body.classList.toggle(`state-off`, !enabled);
    } else {
        document.body.classList.remove(`state-on`);
        document.body.classList.remove(`state-off`);
    }
}

function openPreferences() {
    webkit.messageHandlers.controller.postMessage("open-preferences");
}

document.querySelector("button.open-preferences").addEventListener("click", openPreferences);
