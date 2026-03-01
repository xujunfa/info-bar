(function bridgeProviderCapture(globalScope) {
  "use strict";

  var contracts = globalScope.__INFO_BAR_CONTRACTS__;
  if (!contracts) {
    console.error("[info-bar] contracts missing in content script.");
    return;
  }

  if (globalScope.__INFO_BAR_BRIDGE_READY__) {
    return;
  }
  globalScope.__INFO_BAR_BRIDGE_READY__ = true;

  var PAGE_INJECTED_ATTR = "data-info-bar-page-injected";
  var lastRefreshAtByProvider = {};
  var MIN_REFRESH_INTERVAL_MS = 10 * 60 * 1000;
  var activeProvider = contracts.getProviderByHost(
    globalScope.location && globalScope.location.hostname
  );

  function injectScriptFile(path) {
    var root = document.head || document.documentElement;
    if (!root) {
      return;
    }

    var script = document.createElement("script");
    script.src = chrome.runtime.getURL(path);
    script.async = false;
    script.dataset.infoBar = "true";
    script.onload = function onLoad() {
      script.remove();
    };
    script.onerror = function onError() {
      console.error("[info-bar] failed to inject script:", path);
      script.remove();
    };
    root.appendChild(script);
  }

  function injectMainWorldHooks() {
    var root = document.documentElement;
    if (!root || root.hasAttribute(PAGE_INJECTED_ATTR)) {
      return;
    }
    if (!activeProvider) {
      return;
    }

    root.setAttribute(PAGE_INJECTED_ATTR, "1");
    injectScriptFile("src/shared/contracts.js");
    injectScriptFile("src/page/factory-hook.js");
  }

  function forwardMessageToBackground(pageMessage) {
    var runtimeMessage = {
      type: contracts.BACKGROUND_MESSAGE_TYPE,
      source: contracts.CONNECTOR_NAME,
      schemaVersion: contracts.SCHEMA_VERSION,
      provider: pageMessage.provider,
      payload: pageMessage
    };

    chrome.runtime.sendMessage(runtimeMessage, function onResponse() {
      if (chrome.runtime.lastError) {
        console.warn("[info-bar] sendMessage failed:", chrome.runtime.lastError.message);
      }
    });
  }

  function onWindowMessage(event) {
    if (event.source !== globalScope) {
      return;
    }
    if (event.origin !== globalScope.location.origin) {
      return;
    }
    if (!contracts.validatePageMessage(event.data)) {
      return;
    }
    if (activeProvider && event.data.provider !== activeProvider) {
      return;
    }
    forwardMessageToBackground(event.data);
  }

  function onRuntimeMessage(message, _sender, sendResponse) {
    if (!contracts.isPlainObject(message)) {
      return;
    }
    if (message.type !== contracts.REFRESH_MESSAGE_TYPE) {
      return;
    }
    if (message.source !== contracts.CONNECTOR_NAME) {
      return;
    }
    if (!contracts.getProviderConfig(message.provider || "")) {
      sendResponse({ ok: false, skipped: true, reason: "invalid_provider" });
      return;
    }
    if (!activeProvider || activeProvider !== message.provider) {
      sendResponse({ ok: false, skipped: true, reason: "provider_mismatch" });
      return;
    }

    var provider = message.provider;
    var now = Date.now();
    var lastRefreshAt = lastRefreshAtByProvider[provider] || 0;
    if (now - lastRefreshAt < MIN_REFRESH_INTERVAL_MS) {
      sendResponse({ ok: false, skipped: true, reason: "throttled_in_content" });
      return;
    }

    lastRefreshAtByProvider[provider] = now;
    console.info("[info-bar] refresh requested by service worker:", provider);
    sendResponse({ ok: true });
    globalScope.location.reload();
  }

  injectMainWorldHooks();
  globalScope.addEventListener("message", onWindowMessage, false);
  chrome.runtime.onMessage.addListener(onRuntimeMessage);
  console.info(
    "[info-bar] content bridge ready.",
    activeProvider ? "provider=" + activeProvider : "provider=none"
  );
})(window);
