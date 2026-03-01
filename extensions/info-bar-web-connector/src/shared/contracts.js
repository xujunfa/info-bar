(function initInfoBarContracts(globalScope) {
  "use strict";

  if (globalScope.__INFO_BAR_CONTRACTS__) {
    return;
  }

  var CONNECTOR_NAME = "info-bar-web-connector";
  var SCHEMA_VERSION = 1;
  var FALLBACK_BASE_URL = "https://app.factory.ai";
  var ALARM_NAME_PREFIX = "provider_refresh_";

  var PAGE_MESSAGE_TYPE = "INFO_BAR_PAGE_CAPTURED";
  var BACKGROUND_MESSAGE_TYPE = "INFO_BAR_CAPTURED";
  var REFRESH_MESSAGE_TYPE = "INFO_BAR_REFRESH_REQUEST";

  var PROVIDER_CONFIGS = Object.freeze({
    factory: Object.freeze({
      provider: "factory",
      pageHosts: Object.freeze(["app.factory.ai"]),
      tabUrlPatterns: Object.freeze(["https://app.factory.ai/*"]),
      refresh: Object.freeze({
        periodMinutes: 30,
        minIntervalMinutes: 20,
        delayInMinutes: 1
      }),
      captureRules: Object.freeze([
        Object.freeze({
          ruleId: "factory_usage_subscription",
          event: "usage_snapshot",
          requestHost: "api.factory.ai",
          requestPath: "/api/organization/subscription/usage",
          methods: Object.freeze(["POST", "GET"])
        })
      ])
    })
  });

  function toUrl(urlLike) {
    if (typeof urlLike !== "string" || urlLike.trim() === "") {
      return null;
    }

    var base = FALLBACK_BASE_URL;
    if (globalScope.location && typeof globalScope.location.href === "string") {
      base = globalScope.location.href;
    }

    try {
      return new URL(urlLike, base);
    } catch (_error) {
      return null;
    }
  }

  function sanitizeUrl(urlLike) {
    var url = toUrl(urlLike);
    if (!url) {
      return "";
    }
    return url.origin + url.pathname;
  }

  function normalizeMethod(method) {
    if (typeof method !== "string" || method.trim() === "") {
      return "GET";
    }
    return method.trim().toUpperCase();
  }

  function isPlainObject(value) {
    return Object.prototype.toString.call(value) === "[object Object]";
  }

  function createTraceId() {
    var random = Math.random().toString(16).slice(2, 10);
    var now = Date.now().toString(16);
    return "trace_" + now + "_" + random;
  }

  function getProviderIds() {
    return Object.keys(PROVIDER_CONFIGS);
  }

  function getProviderConfig(provider) {
    if (typeof provider !== "string") {
      return null;
    }
    return PROVIDER_CONFIGS[provider] || null;
  }

  function getProviderByHost(hostname) {
    if (typeof hostname !== "string") {
      return null;
    }

    var providerIds = getProviderIds();
    for (var index = 0; index < providerIds.length; index += 1) {
      var provider = providerIds[index];
      var config = PROVIDER_CONFIGS[provider];
      var hosts = Array.isArray(config.pageHosts) ? config.pageHosts : [];
      if (hosts.indexOf(hostname) >= 0) {
        return provider;
      }
    }
    return null;
  }

  function getProviderByPageUrl(pageUrlLike) {
    var url = toUrl(pageUrlLike);
    if (!url) {
      return null;
    }
    return getProviderByHost(url.hostname);
  }

  function findCaptureRule(requestUrlLike, method) {
    var url = toUrl(requestUrlLike);
    if (!url) {
      return null;
    }

    var normalizedMethod = normalizeMethod(method);
    var providerIds = getProviderIds();

    for (var index = 0; index < providerIds.length; index += 1) {
      var provider = providerIds[index];
      var config = PROVIDER_CONFIGS[provider];
      var rules = Array.isArray(config.captureRules) ? config.captureRules : [];

      for (var ruleIndex = 0; ruleIndex < rules.length; ruleIndex += 1) {
        var rule = rules[ruleIndex];
        if (url.hostname !== rule.requestHost) {
          continue;
        }
        if (url.pathname !== rule.requestPath) {
          continue;
        }

        var methods = Array.isArray(rule.methods) ? rule.methods : ["GET"];
        if (methods.indexOf(normalizedMethod) < 0) {
          continue;
        }

        return {
          provider: provider,
          rule: rule
        };
      }
    }

    return null;
  }

  function getRefreshAlarmName(provider) {
    return ALARM_NAME_PREFIX + provider;
  }

  function parseRefreshProviderFromAlarmName(alarmName) {
    if (typeof alarmName !== "string") {
      return null;
    }
    if (alarmName.indexOf(ALARM_NAME_PREFIX) !== 0) {
      return null;
    }
    return alarmName.slice(ALARM_NAME_PREFIX.length);
  }

  function validatePageMessage(message) {
    if (!isPlainObject(message)) {
      return false;
    }
    if (message.type !== PAGE_MESSAGE_TYPE) {
      return false;
    }
    if (message.source !== CONNECTOR_NAME) {
      return false;
    }
    if (message.schemaVersion !== SCHEMA_VERSION) {
      return false;
    }
    if (!getProviderConfig(message.provider)) {
      return false;
    }
    if (typeof message.event !== "string" || message.event.trim() === "") {
      return false;
    }
    if (!isPlainObject(message.request) || typeof message.request.url !== "string") {
      return false;
    }
    if (typeof message.request.ruleId !== "string" || message.request.ruleId.trim() === "") {
      return false;
    }
    if (!isPlainObject(message.meta)) {
      return false;
    }
    return true;
  }

  globalScope.__INFO_BAR_CONTRACTS__ = Object.freeze({
    CONNECTOR_NAME: CONNECTOR_NAME,
    SCHEMA_VERSION: SCHEMA_VERSION,
    PAGE_MESSAGE_TYPE: PAGE_MESSAGE_TYPE,
    BACKGROUND_MESSAGE_TYPE: BACKGROUND_MESSAGE_TYPE,
    REFRESH_MESSAGE_TYPE: REFRESH_MESSAGE_TYPE,
    PROVIDER_CONFIGS: PROVIDER_CONFIGS,
    sanitizeUrl: sanitizeUrl,
    normalizeMethod: normalizeMethod,
    isPlainObject: isPlainObject,
    createTraceId: createTraceId,
    getProviderIds: getProviderIds,
    getProviderConfig: getProviderConfig,
    getProviderByHost: getProviderByHost,
    getProviderByPageUrl: getProviderByPageUrl,
    findCaptureRule: findCaptureRule,
    getRefreshAlarmName: getRefreshAlarmName,
    parseRefreshProviderFromAlarmName: parseRefreshProviderFromAlarmName,
    validatePageMessage: validatePageMessage
  });
})(typeof globalThis !== "undefined" ? globalThis : this);
