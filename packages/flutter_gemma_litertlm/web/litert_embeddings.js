import { m as A, d as k, s as S, r as M } from "./tensorflow.js";
import { l as z, a as L, T as R } from "./litert.js";
import { S as F } from "./sentencepiece.js";
const $ = "task: search result | query: ", x = "title: none | text: ", y = 2, h = 1, E = 0;
let c = 256;
const m = 768;
let a = null, d = null, u = !1, w = !1, T = null, g = null;
async function C(t) {
  try {
    const o = await fetch(t);
    if (!o.ok)
      throw new Error(`Failed to fetch tokenizer: ${o.status} ${o.statusText}`);
    const r = await o.arrayBuffer(), n = new F();
    if (typeof n.loadFromBuffer == "function")
      await n.loadFromBuffer(new Uint8Array(r));
    else {
      const e = new Uint8Array(r);
      let s = "";
      for (let l = 0; l < e.length; l++)
        s += String.fromCharCode(e[l]);
      const i = btoa(s);
      await n.loadFromB64StringModel(i);
    }
    return d = {
      encode: (e, s = !1) => {
        const i = n.encodeIds(e);
        return s ? [y, ...i, h] : i;
      },
      decode: (e) => n.decodeIds(e),
      processor: n
    }, d;
  } catch (o) {
    throw new Error("Failed to load SentencePiece tokenizer: " + o.message);
  }
}
async function D(t, o = "/node_modules/@litertjs/core/wasm/") {
  try {
    console.log(`[LiteRT] Loading model from: ${t}`), console.log(`[LiteRT] WASM loaded flag: ${w}`), await S("webgl"), await M(), w ? console.log("[LiteRT] WASM runtime already loaded, reusing") : (console.log(`[LiteRT] Loading WASM runtime from: ${o}`), await z(o), w = !0, console.log("[LiteRT] WASM runtime loaded successfully"));
    try {
      console.log("[LiteRT] Attempting to compile model with WebGPU..."), g = "webgpu", a = await L(t, {
        accelerator: "webgpu"
      }), console.log("[LiteRT] Model compiled, accelerator confirmed on first run");
    } catch (r) {
      console.warn("[LiteRT] WebGPU not available, falling back to WASM:", r.message), g = "wasm", a = await L(t, {
        accelerator: "wasm"
      }), console.log("[LiteRT] Model compiled with WASM successfully");
    }
    try {
      const r = a.getInputDetails();
      if (r && r.length > 0) {
        const n = r[0].shape;
        if (n && n.length >= 2) {
          const e = n[1];
          e !== c && (c = e, console.log(`[LiteRT] Auto-detected maxSequenceLength: ${c}`));
        }
      }
    } catch (r) {
      console.warn("[LiteRT] Failed to auto-detect sequence length, using default:", r);
    }
    return a;
  } catch (r) {
    throw new Error("Failed to load LiteRT model: " + r.message);
  }
}
function I(t) {
  const o = d.encode($, !1), r = "▁" + t, n = d.encode(r, !1);
  let e = [...o, ...n];
  if (e.unshift(y), e.push(h), e.length > c)
    e = e.slice(0, c);
  else if (e.length < c) {
    const s = c - e.length;
    e = [...e, ...new Array(s).fill(E)];
  }
  return e;
}
function _(t) {
  const o = d.encode(x, !1), r = "▁" + t, n = d.encode(r, !1);
  let e = [...o, ...n];
  if (e.unshift(y), e.push(h), e.length > c)
    e = e.slice(0, c);
  else if (e.length < c) {
    const s = c - e.length;
    e = [...e, ...new Array(s).fill(E)];
  }
  return e;
}
async function b(t) {
  if (!a || !d)
    throw new Error("Model or tokenizer not initialized. Call loadLiteRtEmbeddings first.");
  const o = I(t), r = new Int32Array(o), n = new R(r, [1, c]), e = n;
  try {
    const i = (await a.run(e))[0];
    N(i.accelerator);
    let l = i;
    i.accelerator === "webgpu" && (l = await i.moveTo("wasm"));
    const p = l.toTypedArray(), f = Array.from(p);
    return f.length !== m && console.warn(`Unexpected embedding dimension: ${f.length}, expected ${m}`), e !== n && !e.deleted && e.delete(), n.deleted || n.delete(), l !== i && !l.deleted && l.delete(), i.deleted || i.delete(), f;
  } catch (s) {
    try {
      e !== n && !e.deleted && e.delete(), n.deleted || n.delete();
    } catch (i) {
      console.warn("[LiteRT] Tensor cleanup failed:", i);
    }
    throw s;
  }
}
async function W(t) {
  if (!a || !d)
    throw new Error("Model or tokenizer not initialized. Call loadLiteRtEmbeddings first.");
  const o = _(t), r = new Int32Array(o), n = new R(r, [1, c]), e = n;
  try {
    const i = (await a.run(e))[0];
    let l = i;
    i.accelerator === "webgpu" && (l = await i.moveTo("wasm"));
    const p = l.toTypedArray(), f = Array.from(p);
    return f.length !== m && console.warn(`Unexpected embedding dimension: ${f.length}, expected ${m}`), e !== n && !e.deleted && e.delete(), n.deleted || n.delete(), l !== i && !l.deleted && l.delete(), i.deleted || i.delete(), f;
  } catch (s) {
    try {
      e !== n && !e.deleted && e.delete(), n.deleted || n.delete();
    } catch (i) {
      console.warn("[LiteRT] Tensor cleanup failed:", i);
    }
    throw s;
  }
}
function N(t) {
  T !== null || !t || (T = t, g && t !== g ? console.warn(
    `[LiteRT] Running on ${t}, not the requested ${g}. LiteRT fell back without raising — the model was not fully accelerated.`
  ) : console.log(`[LiteRT] Running on ${t}`));
}
window.loadLiteRtEmbeddings = async function(t, o, r) {
  try {
    if (u) {
      console.log("[LiteRT] Cleaning up previous model before reinitialization (hot restart detected)");
      try {
        await window.cleanupLiteRtEmbeddings();
      } catch (e) {
        console.warn("[LiteRT] Non-fatal cleanup error (will reinitialize anyway):", e), a = null, d = null, w = !1, u = !1;
      }
    }
    const n = r ?? "/node_modules/@litertjs/core/wasm/";
    await C(o), await D(t, n), u = !0;
  } catch (n) {
    throw u = !1, new Error("Failed to initialize LiteRT embeddings: " + n.message);
  }
};
window.generateEmbedding = async function(t) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (typeof t != "string" || t.trim().length === 0)
    throw new Error("Text must be a non-empty string");
  const o = await b(t);
  return new Float32Array(o);
};
window.generateDocumentEmbedding = async function(t) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (typeof t != "string" || t.trim().length === 0)
    throw new Error("Text must be a non-empty string");
  const o = await W(t);
  return new Float32Array(o);
};
window.generateEmbeddings = async function(t) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (!Array.isArray(t))
    throw new Error("texts must be an array");
  const o = [];
  for (const r of t) {
    if (typeof r != "string" || r.trim().length === 0)
      throw new Error("All texts must be non-empty strings");
    const n = await b(r);
    o.push(new Float32Array(n));
  }
  return o;
};
window.getLiteRtEmbeddingAccelerator = function() {
  return T;
};
window.getLiteRtEmbeddingDimension = function() {
  return m;
};
window.cleanupLiteRtEmbeddings = async function() {
  if (T = null, g = null, console.log("[LiteRT] ========================================"), console.log("[LiteRT] Starting cleanup..."), console.log("[LiteRT] ========================================"), a)
    try {
      typeof a.delete == "function" && !a.deleted && (a.delete(), console.log("[LiteRT] ✅ Model deleted"));
    } catch (t) {
      console.warn("[LiteRT] ⚠️  Error deleting model (non-fatal):", t);
    }
  if (a = null, d)
    try {
      d.processor && typeof d.processor.delete == "function" && (d.processor.delete(), console.log("[LiteRT] ✅ Tokenizer deleted"));
    } catch (t) {
      console.warn("[LiteRT] ⚠️  Error deleting tokenizer (non-fatal):", t);
    }
  d = null;
  try {
    const o = A().numTensors;
    o > 0 && (console.log(`[LiteRT] Disposing ${o} TensorFlow.js tensors`), k(), console.log("[LiteRT] ✅ Tensors disposed"));
  } catch (t) {
    console.warn("[LiteRT] ⚠️  Error disposing tensors (non-fatal):", t);
  }
  console.log("[LiteRT] ✅ Keeping WASM runtime (reusable across models)"), c = 256, console.log("[LiteRT] ✅ Reset MAX_SEQUENCE_LENGTH to default"), u = !1, console.log("[LiteRT] ========================================"), console.log("[LiteRT] ✅ Cleanup completed"), console.log("[LiteRT] ========================================");
};
window.isLiteRtEmbeddingsInitialized = function() {
  return u;
};
console.log("LiteRT Embeddings module loaded successfully");
