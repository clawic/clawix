import Foundation

/// JS bundle that the macOS app injects via `WKUserScript` at document
/// start, before any code from the app's index.html runs. Mounts a
/// `window.clawix` namespace that talks back to the native side via
/// `window.webkit.messageHandlers.clawix.postMessage`.
///
/// Kept as a Swift string (not a Resources file) so the SDK ships
/// inside the binary, can't be tampered with on disk, and doesn't add
/// a Bundle-lookup dance to AppSurfaceView. Update by editing here.
let ClawixAppsSDKJS = #"""
(function () {
  if (window.clawix) return;

  var pending = Object.create(null);
  var listeners = Object.create(null);
  var seq = 0;
  var bridge = (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.clawix) || null;

  function send(op, payload) {
    if (!bridge) {
      return Promise.reject(new Error('clawix bridge unavailable: this surface is not a Clawix App'));
    }
    var requestId = 'r-' + (++seq);
    return new Promise(function (resolve, reject) {
      pending[requestId] = { resolve: resolve, reject: reject };
      try {
        bridge.postMessage({ requestId: requestId, op: op, payload: payload || {} });
      } catch (err) {
        delete pending[requestId];
        reject(err);
      }
    });
  }

  // Resolved by AppBridgeMessageHandler.swift via evaluateJavaScript.
  window.__clawixResolve = function (requestId, result) {
    var entry = pending[requestId];
    if (!entry) return;
    delete pending[requestId];
    entry.resolve(result);
  };
  window.__clawixReject = function (requestId, message) {
    var entry = pending[requestId];
    if (!entry) return;
    delete pending[requestId];
    entry.reject(new Error(message || 'clawix call failed'));
  };
  window.__clawixDispatch = function (eventName, data) {
    var bucket = listeners[eventName];
    if (!bucket) return;
    bucket.slice().forEach(function (cb) {
      try { cb(data); } catch (e) { /* swallow listener errors */ }
    });
  };

  function on(name, cb) {
    if (!listeners[name]) listeners[name] = [];
    listeners[name].push(cb);
  }
  function off(name, cb) {
    var bucket = listeners[name];
    if (!bucket) return;
    var idx = bucket.indexOf(cb);
    if (idx !== -1) bucket.splice(idx, 1);
  }

  // The native side fills window.__clawixContext synchronously via
  // userContentController.addUserScript(forMainFrame:atDocumentStart),
  // injected from AppSurfaceView right before this SDK script.
  var ctx = window.__clawixContext || { app: {}, user: {} };

  window.clawix = {
    app: ctx.app,
    user: ctx.user,
    storage: {
      get: function (key) { return send('storage.get', { key: String(key) }); },
      set: function (key, value) { return send('storage.set', { key: String(key), value: value }); },
      delete: function (key) { return send('storage.delete', { key: String(key) }); },
      keys: function () { return send('storage.keys'); }
    },
    agent: {
      sendMessage: function (text) { return send('agent.sendMessage', { text: String(text || '') }); },
      callTool: function (opts) {
        var tool = (opts && opts.tool) ? String(opts.tool) : '';
        var args = (opts && opts.args) ? opts.args : {};
        return send('agent.callTool', { tool: tool, args: args });
      }
    },
    ui: {
      setTitle: function (title) { return send('ui.setTitle', { title: String(title || '') }); },
      setBadge: function (text) {
        return send('ui.setBadge', { text: text == null ? null : String(text) });
      },
      openExternal: function (url) { return send('ui.openExternal', { url: String(url || '') }); }
    },
    events: { on: on, off: off }
  };

  // Best-effort focus/blur events the SDK emits on its own without
  // needing a round trip to native (handlers can still subscribe via
  // events.on('focus' | 'blur')).
  window.addEventListener('focus', function () {
    window.__clawixDispatch('focus', null);
  });
  window.addEventListener('blur', function () {
    window.__clawixDispatch('blur', null);
  });
})();
"""#
