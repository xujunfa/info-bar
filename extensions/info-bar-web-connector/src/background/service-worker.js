"use strict";

importScripts("../shared/contracts.js");

var contracts = self.__INFO_BAR_CONTRACTS__;
if (!contracts) {
  throw new Error("Missing shared contracts in service worker.");
}

var STORAGE_SNAPSHOTS_KEY = "connector_snapshots";
var STORAGE_DEDUPE_KEY = "connector_dedupe_index";
var STORAGE_RUNTIME_KEY = "connector_runtime_state";
var STORAGE_REMOTE_CACHE_KEY = "connector_remote_snapshots";
var STORAGE_SUPABASE_CONFIG_KEY = "supabase_config";

var LEGACY_PROVIDER_STORAGE_KEYS = Object.freeze({
  factory: Object.freeze({
    snapshots: "factory_usage_snapshots",
    dedupe: "factory_usage_dedupe_index"
  })
});

var EXTENSION_CONFIG_EXAMPLE_FILE = "config.example.json";
var EXTENSION_CONFIG_LOCAL_FILE = "config.local.json";

var DEFAULT_SUPABASE_CONFIG = Object.freeze({
  enabled: true,
  projectUrl: "",
  table: "connector_events",
  // Publishable/anon key is intentionally client-side; keep RLS policies strict.
  apiKey: "",
  readBackLimit: 20
});

var MAX_SNAPSHOTS = 100;
var MAX_DEDUPE_KEYS = 500;
var MAX_REMOTE_CACHE_ROWS = 50;
var DEDUPE_BUCKET_MS = 10 * 60 * 1000;

var SINKS_CONFIG = Object.freeze({
  console: true,
  localStorage: true,
  supabase: true
});

function stableStringify(value) {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return "[" + value.map(stableStringify).join(",") + "]";
  }

  var keys = Object.keys(value).sort();
  var segments = [];
  for (var index = 0; index < keys.length; index += 1) {
    var key = keys[index];
    segments.push(JSON.stringify(key) + ":" + stableStringify(value[key]));
  }
  return "{" + segments.join(",") + "}";
}

function hashString(input) {
  var text = typeof input === "string" ? input : "";
  var hash = 2166136261;
  for (var index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash +=
      (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  return (hash >>> 0).toString(16);
}

function redactSensitive(value) {
  if (Array.isArray(value)) {
    return value.map(redactSensitive);
  }

  if (!contracts.isPlainObject(value)) {
    return value;
  }

  var cloned = {};
  var keys = Object.keys(value);
  for (var index = 0; index < keys.length; index += 1) {
    var key = keys[index];
    if (/token|authorization|cookie|secret|password|apikey|api_key/i.test(key)) {
      cloned[key] = "[REDACTED]";
      continue;
    }
    cloned[key] = redactSensitive(value[key]);
  }

  return cloned;
}

function maskApiKey(apiKey) {
  if (typeof apiKey !== "string" || apiKey.length < 10) {
    return "[EMPTY]";
  }
  return apiKey.slice(0, 6) + "..." + apiKey.slice(-4);
}

function isPlaceholderSupabaseProjectUrl(value) {
  if (typeof value !== "string" || value.trim() === "") {
    return false;
  }
  return value.toLowerCase().indexOf("your-project-ref.supabase.co") >= 0;
}

function isPlaceholderSupabaseApiKey(value) {
  if (typeof value !== "string" || value.trim() === "") {
    return false;
  }
  var normalized = value.trim().toLowerCase();
  return (
    normalized === "sb_publishable_replace_me" ||
    normalized === "sb_anon_replace_me" ||
    normalized.indexOf("replace_me") >= 0 ||
    normalized.indexOf("replace-me") >= 0
  );
}

function isBridgeMessage(message) {
  if (!contracts.isPlainObject(message)) {
    return false;
  }
  if (message.type !== contracts.BACKGROUND_MESSAGE_TYPE) {
    return false;
  }
  if (message.source !== contracts.CONNECTOR_NAME) {
    return false;
  }
  if (message.schemaVersion !== contracts.SCHEMA_VERSION) {
    return false;
  }
  if (!contracts.getProviderConfig(message.provider || "")) {
    return false;
  }
  return contracts.validatePageMessage(message.payload);
}

function normalizeSnapshot(pageEnvelope, sender) {
  var provider = pageEnvelope.provider;
  var capturedAt =
    typeof pageEnvelope.capturedAt === "string"
      ? pageEnvelope.capturedAt
      : new Date().toISOString();

  var snapshot = {
    connector: contracts.CONNECTOR_NAME,
    provider: provider,
    event: pageEnvelope.event,
    capturedAt: capturedAt,
    pageUrl: contracts.sanitizeUrl(pageEnvelope.pageUrl || (sender && sender.url) || ""),
    request: {
      url: contracts.sanitizeUrl(pageEnvelope.request && pageEnvelope.request.url),
      method: contracts.normalizeMethod(pageEnvelope.request && pageEnvelope.request.method),
      status:
        typeof (pageEnvelope.request && pageEnvelope.request.status) === "number"
          ? pageEnvelope.request.status
          : null,
      ruleId:
        pageEnvelope.request && typeof pageEnvelope.request.ruleId === "string"
          ? pageEnvelope.request.ruleId
          : ""
    },
    payload: pageEnvelope.payload,
    meta: {
      traceId:
        pageEnvelope.meta && typeof pageEnvelope.meta.traceId === "string"
          ? pageEnvelope.meta.traceId
          : contracts.createTraceId(),
      hook:
        pageEnvelope.meta && pageEnvelope.meta.hook === "xhr" ? "xhr" : "fetch",
      version: 1,
      receivedAt: new Date().toISOString()
    }
  };

  var capturedTime = new Date(snapshot.capturedAt).getTime();
  var bucket = Number.isNaN(capturedTime)
    ? Math.floor(Date.now() / DEDUPE_BUCKET_MS)
    : Math.floor(capturedTime / DEDUPE_BUCKET_MS);
  var payloadHash = hashString(stableStringify(snapshot.payload));
  snapshot.meta.dedupeKey =
    snapshot.provider +
    "|" +
    snapshot.event +
    "|" +
    snapshot.request.url +
    "|" +
    bucket +
    "|" +
    payloadHash;

  return snapshot;
}

function normalizeSupabaseConfig(configLike) {
  var raw = contracts.isPlainObject(configLike) ? configLike : {};
  var rawProjectUrl =
    (typeof raw.projectUrl === "string" && raw.projectUrl) ||
    (typeof raw.projectURL === "string" && raw.projectURL) ||
    (typeof raw.url === "string" && raw.url) ||
    "";
  var projectUrl =
    typeof rawProjectUrl === "string" && rawProjectUrl.trim() !== ""
      ? rawProjectUrl.trim().replace(/\/+$/, "")
      : "";
  var table =
    typeof raw.table === "string" && raw.table.trim() !== "" ? raw.table.trim() : "connector_events";
  var rawApiKey =
    (typeof raw.apiKey === "string" && raw.apiKey) ||
    (typeof raw.anonKey === "string" && raw.anonKey) ||
    (typeof raw.publishableKey === "string" && raw.publishableKey) ||
    "";
  var apiKey = typeof rawApiKey === "string" ? rawApiKey.trim() : "";
  var readBackLimit = Number(
    typeof raw.readBackLimit !== "undefined" ? raw.readBackLimit : raw.read_back_limit
  );

  return {
    enabled: raw.enabled !== false,
    projectUrl: isPlaceholderSupabaseProjectUrl(projectUrl) ? "" : projectUrl,
    table: table,
    apiKey: isPlaceholderSupabaseApiKey(apiKey) ? "" : apiKey,
    readBackLimit:
      Number.isFinite(readBackLimit) && readBackLimit > 0 ? Math.floor(readBackLimit) : 20
  };
}

async function loadConfigFileByName(fileName) {
  try {
    var response = await fetch(chrome.runtime.getURL(fileName), {
      method: "GET",
      cache: "no-store"
    });
    if (!response.ok) {
      return {};
    }
    var payload = await response.json();
    if (contracts.isPlainObject(payload) && contracts.isPlainObject(payload.supabase)) {
      return payload.supabase;
    }
    if (contracts.isPlainObject(payload)) {
      return payload;
    }
  } catch (_error) {
    // Missing or malformed local config should not break extension startup.
  }
  return {};
}

async function loadSupabaseConfigFromExtensionFiles() {
  var exampleConfig = await loadConfigFileByName(EXTENSION_CONFIG_EXAMPLE_FILE);
  var localConfig = await loadConfigFileByName(EXTENSION_CONFIG_LOCAL_FILE);
  return Object.assign({}, exampleConfig, localConfig);
}

function mapSnapshotToSupabaseRow(snapshot) {
  return {
    connector: snapshot.connector,
    provider: snapshot.provider,
    event: snapshot.event,
    dedupe_key: snapshot.meta.dedupeKey,
    captured_at: snapshot.capturedAt,
    received_at: snapshot.meta.receivedAt,
    page_url: snapshot.pageUrl,
    request_url: snapshot.request.url,
    request_method: snapshot.request.method,
    request_status: snapshot.request.status,
    request_rule_id: snapshot.request.ruleId,
    payload: snapshot.payload,
    metadata: snapshot.meta,
    source: "chrome_extension"
  };
}

function mapSupabaseRowToSnapshot(row) {
  if (!contracts.isPlainObject(row)) {
    return null;
  }
  return {
    connector: typeof row.connector === "string" ? row.connector : contracts.CONNECTOR_NAME,
    provider: typeof row.provider === "string" ? row.provider : "",
    event: typeof row.event === "string" ? row.event : "",
    capturedAt: typeof row.captured_at === "string" ? row.captured_at : "",
    pageUrl: typeof row.page_url === "string" ? row.page_url : "",
    request: {
      url: typeof row.request_url === "string" ? row.request_url : "",
      method: typeof row.request_method === "string" ? row.request_method : "GET",
      status: typeof row.request_status === "number" ? row.request_status : null,
      ruleId: typeof row.request_rule_id === "string" ? row.request_rule_id : ""
    },
    payload: row.payload,
    meta: contracts.isPlainObject(row.metadata) ? row.metadata : {}
  };
}

async function getStorage(keys) {
  return chrome.storage.local.get(keys);
}

async function setStorage(value) {
  return chrome.storage.local.set(value);
}

async function readSupabaseConfig() {
  var stored = await getStorage([STORAGE_SUPABASE_CONFIG_KEY]);
  var userConfig = contracts.isPlainObject(stored[STORAGE_SUPABASE_CONFIG_KEY])
    ? stored[STORAGE_SUPABASE_CONFIG_KEY]
    : {};
  var fileConfig = await loadSupabaseConfigFromExtensionFiles();
  var merged = Object.assign({}, DEFAULT_SUPABASE_CONFIG, fileConfig, userConfig);
  return normalizeSupabaseConfig(merged);
}

async function ensureSupabaseConfigSeeded() {
  var stored = await getStorage([STORAGE_SUPABASE_CONFIG_KEY]);
  var existing = contracts.isPlainObject(stored[STORAGE_SUPABASE_CONFIG_KEY])
    ? stored[STORAGE_SUPABASE_CONFIG_KEY]
    : {};
  var fileConfig = await loadSupabaseConfigFromExtensionFiles();
  var merged = normalizeSupabaseConfig(
    Object.assign({}, DEFAULT_SUPABASE_CONFIG, fileConfig, existing)
  );
  await setStorage({ [STORAGE_SUPABASE_CONFIG_KEY]: merged });
  console.info(
    "[info-bar] supabase config initialized:",
    merged.projectUrl || "[MISSING_SUPABASE_URL]",
    "key=" + maskApiKey(merged.apiKey)
  );
}

async function requestSupabase(config, restPath, init) {
  var url = config.projectUrl + "/rest/v1/" + restPath;
  var headers = new Headers((init && init.headers) || {});
  headers.set("apikey", config.apiKey);
  headers.set("Authorization", "Bearer " + config.apiKey);
  if ((init && init.method && init.method !== "GET") || (init && init.body)) {
    if (!headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json");
    }
  }

  var response = await fetch(url, {
    method: (init && init.method) || "GET",
    headers: headers,
    body: init && init.body ? init.body : undefined
  });

  if (!response.ok) {
    var errorText = "";
    try {
      errorText = await response.text();
    } catch (_readError) {
      errorText = "";
    }
    throw new Error(
      "supabase_http_" +
        response.status +
        ":" +
        (errorText ? errorText.slice(0, 220) : "no_response_body")
    );
  }

  if (response.status === 204) {
    return null;
  }

  var contentType = response.headers.get("content-type") || "";
  if (contentType.indexOf("application/json") >= 0) {
    return response.json();
  }

  return response.text();
}

async function readDedupeIndex() {
  var stored = await getStorage([STORAGE_DEDUPE_KEY]);
  return Array.isArray(stored[STORAGE_DEDUPE_KEY]) ? stored[STORAGE_DEDUPE_KEY] : [];
}

async function writeDedupeIndex(dedupeKeys) {
  var keysToWrite = dedupeKeys.slice(-MAX_DEDUPE_KEYS);
  await setStorage({ [STORAGE_DEDUPE_KEY]: keysToWrite });
}

async function markAndCheckDuplicate(snapshot) {
  var dedupeKey = snapshot.meta.dedupeKey;
  var dedupeKeys = await readDedupeIndex();

  if (dedupeKeys.indexOf(dedupeKey) >= 0) {
    return true;
  }

  dedupeKeys.push(dedupeKey);
  await writeDedupeIndex(dedupeKeys);

  var legacy = LEGACY_PROVIDER_STORAGE_KEYS[snapshot.provider];
  if (legacy) {
    await setStorage({ [legacy.dedupe]: dedupeKeys.slice(-MAX_DEDUPE_KEYS) });
  }

  return false;
}

async function appendSnapshotToKey(storageKey, snapshot, maxCount) {
  var stored = await getStorage([storageKey]);
  var snapshots = Array.isArray(stored[storageKey]) ? stored[storageKey] : [];
  snapshots.unshift(snapshot);
  if (snapshots.length > maxCount) {
    snapshots.length = maxCount;
  }
  await setStorage({ [storageKey]: snapshots });
}

async function localStorageSink(snapshot) {
  await appendSnapshotToKey(STORAGE_SNAPSHOTS_KEY, snapshot, MAX_SNAPSHOTS);

  var legacy = LEGACY_PROVIDER_STORAGE_KEYS[snapshot.provider];
  if (legacy) {
    await appendSnapshotToKey(legacy.snapshots, snapshot, MAX_SNAPSHOTS);
  }
}

async function consoleSink(snapshot) {
  console.info("[info-bar] normalized snapshot:", redactSensitive(snapshot));
}

async function supabaseSink(snapshot) {
  if (!SINKS_CONFIG.supabase) {
    return;
  }

  var config = await readSupabaseConfig();
  if (!config.enabled || !config.projectUrl || !config.apiKey) {
    return;
  }

  var row = mapSnapshotToSupabaseRow(snapshot);
  await requestSupabase(config, config.table + "?on_conflict=dedupe_key", {
    method: "POST",
    headers: {
      Prefer: "resolution=merge-duplicates,return=minimal"
    },
    body: JSON.stringify(row)
  });
}

async function syncRemoteSnapshotsForProvider(provider, reason) {
  var config = await readSupabaseConfig();
  if (!config.enabled || !config.projectUrl || !config.apiKey) {
    return { synced: false, reason: "supabase_disabled_or_missing_config" };
  }

  var limit = Math.min(Math.max(config.readBackLimit, 1), MAX_REMOTE_CACHE_ROWS);
  var params = new URLSearchParams();
  params.set(
    "select",
    [
      "connector",
      "provider",
      "event",
      "dedupe_key",
      "captured_at",
      "received_at",
      "page_url",
      "request_url",
      "request_method",
      "request_status",
      "request_rule_id",
      "payload",
      "metadata"
    ].join(",")
  );
  params.set("connector", "eq." + contracts.CONNECTOR_NAME);
  params.set("provider", "eq." + provider);
  params.set("order", "captured_at.desc");
  params.set("limit", String(limit));

  var rows = await requestSupabase(config, config.table + "?" + params.toString(), {
    method: "GET"
  });
  var parsedRows = Array.isArray(rows) ? rows.map(mapSupabaseRowToSnapshot).filter(Boolean) : [];

  var stored = await getStorage([STORAGE_REMOTE_CACHE_KEY]);
  var remoteCache = contracts.isPlainObject(stored[STORAGE_REMOTE_CACHE_KEY])
    ? stored[STORAGE_REMOTE_CACHE_KEY]
    : {};
  remoteCache[provider] = {
    syncedAt: new Date().toISOString(),
    reason: reason || "unknown",
    total: parsedRows.length,
    snapshots: parsedRows
  };
  await setStorage({ [STORAGE_REMOTE_CACHE_KEY]: remoteCache });

  return { synced: true, count: parsedRows.length };
}

async function syncRemoteSnapshotsForAllProviders(reason) {
  var providers = contracts.getProviderIds();
  for (var index = 0; index < providers.length; index += 1) {
    var provider = providers[index];
    try {
      var result = await syncRemoteSnapshotsForProvider(provider, reason);
      if (result && result.synced) {
        console.info("[info-bar] supabase read sync:", provider, "rows=", result.count);
      }
    } catch (error) {
      console.warn(
        "[info-bar] supabase read sync failed:",
        provider,
        error && error.message ? error.message : error
      );
    }
  }
}

function getEnabledSinks() {
  var sinks = [];
  if (SINKS_CONFIG.console) {
    sinks.push(consoleSink);
  }
  if (SINKS_CONFIG.localStorage) {
    sinks.push(localStorageSink);
  }
  sinks.push(supabaseSink);
  return sinks;
}

async function runSinks(snapshot) {
  var sinks = getEnabledSinks();
  for (var index = 0; index < sinks.length; index += 1) {
    try {
      await sinks[index](snapshot);
    } catch (error) {
      console.warn("[info-bar] sink failed:", error && error.message ? error.message : error);
    }
  }
}

async function handleCapturedEnvelope(pageEnvelope, sender) {
  var normalized = normalizeSnapshot(pageEnvelope, sender);
  var isDuplicate = await markAndCheckDuplicate(normalized);
  if (isDuplicate) {
    console.info("[info-bar] duplicate snapshot skipped:", normalized.meta.dedupeKey);
    return { accepted: false, deduped: true };
  }

  await runSinks(normalized);
  return { accepted: true, deduped: false, dedupeKey: normalized.meta.dedupeKey };
}

async function ensureRefreshAlarms() {
  var providers = contracts.getProviderIds();
  for (var index = 0; index < providers.length; index += 1) {
    var provider = providers[index];
    var config = contracts.getProviderConfig(provider);
    if (!config || !contracts.isPlainObject(config.refresh)) {
      continue;
    }

    var period = Number(config.refresh.periodMinutes || 0);
    if (period <= 0) {
      continue;
    }

    var alarmName = contracts.getRefreshAlarmName(provider);
    var currentAlarm = await chrome.alarms.get(alarmName);
    if (currentAlarm) {
      continue;
    }

    chrome.alarms.create(alarmName, {
      delayInMinutes: Number(config.refresh.delayInMinutes || 1),
      periodInMinutes: period
    });
    console.info("[info-bar] refresh alarm scheduled:", provider, "every", period, "minutes.");
  }
}

async function readRuntimeState() {
  var stored = await getStorage([STORAGE_RUNTIME_KEY]);
  return contracts.isPlainObject(stored[STORAGE_RUNTIME_KEY]) ? stored[STORAGE_RUNTIME_KEY] : {};
}

async function writeRuntimeState(runtimeState) {
  await setStorage({ [STORAGE_RUNTIME_KEY]: runtimeState });
}

async function shouldThrottleRefresh(provider, nowMs) {
  var runtimeState = await readRuntimeState();
  var byProvider = contracts.isPlainObject(runtimeState.refreshByProvider)
    ? runtimeState.refreshByProvider
    : {};
  var providerState = contracts.isPlainObject(byProvider[provider]) ? byProvider[provider] : {};
  var config = contracts.getProviderConfig(provider);
  var minIntervalMinutes =
    config && config.refresh ? Number(config.refresh.minIntervalMinutes || 20) : 20;
  var minIntervalMs = minIntervalMinutes * 60 * 1000;
  var lastTriggeredAt =
    typeof providerState.lastTriggeredAt === "number" ? providerState.lastTriggeredAt : 0;

  if (nowMs - lastTriggeredAt < minIntervalMs) {
    return true;
  }

  byProvider[provider] = {
    lastTriggeredAt: nowMs,
    lastTriggeredAtISO: new Date(nowMs).toISOString()
  };
  runtimeState.refreshByProvider = byProvider;
  await writeRuntimeState(runtimeState);
  return false;
}

async function handleRefreshAlarm(provider) {
  var config = contracts.getProviderConfig(provider);
  if (!config) {
    return;
  }

  var now = Date.now();
  if (await shouldThrottleRefresh(provider, now)) {
    console.info("[info-bar] refresh alarm skipped by throttle:", provider);
    return;
  }

  var tabPatterns = Array.isArray(config.tabUrlPatterns) ? config.tabUrlPatterns : [];
  if (tabPatterns.length === 0) {
    return;
  }

  var tabs = await chrome.tabs.query({ url: tabPatterns });
  if (!Array.isArray(tabs) || tabs.length === 0) {
    console.info("[info-bar] refresh alarm fired but no tabs are open:", provider);
    return;
  }

  var triggered = 0;
  for (var index = 0; index < tabs.length; index += 1) {
    var tab = tabs[index];
    if (!tab || typeof tab.id !== "number") {
      continue;
    }

    try {
      await chrome.tabs.sendMessage(tab.id, {
        type: contracts.REFRESH_MESSAGE_TYPE,
        source: contracts.CONNECTOR_NAME,
        schemaVersion: contracts.SCHEMA_VERSION,
        provider: provider,
        reason: "alarm"
      });
      triggered += 1;
    } catch (_error) {
      // Content script may not be ready.
    }
  }

  console.info("[info-bar] refresh alarm dispatched:", provider, "tabs=", triggered);

  // Lightweight server-side read sync to keep remote cache in local storage.
  void syncRemoteSnapshotsForProvider(provider, "alarm");
}

chrome.runtime.onInstalled.addListener(function onInstalled(details) {
  console.info("[info-bar] service worker started:", details && details.reason);
  void ensureSupabaseConfigSeeded();
  void ensureRefreshAlarms();
  void syncRemoteSnapshotsForAllProviders("onInstalled");
});

chrome.runtime.onStartup.addListener(function onStartup() {
  console.info("[info-bar] browser startup detected.");
  void ensureSupabaseConfigSeeded();
  void ensureRefreshAlarms();
  void syncRemoteSnapshotsForAllProviders("onStartup");
});

chrome.runtime.onMessage.addListener(function onMessage(message, sender, sendResponse) {
  if (!isBridgeMessage(message)) {
    return;
  }

  handleCapturedEnvelope(message.payload, sender)
    .then(function onSuccess(result) {
      sendResponse({ ok: true, result: result });
    })
    .catch(function onFailure(error) {
      var reason = error && error.message ? error.message : String(error);
      console.error("[info-bar] failed to process snapshot:", reason);
      sendResponse({ ok: false, error: reason });
    });

  return true;
});

chrome.alarms.onAlarm.addListener(function onAlarm(alarm) {
  var provider = contracts.parseRefreshProviderFromAlarmName(alarm && alarm.name);
  if (!provider) {
    return;
  }
  console.info("[info-bar] refresh alarm fired:", provider);
  void handleRefreshAlarm(provider);
});

void ensureSupabaseConfigSeeded();
void ensureRefreshAlarms();
void syncRemoteSnapshotsForAllProviders("worker_init");
console.info("[info-bar] service worker initialized.");
