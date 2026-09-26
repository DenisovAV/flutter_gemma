import { m as k, d as M, s as F, r as z } from "./tensorflow.js";
import { l as $, a as R, T as b } from "./litert.js";
import { S as x } from "./sentencepiece.js";
const C = "task: search result | query: ", _ = "title: none | text: ", h = 2, L = 1, E = 0;
let c = 256;
const w = 768;
let s = null, d = null, u = !1, m = !1, p = null, g = null, T = null;
async function D(t) {
  try {
    const o = await fetch(t);
    if (!o.ok)
      throw new Error(`Failed to fetch tokenizer: ${o.status} ${o.statusText}`);
    const r = await o.arrayBuffer(), n = new x();
    if (typeof n.loadFromBuffer == "function")
      await n.loadFromBuffer(new Uint8Array(r));
    else {
      const e = new Uint8Array(r);
      let a = "";
      for (let l = 0; l < e.length; l++)
        a += String.fromCharCode(e[l]);
      const i = btoa(a);
      await n.loadFromB64StringModel(i);
    }
    return d = {
      encode: (e, a = !1) => {
        const i = n.encodeIds(e);
        return a ? [h, ...i, L] : i;
      },
      decode: (e) => n.decodeIds(e),
      processor: n
    }, d;
  } catch (o) {
    throw new Error("Failed to load SentencePiece tokenizer: " + o.message);
  }
}
async function I(t, o = "/node_modules/@litertjs/core/wasm/") {
  try {
    console.log(`[LiteRT] Loading model from: ${t}`), console.log(`[LiteRT] WASM loaded flag: ${m}`), await F("webgl"), await z(), m ? console.log("[LiteRT] WASM runtime already loaded, reusing") : (console.log(`[LiteRT] Loading WASM runtime from: ${o}`), await $(o), m = !0, console.log("[LiteRT] WASM runtime loaded successfully"));
    try {
      console.log("[LiteRT] Attempting to compile model with WebGPU..."), g = "webgpu", s = await R(t, {
        accelerator: "webgpu"
      }), B(s), console.log("[LiteRT] Model compiled, accelerator confirmed on first run");
    } catch (r) {
      console.warn("[LiteRT] WebGPU not available, falling back to WASM:", r.message), g = "wasm", s = await R(t, {
        accelerator: "wasm"
      }), console.log("[LiteRT] Model compiled with WASM successfully");
    }
    try {
      const r = s.getInputDetails();
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
    return s;
  } catch (r) {
    throw new Error("Failed to load LiteRT model: " + r.message);
  }
}
function W(t) {
  const o = d.encode(C, !1), r = "▁" + t, n = d.encode(r, !1);
  let e = [...o, ...n];
  if (e.unshift(h), e.push(L), e.length > c)
    e = e.slice(0, c);
  else if (e.length < c) {
    const a = c - e.length;
    e = [...e, ...new Array(a).fill(E)];
  }
  return e;
}
function N(t) {
  const o = d.encode(_, !1), r = "▁" + t, n = d.encode(r, !1);
  let e = [...o, ...n];
  if (e.unshift(h), e.push(L), e.length > c)
    e = e.slice(0, c);
  else if (e.length < c) {
    const a = c - e.length;
    e = [...e, ...new Array(a).fill(E)];
  }
  return e;
}
async function A(t) {
  if (!s || !d)
    throw new Error("Model or tokenizer not initialized. Call loadLiteRtEmbeddings first.");
  const o = W(t), r = new Int32Array(o), n = new b(r, [1, c]), e = n;
  try {
    const i = (await s.run(e))[0];
    S(i.accelerator);
    let l = i;
    i.accelerator === "webgpu" && (l = await i.moveTo("wasm"));
    const y = l.toTypedArray(), f = Array.from(y);
    return f.length !== w && console.warn(`Unexpected embedding dimension: ${f.length}, expected ${w}`), e !== n && !e.deleted && e.delete(), n.deleted || n.delete(), l !== i && !l.deleted && l.delete(), i.deleted || i.delete(), f;
  } catch (a) {
    try {
      e !== n && !e.deleted && e.delete(), n.deleted || n.delete();
    } catch (i) {
      console.warn("[LiteRT] Tensor cleanup failed:", i);
    }
    throw a;
  }
}
async function U(t) {
  if (!s || !d)
    throw new Error("Model or tokenizer not initialized. Call loadLiteRtEmbeddings first.");
  const o = N(t), r = new Int32Array(o), n = new b(r, [1, c]), e = n;
  try {
    const i = (await s.run(e))[0];
    S(i.accelerator);
    let l = i;
    i.accelerator === "webgpu" && (l = await i.moveTo("wasm"));
    const y = l.toTypedArray(), f = Array.from(y);
    return f.length !== w && console.warn(`Unexpected embedding dimension: ${f.length}, expected ${w}`), e !== n && !e.deleted && e.delete(), n.deleted || n.delete(), l !== i && !l.deleted && l.delete(), i.deleted || i.delete(), f;
  } catch (a) {
    try {
      e !== n && !e.deleted && e.delete(), n.deleted || n.delete();
    } catch (i) {
      console.warn("[LiteRT] Tensor cleanup failed:", i);
    }
    throw a;
  }
}
function B(t) {
  let o;
  try {
    o = t.isFullyAccelerated;
  } catch {
    return;
  }
  o === !1 ? (T = !1, console.warn(
    `[LiteRT] Model is not fully accelerated on ${g}. Unsupported ops run in WASM, so the accelerator reported after the first embedding is where the output buffer lives, not where every op ran.`
  )) : o === !0 && (T = !0);
}
function S(t) {
  p !== null || !t || (p = t, g && t !== g ? console.warn(
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
        console.warn("[LiteRT] Non-fatal cleanup error (will reinitialize anyway):", e), s = null, d = null, m = !1, u = !1;
      }
    }
    const n = r ?? "/node_modules/@litertjs/core/wasm/";
    await D(o), await I(t, n), u = !0;
  } catch (n) {
    throw u = !1, new Error("Failed to initialize LiteRT embeddings: " + n.message);
  }
};
window.generateEmbedding = async function(t) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (typeof t != "string" || t.trim().length === 0)
    throw new Error("Text must be a non-empty string");
  const o = await A(t);
  return new Float32Array(o);
};
window.generateDocumentEmbedding = async function(t) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (typeof t != "string" || t.trim().length === 0)
    throw new Error("Text must be a non-empty string");
  const o = await U(t);
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
    const n = await A(r);
    o.push(new Float32Array(n));
  }
  return o;
};
window.getLiteRtEmbeddingAccelerator = function() {
  return p;
};
window.getLiteRtEmbeddingFullyAccelerated = function() {
  return T;
};
window.getLiteRtEmbeddingDimension = function() {
  return w;
};
window.cleanupLiteRtEmbeddings = async function() {
  if (p = null, g = null, T = null, console.log("[LiteRT] ========================================"), console.log("[LiteRT] Starting cleanup..."), console.log("[LiteRT] ========================================"), s)
    try {
      typeof s.delete == "function" && !s.deleted && (s.delete(), console.log("[LiteRT] ✅ Model deleted"));
    } catch (t) {
      console.warn("[LiteRT] ⚠️  Error deleting model (non-fatal):", t);
    }
  if (s = null, d)
    try {
      d.processor && typeof d.processor.delete == "function" && (d.processor.delete(), console.log("[LiteRT] ✅ Tokenizer deleted"));
    } catch (t) {
      console.warn("[LiteRT] ⚠️  Error deleting tokenizer (non-fatal):", t);
    }
  d = null;
  try {
    const o = k().numTensors;
    o > 0 && (console.log(`[LiteRT] Disposing ${o} TensorFlow.js tensors`), M(), console.log("[LiteRT] ✅ Tensors disposed"));
  } catch (t) {
    console.warn("[LiteRT] ⚠️  Error disposing tensors (non-fatal):", t);
  }
  console.log("[LiteRT] ✅ Keeping WASM runtime (reusable across models)"), c = 256, console.log("[LiteRT] ✅ Reset MAX_SEQUENCE_LENGTH to default"), u = !1, console.log("[LiteRT] ========================================"), console.log("[LiteRT] ✅ Cleanup completed"), console.log("[LiteRT] ========================================");
};
window.isLiteRtEmbeddingsInitialized = function() {
  return u;
};
console.log("LiteRT Embeddings module loaded successfully");
