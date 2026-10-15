const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const { createHmac } = require("node:crypto");

const source = fs.readFileSync("google-apps-script-drive-bridge/Code.gs", "utf8");
const SECRET = "test-only-secret-with-at-least-32-bytes-long";
const FOLDER_ID = "school-folder-id-123456789";
const OTHER_FOLDER_ID = "other-folder-id-123456789";

function makeBridge() {
  const cache = new Map();
  const files = new Map();
  let lastError = "";
  let nextId = 1;
  const folder = {
    getId: () => FOLDER_ID,
    getName: () => "WBNS test folder",
    createFile(blob) {
      const id = "test-file-id-" + String(nextId++).padStart(10, "0");
      const file = {
        id,
        blob,
        trashed: false,
        getId: () => id,
        getName: () => blob.name,
        getMimeType: () => blob.mimeType,
        getSize: () => blob.bytes.length,
        getUrl: () => "https://drive.google.test/file/" + id,
        getParents() {
          let consumed = false;
          return {
            hasNext: () => !consumed,
            next: () => {
              consumed = true;
              return { getId: () => FOLDER_ID };
            },
          };
        },
        setTrashed(value) { this.trashed = value; },
      };
      files.set(id, file);
      return file;
    },
  };

  const sandbox = {
    console: { error(...args) { lastError = args.join(" "); } },
    Date,
    JSON,
    Math,
    Number,
    Object,
    String,
    RegExp,
    PropertiesService: {
      getScriptProperties: () => ({ getProperty: (key) => ({
        WBNS_BRIDGE_SECRET: SECRET,
        WBNS_DRIVE_FOLDER_ID: FOLDER_ID,
      })[key] ?? null }),
    },
    CacheService: {
      getScriptCache: () => ({
        get: (key) => cache.has(key) ? cache.get(key) : null,
        put: (key, value) => cache.set(key, value),
      }),
    },
    LockService: {
      getScriptLock: () => ({ waitLock() {}, releaseLock() {} }),
    },
    Utilities: {
      computeHmacSha256Signature: (value, secret) =>
        Array.from(createHmac("sha256", secret).update(value, "utf8").digest()),
      base64EncodeWebSafe: (bytes) =>
        Buffer.from(bytes).toString("base64").replace(/\+/g, "-").replace(/\//g, "_"),
      base64Decode: (value) => Array.from(Buffer.from(value, "base64")),
      newBlob: (bytes, mimeType, name) => ({ bytes, mimeType, name }),
    },
    DriveApp: {
      getFolderById(id) {
        if (id !== FOLDER_ID) throw new Error("folder not found");
        return folder;
      },
      getFileById(id) {
        const file = files.get(id);
        if (!file) throw new Error("file not found");
        return file;
      },
    },
    ContentService: {
      MimeType: { JSON: "application/json" },
      createTextOutput(text) {
        return {
          text,
          mimeType: null,
          setMimeType(type) { this.mimeType = type; return this; },
        };
      },
    },
  };
  vm.runInNewContext(source, sandbox, { filename: "Code.gs" });

  function signed(payload) {
    const signature = createHmac("sha256", SECRET)
      .update(JSON.stringify(payload), "utf8")
      .digest("base64url");
    return JSON.stringify({ ...payload, signature });
  }
  function call(payloadOrRaw) {
    const raw = typeof payloadOrRaw === "string" ? payloadOrRaw : signed(payloadOrRaw);
    const output = sandbox.doPost({ postData: { contents: raw } });
    assert.equal(output.mimeType, "application/json");
    const result = JSON.parse(output.text);
    if (result.code === "BRIDGE_OPERATION_FAILED") throw new Error("Bridge exception: " + lastError);
    return result;
  }
  return { call, files, folder, cache };
}

function request(action, extra = {}, requestId = "a3c6a29a-5ed0-4bd4-96f1-21d1ac4b5a66") {
  return { action, timestamp: Math.floor(Date.now() / 1000), requestId, ...extra };
}

test("health accepts a valid HMAC and returns configured folder name", () => {
  const bridge = makeBridge();
  assert.deepEqual(bridge.call(request("health")), { ok: true, folder_name: "WBNS test folder" });
});

test("rejects an invalid HMAC before executing an operation", () => {
  const bridge = makeBridge();
  const payload = request("upload", {
    filename: "test.txt", mimeType: "text/plain",
    contentBase64: Buffer.from("safe test").toString("base64"),
  });
  const result = bridge.call(JSON.stringify({ ...payload, signature: "invalid" }));
  assert.deepEqual(result, { ok: false, code: "SIGNATURE_INVALID" });
  assert.equal(bridge.files.size, 0);
});

test("rejects a replayed requestId", () => {
  const bridge = makeBridge();
  const payload = request("health");
  assert.equal(bridge.call(payload).ok, true);
  assert.deepEqual(bridge.call(payload), { ok: false, code: "REQUEST_REPLAYED" });
});

test("rejects an expired timestamp", () => {
  const bridge = makeBridge();
  const payload = request("health");
  payload.timestamp -= 301;
  assert.deepEqual(bridge.call(payload), { ok: false, code: "REQUEST_EXPIRED" });
});

test("uploads a small file into the configured folder", () => {
  const bridge = makeBridge();
  const result = bridge.call(request("upload", {
    filename: "minutes.txt",
    mimeType: "text/plain",
    contentBase64: Buffer.from("school document").toString("base64"),
  }));
  assert.equal(result.ok, true);
  assert.equal(result.name, "minutes.txt");
  assert.equal(result.size_bytes, Buffer.byteLength("school document"));
  assert.equal(bridge.files.size, 1);
});

test("rejects malformed filenames", () => {
  const bridge = makeBridge();
  const result = bridge.call(request("upload", {
    filename: "../minutes.txt",
    mimeType: "text/plain",
    contentBase64: Buffer.from("x").toString("base64"),
  }));
  assert.deepEqual(result, { ok: false, code: "INVALID_FILENAME" });
  assert.equal(bridge.files.size, 0);
});

test("trashes a file inside the configured folder", () => {
  const bridge = makeBridge();
  const upload = bridge.call(request("upload", {
    filename: "minutes.txt",
    mimeType: "text/plain",
    contentBase64: Buffer.from("x").toString("base64"),
  }));
  const result = bridge.call(request("delete", { fileId: upload.file_id },
    "b4c6a29a-5ed0-4bd4-96f1-21d1ac4b5a67"));
  assert.deepEqual(result, { ok: true, file_id: upload.file_id, trashed: true });
  assert.equal(bridge.files.get(upload.file_id).trashed, true);
});

test("refuses to trash a file outside the configured folder", () => {
  const bridge = makeBridge();
  const otherFile = {
    getParents() {
      let consumed = false;
      return {
        hasNext: () => !consumed,
        next: () => { consumed = true; return { getId: () => OTHER_FOLDER_ID }; },
      };
    },
    setTrashed(value) { this.trashed = value; },
  };
  bridge.files.set("outside-file-id-12345", otherFile);
  const result = bridge.call(request("delete", { fileId: "outside-file-id-12345" }));
  assert.deepEqual(result, { ok: false, code: "FILE_OUTSIDE_CONFIGURED_FOLDER" });
  assert.notEqual(otherFile.trashed, true);
});
test("upload cleanup moves the Drive object to Trash before deleting its metadata", () => {
  const uploadSource = fs.readFileSync("supabase/functions/drive-upload/index.ts", "utf8");
  const cleanupStart = uploadSource.indexOf("async function cleanupCreatedResources()");
  const cleanupEnd = uploadSource.indexOf("\n\n  try {\n    const bytes", cleanupStart);
  assert.notEqual(cleanupStart, -1, "cleanup function must exist");
  assert.notEqual(cleanupEnd, -1, "cleanup function boundary must exist");
  const cleanup = uploadSource.slice(cleanupStart, cleanupEnd);
  const trashIndex = cleanup.indexOf('await signedBridgeRequest("delete", { fileId: driveFileId })');
  const metadataDeleteIndex = cleanup.indexOf('.from("google_drive_files").delete()');
  assert.notEqual(trashIndex, -1, "cleanup must request Drive trash");
  assert.notEqual(metadataDeleteIndex, -1, "cleanup must delete metadata only after Drive cleanup");
  assert.ok(trashIndex < metadataDeleteIndex, "Drive trash must succeed before metadata is removed");
  assert.match(cleanup.slice(trashIndex, metadataDeleteIndex), /catch\s*\(error\)[\s\S]*?return;/,
    "if Drive trash fails, metadata must be retained for reconciliation");
});
