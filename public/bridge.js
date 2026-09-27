// Injected into every tool before its own code runs. A tool lives in a
// sandboxed frame with no network, so this is its only way to reach Amber:
// every call becomes a postMessage to the parent page, which checks it came
// from this frame and forwards it with the member's link attached.
(function () {
  var pending = {};
  var listeners = [];
  var counter = 0;

  function call(op, args) {
    var id = "c" + ++counter;
    var message = Object.assign({ amber: 1, id: id, op: op }, args || {});
    return new Promise(function (resolve, reject) {
      pending[id] = { resolve: resolve, reject: reject };
      parent.postMessage(message, "*");
    });
  }

  window.addEventListener("message", function (event) {
    if (event.source !== parent) return;
    var data = event.data || {};
    if (data.amber !== 1) return;
    if (data.type === "change") {
      listeners.forEach(function (listener) {
        try {
          listener(data.detail);
        } catch (error) {
          console.error(error);
        }
      });
      return;
    }
    var waiter = pending[data.id];
    if (!waiter) return;
    delete pending[data.id];
    if (data.error) waiter.reject(new Error(data.error));
    else waiter.resolve(data.result);
  });

  window.amber = {
    me: function () {
      return call("me");
    },
    circle: function () {
      return call("circle");
    },
    people: function () {
      return call("people");
    },
    list: function (collection) {
      return call("list", { collection: collection });
    },
    add: function (collection, data) {
      return call("add", { collection: collection, data: data });
    },
    update: function (collection, id, data) {
      return call("update", { collection: collection, id: id, data: data });
    },
    remove: function (collection, id) {
      return call("remove", { collection: collection, id: id });
    },
    reachOut: function (memberId, message) {
      return call("reach", { memberId: memberId, message: message || "" });
    },
    onChange: function (listener) {
      listeners.push(listener);
    },
  };
})();
