(function providerCaptureHook(globalScope) {
  "use strict";

  var contracts = globalScope.__INFO_BAR_CONTRACTS__;
  if (!contracts) {
    console.warn("[info-bar] contracts missing, skip page hook.");
    return;
  }

  if (globalScope.__INFO_BAR_PAGE_HOOK_INSTALLED__) {
    return;
  }
  globalScope.__INFO_BAR_PAGE_HOOK_INSTALLED__ = true;

  function safeParseJson(text) {
    if (typeof text !== "string" || text.trim() === "") {
      return null;
    }
    try {
      return JSON.parse(text);
    } catch (_error) {
      return null;
    }
  }

  function normalizePayload(payload) {
    if (Array.isArray(payload) || contracts.isPlainObject(payload)) {
      return payload;
    }
    if (payload == null) {
      return {};
    }
    return { value: payload };
  }

  function resolveRule(requestUrl, method) {
    return contracts.findCaptureRule(requestUrl, method);
  }

  function postCapturedSnapshot(input) {
    var matched = resolveRule(input.requestUrl, input.method);
    if (!matched) {
      return;
    }

    var message = {
      type: contracts.PAGE_MESSAGE_TYPE,
      source: contracts.CONNECTOR_NAME,
      schemaVersion: contracts.SCHEMA_VERSION,
      provider: matched.provider,
      event: matched.rule.event,
      capturedAt: new Date().toISOString(),
      pageUrl: contracts.sanitizeUrl(globalScope.location && globalScope.location.href),
      request: {
        url: contracts.sanitizeUrl(input.requestUrl),
        method: contracts.normalizeMethod(input.method),
        status: typeof input.status === "number" ? input.status : null,
        ruleId: matched.rule.ruleId
      },
      payload: normalizePayload(input.payload),
      meta: {
        traceId: contracts.createTraceId(),
        hook: input.hook === "xhr" ? "xhr" : "fetch",
        version: 1
      }
    };

    globalScope.postMessage(message, globalScope.location.origin);
  }

  function hookFetch() {
    if (typeof globalScope.fetch !== "function") {
      return;
    }

    var originalFetch = globalScope.fetch;
    globalScope.fetch = async function infoBarFetch(input, init) {
      var response = await originalFetch.apply(this, arguments);

      try {
        var requestUrl = "";
        if (typeof input === "string") {
          requestUrl = input;
        } else if (input && typeof input.url === "string") {
          requestUrl = input.url;
        }

        var requestMethod =
          (init && typeof init.method === "string" && init.method) ||
          (input && typeof input.method === "string" && input.method) ||
          "GET";
        var matched = resolveRule(requestUrl, requestMethod);
        if (!matched) {
          return response;
        }

        var clonedResponse = response.clone();
        var payload = await clonedResponse.json();
        postCapturedSnapshot({
          hook: "fetch",
          requestUrl: requestUrl,
          method: requestMethod,
          status: response.status,
          payload: payload
        });
      } catch (_error) {
        // Never break page network logic for capture failures.
      }

      return response;
    };
  }

  function hookXmlHttpRequest() {
    if (!globalScope.XMLHttpRequest || !globalScope.XMLHttpRequest.prototype) {
      return;
    }

    var originalOpen = globalScope.XMLHttpRequest.prototype.open;
    var originalSend = globalScope.XMLHttpRequest.prototype.send;

    globalScope.XMLHttpRequest.prototype.open = function infoBarOpen(method, url) {
      this.__infoBarRequestContext = {
        method: typeof method === "string" ? method : "GET",
        url: typeof url === "string" ? url : url != null ? String(url) : ""
      };
      return originalOpen.apply(this, arguments);
    };

    globalScope.XMLHttpRequest.prototype.send = function infoBarSend() {
      this.addEventListener("load", function onLoad() {
        try {
          var context = this.__infoBarRequestContext || {};
          var matched = resolveRule(context.url, context.method);
          if (!matched) {
            return;
          }

          var payload = safeParseJson(this.responseText);
          if (!payload) {
            return;
          }

          postCapturedSnapshot({
            hook: "xhr",
            requestUrl: context.url,
            method: context.method,
            status: this.status,
            payload: payload
          });
        } catch (_error) {
          // Never break page network logic for capture failures.
        }
      });

      return originalSend.apply(this, arguments);
    };
  }

  hookFetch();
  hookXmlHttpRequest();
  console.info("[info-bar] page hook ready with provider rules.");
})(window);
