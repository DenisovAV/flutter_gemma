import { m as R, d as h, s as E, r as b } from "./tensorflow.js";
import { l as A, a as w, T as S } from "./litert.js";
import { S as M } from "./sentencepiece.js";
const k = "task: search result | query: ", T = 2, p = 1, z = 0;
let c = 256;
const m = 768;
let i = null, s = null, u = !1, f = !1;
async function F(o) {
  try {
    const r = await fetch(o);
    if (!r.ok)
      throw new Error(`Failed to fetch tokenizer: ${r.status} ${r.statusText}`);
    const n = await r.arrayBuffer(), t = new M();
    if (typeof t.loadFromBuffer == "function")
      await t.loadFromBuffer(new Uint8Array(n));
    else {
      const e = new Uint8Array(n);
      let a = "";
      for (let d = 0; d < e.length; d++)
        a += String.fromCharCode(e[d]);
      const l = btoa(a);
      await t.loadFromB64StringModel(l);
    }
    return s = {
      encode: (e, a = !1) => {
        const l = t.encodeIds(e);
        return a ? [T, ...l, p] : l;
      },
      decode: (e) => t.decodeIds(e),
      processor: t
    }, s;
  } catch (r) {
    throw new Error("Failed to load SentencePiece tokenizer: " + r.message);
  }
}
async function W(o, r = "/node_modules/@litertjs/core/wasm/") {
  try {
    console.log(`[LiteRT] Loading model from: ${o}`), console.log(`[LiteRT] WASM loaded flag: ${f}`), await E("webgl"), await b(), f ? console.log("[LiteRT] WASM runtime already loaded, reusing") : (console.log(`[LiteRT] Loading WASM runtime from: ${r}`), await A(r), f = !0, console.log("[LiteRT] WASM runtime loaded successfully"));
    try {
      console.log("[LiteRT] Attempting to compile model with WebGPU..."), i = await w(o, {
        accelerator: "webgpu"
      }), console.log("[LiteRT] Model compiled with WebGPU successfully");
    } catch (n) {
      console.warn("[LiteRT] WebGPU not available, falling back to WASM:", n.message), i = await w(o, {
        accelerator: "wasm"
      }), console.log("[LiteRT] Model compiled with WASM successfully");
    }
    try {
      const n = i.getInputDetails();
      if (n && n.length > 0) {
        const t = n[0].shape;
        if (t && t.length >= 2) {
          const e = t[1];
          e !== c && (c = e, console.log(`[LiteRT] Auto-detected maxSequenceLength: ${c}`));
        }
      }
    } catch (n) {
      console.warn("[LiteRT] Failed to auto-detect sequence length, using default:", n);
    }
    return i;
  } catch (n) {
    throw new Error("Failed to load LiteRT model: " + n.message);
  }
}
function _(o) {
  const r = s.encode(k, !1), n = "▁" + o, t = s.encode(n, !1);
  let e = [...r, ...t];
  if (e.unshift(T), e.push(p), e.length > c)
    e = e.slice(0, c);
  else if (e.length < c) {
    const a = c - e.length;
    e = [...e, ...new Array(a).fill(z)];
  }
  return e;
}
async function y(o) {
  if (!i || !s)
    throw new Error("Model or tokenizer not initialized. Call loadLiteRtEmbeddings first.");
  const r = _(o), n = new Int32Array(r), t = new S(n, [1, c]);
  let e = t;
  i.accelerator === "webgpu" && (e = await t.moveTo("webgpu"));
  try {
    const l = i.run(e)[0];
    let d = l;
    l.accelerator === "webgpu" && (d = await l.moveTo("wasm"));
    const L = d.toTypedArray(), g = Array.from(L);
    return g.length !== m && console.warn(`Unexpected embedding dimension: ${g.length}, expected ${m}`), e !== t && !e.deleted && e.delete(), t.deleted || t.delete(), d !== l && !d.deleted && d.delete(), l.deleted || l.delete(), g;
  } catch (a) {
    try {
      e !== t && !e.deleted && e.delete(), t.deleted || t.delete();
    } catch {
    }
    throw a;
  }
}
window.loadLiteRtEmbeddings = async function(o, r, n) {
  try {
    if (u) {
      console.log("[LiteRT] Cleaning up previous model before reinitialization (hot restart detected)");
      try {
        await window.cleanupLiteRtEmbeddings();
      } catch (e) {
        console.warn("[LiteRT] Non-fatal cleanup error (will reinitialize anyway):", e), i = null, s = null, f = !1, u = !1;
      }
    }
    const t = n ?? "/node_modules/@litertjs/core/wasm/";
    await F(r), await W(o, t), u = !0;
  } catch (t) {
    throw u = !1, new Error("Failed to initialize LiteRT embeddings: " + t.message);
  }
};
window.generateEmbedding = async function(o) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (typeof o != "string" || o.trim().length === 0)
    throw new Error("Text must be a non-empty string");
  const r = await y(o);
  return new Float32Array(r);
};
window.generateEmbeddings = async function(o) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (!Array.isArray(o))
    throw new Error("texts must be an array");
  const r = [];
  for (const n of o) {
    if (typeof n != "string" || n.trim().length === 0)
      throw new Error("All texts must be non-empty strings");
    const t = await y(n);
    r.push(new Float32Array(t));
  }
  return r;
};
window.getLiteRtEmbeddingDimension = function() {
  return m;
};
window.cleanupLiteRtEmbeddings = async function() {
  if (console.log("[LiteRT] ========================================"), console.log("[LiteRT] Starting cleanup..."), console.log("[LiteRT] ========================================"), i)
    try {
      typeof i.delete == "function" && !i.deleted && (i.delete(), console.log("[LiteRT] ✅ Model deleted"));
    } catch (o) {
      console.warn("[LiteRT] ⚠️  Error deleting model (non-fatal):", o);
    }
  if (i = null, s)
    try {
      s.processor && typeof s.processor.delete == "function" && (s.processor.delete(), console.log("[LiteRT] ✅ Tokenizer deleted"));
    } catch (o) {
      console.warn("[LiteRT] ⚠️  Error deleting tokenizer (non-fatal):", o);
    }
  s = null;
  try {
    const r = R().numTensors;
    r > 0 && (console.log(`[LiteRT] Disposing ${r} TensorFlow.js tensors`), h(), console.log("[LiteRT] ✅ Tensors disposed"));
  } catch (o) {
    console.warn("[LiteRT] ⚠️  Error disposing tensors (non-fatal):", o);
  }
  console.log("[LiteRT] ✅ Keeping WASM runtime (reusable across models)"), c = 256, console.log("[LiteRT] ✅ Reset MAX_SEQUENCE_LENGTH to default"), u = !1, console.log("[LiteRT] ========================================"), console.log("[LiteRT] ✅ Cleanup completed"), console.log("[LiteRT] ========================================");
};
window.isLiteRtEmbeddingsInitialized = function() {
  return u;
};
console.log("LiteRT Embeddings module loaded successfully");
