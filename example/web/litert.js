async function F(t) {
  if (typeof importScripts == "function")
    importScripts(t.toString());
  else {
    const e = document.createElement("script");
    return e.src = t.toString(), e.crossOrigin = "anonymous", new Promise((r, s) => {
      e.addEventListener("load", () => {
        r();
      }, !1), e.addEventListener("error", (o) => {
        s(o);
      }, !1), document.body.appendChild(e);
    });
  }
}
var j = async (t, e, r, s, o) => {
  if (e && await F(e), !self.ModuleFactory)
    throw new Error("ModuleFactory not set.");
  const n = await self.ModuleFactory(self.Module || o);
  return self.ModuleFactory = self.Module = void 0, new t(n, s);
}, T = class {
  constructor(t, e, r) {
    this.liteRtInterpreter = t, this.onDelete = r;
    const s = this.liteRtInterpreter.inputs();
    for (let n = 0; n < s.size(); ++n) {
      const i = s.get(n);
      this.inputTensors.set(i.name(), i);
    }
    const o = this.liteRtInterpreter.listSignatures();
    for (let n = 0; n < o.size(); ++n) {
      const i = o.get(n);
      this.signatures[i] = e(
        this.liteRtInterpreter.getSignatureRunner(i)
      );
    }
    this.primarySignature = e(t), this.accelerator = this.primarySignature.accelerator;
  }
  inputTensors = /* @__PURE__ */ new Map();
  outputTensors = /* @__PURE__ */ new Map();
  signatures = {};
  primarySignature;
  accelerator;
  deleted = !1;
  checkDeleted() {
    if (this.deleted)
      throw new Error("Model has been deleted. Please reload the model.");
  }
  run(t, e) {
    if (this.checkDeleted(), typeof t == "string") {
      const r = t, s = e, o = this.signatures[r];
      if (!o) {
        const n = Object.keys(this.signatures).join(", ");
        throw new Error(`Signature '${r}' not found in the model. Available signatures: ${n}`);
      }
      if (!s)
        throw new Error(`No input provided for signature '${r}'.`);
      return o.run(s);
    } else
      return this.primarySignature.run(t);
  }
  /**
   * Returns the input details for the primary signature.
   */
  getInputDetails() {
    return this.checkDeleted(), this.primarySignature.getInputDetails();
  }
  /**
   * Returns the output details for the primary signature.
   */
  getOutputDetails() {
    return this.checkDeleted(), this.primarySignature.getOutputDetails();
  }
  delete() {
    if (!this.deleted) {
      this.deleted = !0;
      for (const t of Object.values(this.signatures))
        t.delete();
      this.primarySignature.delete();
      for (const t of this.inputTensors.values())
        t.delete();
      for (const t of this.outputTensors.values())
        t.delete();
      this.liteRtInterpreter.delete(), this.onDelete();
    }
  }
}, v = Object.freeze({
  // noType is not supported.
  float32: Float32Array,
  int32: Int32Array
  // The following types are disabled until we support them in C++.
  /*
  'uint8': Uint8Array,
  // TODO(msoulanille): int64 is not supported yet because BigInt64Array makes
  // TFJS integration more complicated.
  // 'int64': BigInt64Array,
  // String is not supported.
  // TODO(msoulanille): bool will require special handling in C++.
  // TFJS WebGPU stores bool in a 32 bit integer.
  // However, tf.data() returns a Uint8Array.
  // Unclear if we should follow TFJS or whatever LiteRt xnnpack does.
  'bool': Uint8Array,
  'int16': Int16Array,
  // Complex64 is not supported.
  'int8': Int8Array,
  // JS does not have a Float16Array.
  // TODO(msoulanille): This will require special handling in C++.
  'float16': Float32Array,
  'float64': Float64Array,
  // Complex128 is not supported.
  // TODO(msoulanille): uint64 is not supported yet because BigInt64Array makes
  // TFJS integration more complicated.
  // 'uint64': BigInt64Array,
  // Resource and Variant are not supported.
  'uint32': Uint32Array,
  'uint16': Uint16Array,
  // TODO(msoulanille): This will require special handling in C++.
  'int4': Uint8Array,
  // TODO(msoulanille): This will require special handling in C++.
  'bfloat16': Float32Array,
  */
});
new Set(Object.keys(v));
function L(t) {
  if (t instanceof Float32Array)
    return "float32";
  if (t instanceof Int32Array)
    return "int32";
  throw new Error(
    `Unsupported typed array type ${t.constructor.name}.`
  );
}
var I = class extends Error {
  constructor() {
    super(
      "LiteRT is not initialized yet. Please call loadLiteRt() and wait for its promise to resolve to load the LiteRT WASM module."
    );
  }
}, m = void 0, w = void 0;
function p() {
  if (!m)
    throw new I();
  return m;
}
function z(t) {
  m = t;
}
function _() {
  return w;
}
function B() {
  return !!w;
}
function E(t) {
  w = t;
}
function k(t) {
  const e = t;
  return e !== void 0 && typeof e == "object" && typeof e.type == "object" && typeof e.accelerator == "string" && typeof e.reference == "object";
}
var l = class y {
  // This contains properties of TensorWrapper but organized in a more
  // JS-friendly way. Some properties may be missing, such as when the user
  // creates their own Tensor.
  //
  // Additionally, instances of this interface are not associated with a
  // specific TfLite Interpreter.
  static copyFunctions = {};
  tensorReferenceData;
  deletedInternal = !1;
  constructor(e, r) {
    k(e) ? this.tensorReferenceData = e : this.tensorReferenceData = {
      type: {
        dtype: L(e),
        layout: {
          dimensions: r ?? [e.length]
        }
      },
      accelerator: "wasm",
      reference: $(e)
    };
  }
  /**
   * Returns the datatype of the tensor.
   */
  get type() {
    return this.tensorReferenceData.type;
  }
  /**
   * Returns the accelerator the tensor is stored on.
   */
  get accelerator() {
    return this.tensorReferenceData.accelerator;
  }
  /**
   * Returns the internal reference to the tensor data.
   *
   * Users should not rely on this call, and should use `toTypedArray` instead
   * if they are trying to view Tensor data.
   */
  get reference() {
    return this.tensorReferenceData.reference;
  }
  static fromTypedArray(e, r) {
    return new y(e, r);
  }
  /**
   * Returns the data of the tensor as a TypedArray.
   *
   * The returned TypedArray is a copy of the data, and this method does not
   * delete the original tensor.
   * @throws An error if the tensor is not on Wasm.
   */
  toTypedArray() {
    if (this.accelerator !== "wasm")
      throw new Error(
        "Tensor must be on Wasm to be converted to a TypedArray."
      );
    const e = v[this.type.dtype], s = this.reference.data();
    return new e(
      // Cast is needed to avoid 'SharedArrayBuffer' in the type.
      s.buffer,
      s.byteOffset,
      s.length / e.BYTES_PER_ELEMENT
    ).slice();
  }
  /**
   * Copies the tensor to the given accelerator.
   *
   * @param accelerator The accelerator to copy to.
   * @return A promise that resolves to the copied tensor.
   */
  async copyTo(e) {
    const r = y.copyFunctions[this.accelerator];
    if (!r)
      throw new Error(
        `Accelerator ${this.accelerator} does not support copying`
      );
    const s = r[e];
    if (!s || !s.copyTo) {
      const o = Object.entries(r).filter(([n, i]) => i.copyTo).map(([n, i]) => n);
      throw new Error(`Accelerator ${this.accelerator} does not support copying to ${e}. It supports copying to the following accelerators: [${o.join(", ")}].`);
    }
    return s.copyTo(this);
  }
  /**
   * Moves the tensor to the given accelerator, deleting the original.
   *
   * @param accelerator The accelerator to move to.
   * @return A promise that resolves to the moved tensor.
   */
  async moveTo(e) {
    const r = y.copyFunctions[this.accelerator];
    if (!r)
      throw new Error(
        `Accelerator ${this.accelerator} does not support moving`
      );
    const s = r[e];
    if (!s || !s.moveTo) {
      const o = Object.entries(r).filter(([n, i]) => i.moveTo).map(([n, i]) => n);
      throw new Error(`Accelerator ${this.accelerator} does not support moving to ${e}. It supports moving to the following accelerators: [${o.join(", ")}].`);
    }
    return s.moveTo(this);
  }
  get deleted() {
    return this.deletedInternal;
  }
  delete() {
    this.tensorReferenceData.reference.delete?.(), this.deletedInternal = !0;
  }
}, x = class extends Error {
  constructor(t, e, r, s) {
    super(`Input tensor for ${t} at position ${e} has type ${s}, but signature expects ${r}.`);
  }
}, b = class extends Error {
  constructor(t, e, r) {
    const s = `[${e.join(", ")}]`, o = `[${r.join(", ")}]`;
    super(
      `Input tensor for ${t} has shape ${o}, but signature expects ${s}.`
    );
  }
};
function $(t) {
  const e = p(), r = t.constructor, s = new e.liteRtWasm.CpuTensor(
    t.length * r.BYTES_PER_ELEMENT
  ), o = s.data();
  return new r(
    // Cast is needed to avoid 'SharedArrayBuffer' in the type.
    o.buffer,
    o.byteOffset,
    t.length
  ).set(t), s;
}
var C = class {
  constructor(t) {
    this.signatureRunnerWrapper = t, this.inputTensorsVector = this.signatureRunnerWrapper.inputs();
    for (let e = 0; e < this.inputTensorsVector.size(); ++e) {
      const r = this.inputTensorsVector.get(e);
      this.inputTensors.set(r.name(), r);
    }
    this.outputTensorsVector = this.signatureRunnerWrapper.outputs();
    for (let e = 0; e < this.outputTensorsVector.size(); ++e) {
      const r = this.outputTensorsVector.get(e);
      this.outputTensors.set(r.name(), r);
    }
  }
  inputTensors = /* @__PURE__ */ new Map();
  inputTensorsVector;
  outputTensors = /* @__PURE__ */ new Map();
  outputTensorsVector;
  deleted = !1;
  checkTypes(t) {
    const e = [...this.inputTensors.values()];
    for (let r = 0; r < e.length; ++r) {
      const s = e[r], o = t[r], n = s.type();
      if (n !== o.type.dtype)
        throw new x(
          s.name(),
          r,
          n,
          o.type.dtype
        );
    }
  }
  run(t) {
    if (this.deleted)
      throw new Error("Signature has been deleted. Please reload the model.");
    let e, r = !0;
    if (Array.isArray(t)) {
      if (t.length !== this.inputTensors.size)
        throw new Error(
          `run() called with ${t.length} inputs, but signature expects ${this.inputTensors.size} inputs`
        );
      e = t;
    } else if (t instanceof l) {
      if (this.inputTensors.size !== 1)
        throw new Error(
          `run() called with a single tensor, but signature expects ${this.inputTensors.size} inputs`
        );
      e = [t];
    } else {
      r = !1, e = [];
      for (const i of this.inputTensors.keys()) {
        const a = t[i];
        if (!a)
          throw new Error(`Expected input tensor with name '${i}', but none was provided.`);
        e.push(a);
      }
    }
    this.checkTypes(e);
    const s = this.runWithArray(e);
    if (r)
      return s;
    const o = {}, n = [...this.outputTensors.keys()];
    for (let i = 0; i < n.length; i++)
      o[n[i]] = s[i];
    return o;
  }
  pushErrorScopes() {
  }
  popErrorScopes(t) {
  }
  /**
   * Runs the default signature of the model with the given input tensors and
   * returns the outputs.
   */
  runWithArray(t) {
    const e = this.signatureRunnerWrapper.makeTensorVector();
    for (const o of t)
      e.push_back(o.reference);
    this.pushErrorScopes(), this.signatureRunnerWrapper.copyInputs(e), this.popErrorScopes("copyInputs"), e.delete(), this.pushErrorScopes(), this.signatureRunnerWrapper.invoke(), this.popErrorScopes("invoke"), this.pushErrorScopes();
    const r = this.signatureRunnerWrapper.copyOutputs();
    this.popErrorScopes("copyOutputs");
    const s = [];
    for (let o = 0; o < this.outputTensorsVector.size(); ++o) {
      const n = this.outputTensorsVector.get(o), i = r.get(o);
      s.push(new l({
        type: {
          dtype: n.type(),
          layout: { dimensions: n.shape() }
        },
        accelerator: n.accelerator(),
        reference: i
      })), n.delete();
    }
    return r.delete(), s;
  }
  /**
   * Get details about each input tensor.
   */
  getInputDetails() {
    return R(this.inputTensors);
  }
  /**
   * Get details about each output tensor.
   */
  getOutputDetails() {
    return R(this.outputTensors);
  }
  delete() {
    if (!this.deleted) {
      for (const t of this.inputTensors.values())
        t.delete();
      this.inputTensors.clear(), this.inputTensorsVector.delete();
      for (const t of this.outputTensors.values())
        t.delete();
      this.outputTensors.clear(), this.outputTensorsVector.delete(), this.deleted = !0;
    }
  }
};
function R(t) {
  return [...t.entries()].map(
    ([e, r], s) => ({ name: e, index: s, shape: r.shape(), dtype: r.type() })
  );
}
var O = class extends C {
  accelerator = "wasm";
  constructor(t) {
    super(t);
  }
  /**
   * Throws an error if the input tensors have different shapes than the
   * signature.
   *
   * Note that this may be overrestrictive since it doesn't account for
   * automatically expanding / contracting dimensions (e.g. [1, 1, 224, 224] vs
   * [224, 224]).
   */
  checkShapes(t) {
    let e = 0;
    for (const r of this.inputTensors.values()) {
      const o = t[e++].type.layout.dimensions, n = r.shape();
      if (n.length !== o.length)
        throw new b(r.name(), n, o);
      for (let i = 0; i < o.length; ++i)
        if (o[i] !== n[i])
          throw new b(
            r.name(),
            n,
            o
          );
    }
  }
  runWithArray(t) {
    return this.checkShapes(t), super.runWithArray(t);
  }
};
function V() {
  return !!(typeof globalThis < "u" && globalThis.navigator && globalThis.navigator.gpu);
}
var P = ["internal", "out-of-memory", "validation"];
function h(t) {
  for (const e of P)
    t.pushErrorScope(e);
}
function d(t, e, r) {
  for (let s = 0; s < P.length; ++s)
    t.popErrorScope().then((o) => {
      o && r(o, e);
    });
}
function N(t) {
  const e = [1, 1, 1, 1];
  switch (t.length) {
    case 1:
      e[3] = t[0];
      break;
    case 2:
      e[3] = t[1], e[2] = t[0];
      break;
    case 3:
      e[3] = t[2], e[2] = t[1], e[1] = t[0];
      break;
    case 4:
      e[3] = t[3], e[2] = t[2], e[1] = t[1], e[0] = t[0];
      break;
    default:
      throw new Error(
        "Only 1D~4D tensors are supported, but got shape: " + t.toString() + "."
      );
  }
  return e;
}
async function S(t) {
  const e = await p().getWebGpuDevice(), s = p().getConverterFactory().makeConverterToTfjs(
    t.reference
  ).convertToTfjs(t.reference), o = e.createBuffer({
    size: s.size,
    usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST,
    mappedAtCreation: !1
  }), n = e.createCommandEncoder();
  n.copyBufferToBuffer(s, 0, o, 0, s.size), e.queue.submit([n.finish()]), await o.mapAsync(GPUMapMode.READ);
  const i = o.getMappedRange(), a = new Uint8Array(i), c = p().liteRtWasm.CpuTensor, f = new c(a.byteLength);
  return f.data().set(a), o.unmap(), o.destroy(), new l({
    type: t.type,
    accelerator: "wasm",
    reference: f
  });
}
async function A(t) {
  const e = await p().getWebGpuDevice(), r = t.reference.data(), s = v[t.type.dtype], o = new s(
    // Cast is needed to avoid 'SharedArrayBuffer' in the type.
    r.buffer,
    r.byteOffset,
    r.length
  ), n = e.createBuffer({
    size: o.byteLength,
    usage: GPUBufferUsage.MAP_WRITE | GPUBufferUsage.COPY_SRC,
    mappedAtCreation: !0
  }), i = await n.getMappedRange();
  if (o instanceof Float32Array)
    new Float32Array(i).set(o);
  else if (o instanceof Int32Array)
    new Int32Array(i).set(o);
  else
    throw new Error(
      "Unsupported typed array type: " + o.constructor.name
    );
  n.unmap();
  const a = e.createBuffer({
    size: n.size,
    usage: GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
  }), c = e.createCommandEncoder();
  c.copyBufferToBuffer(
    n,
    0,
    a,
    0,
    n.size
  ), e.queue.submit([c.finish()]), n.destroy();
  const f = N(t.type.layout.dimensions), G = p().getConverterFactory().makeConverterFromTfjs(
    t.type.dtype,
    ...f
  ).convertFromTfjs(a);
  return a.destroy(), new l({
    type: t.type,
    accelerator: "webgpu",
    reference: G
  });
}
var Y = class U extends Map {
  val;
  constructor() {
    super();
  }
  getMap(e, r = !1) {
    let s = this;
    for (let o = 0; o < e.length; o++) {
      if (!s.has(e[o])) {
        if (!r)
          return;
        s.set(e[o], new U());
      }
      s = s.get(e[o]);
    }
    return s;
  }
  getPath(e) {
    return this.getMap(e)?.val;
  }
  hasPath(e) {
    return this.getMap(e) !== void 0;
  }
  setPath(e, r) {
    const s = this.getMap(
      e,
      /* createIfMissing= */
      !0
    );
    s.val = r;
  }
};
function W(t, e = (r) => r) {
  const r = new Y();
  return (...s) => {
    const o = e(s);
    return r.hasPath(o) || r.setPath(o, t(...s)), r.getPath(o);
  };
}
var q = class {
  constructor(t, e, r) {
    this.converter = t, this.wasm = e, this.gpuErrorReporter = r;
  }
  convertFromTfjs(t) {
    h(this.wasm.preinitializedWebGPUDevice);
    const e = this.wasm.WebGPU.importJsBuffer(t), r = this.converter.convertFromTfjs(e);
    return d(
      this.wasm.preinitializedWebGPUDevice,
      "convertFromTfjs",
      this.gpuErrorReporter.val
    ), r;
  }
  delete() {
    this.converter.delete();
  }
}, H = class {
  constructor(t, e, r) {
    this.converter = t, this.wasm = e, this.gpuErrorReporter = r;
  }
  convertToTfjs(t) {
    h(this.wasm.preinitializedWebGPUDevice);
    const e = this.converter.convertToTfjs(t), r = this.wasm.WebGPU.getJsObject(e);
    return d(
      this.wasm.preinitializedWebGPUDevice,
      "convertToTfjs",
      this.gpuErrorReporter.val
    ), r;
  }
  delete() {
    this.converter.delete();
  }
}, J = class {
  constructor(t, e) {
    this.wasm = t, this.gpuErrorReporter = e;
  }
  /**
   * Returns true if this ConverterFactory uses the same WebGPU device as the
   * one passed in.
   */
  isWebGpuDeviceCompatible(t) {
    return t === this.wasm.preinitializedWebGPUDevice;
  }
  /**
   * Returns an InputConverter for quickly converting WebGPU buffers in TF.js
   * tensor format into the corresponding LiteRT Tensors. Each InputConverter is
   * created for a given type and [B,H,W,C] shape, so the converter can be
   * reused, but only for tensors of the same type and shape.
   */
  makeConverterFromTfjs = W(this.makeConverterFromTfjsInternal.bind(this));
  makeConverterFromTfjsInternal(t, e, r, s, o) {
    h(this.wasm.preinitializedWebGPUDevice);
    const n = this.wasm.makeConverterFromTfjs(t, e, r, s, o);
    return d(
      this.wasm.preinitializedWebGPUDevice,
      "makeConverterFromTfjs",
      this.gpuErrorReporter.val
    ), new q(
      n,
      this.wasm,
      this.gpuErrorReporter
    );
  }
  /**
   * Returns an OutputConverter for quickly converting LiteRT Tensors into the
   * the corresponding WebGPU buffer in TF.js tensor format. Each
   * OutputConverter is created to match the specifications of the given Tensor
   * (type and [B,H,W,C] shape), so the converter can be reused, but only for
   * Tensors of the same type and shape.
   */
  makeConverterToTfjs = W(
    this.makeConverterToTfjsInternal.bind(this),
    ([t]) => t.getCacheKey()
  );
  makeConverterToTfjsInternal(t) {
    h(this.wasm.preinitializedWebGPUDevice);
    const e = this.wasm.makeConverterToTfjs(t);
    return d(
      this.wasm.preinitializedWebGPUDevice,
      "makeConverterToTfjs",
      this.gpuErrorReporter.val
    ), new H(
      e,
      this.wasm,
      this.gpuErrorReporter
    );
  }
}, K = class extends C {
  constructor(t, e, r) {
    super(t), this.device = e, this.gpuErrorReporter = r;
  }
  accelerator = "webgpu";
  pushErrorScopes() {
    h(this.device);
  }
  popErrorScopes(t) {
    d(this.device, t, this.gpuErrorReporter.val);
  }
}, X = [
  "shader-f16",
  "subgroups",
  // In origin trial
  "subgroups-f16"
  // In origin trial
];
function ue(t, e) {
  return p().loadAndCompile(t, e);
}
var Z = class g {
  liteRtWasm;
  device;
  // Boxed so it can be passed as a reference to the signatures and updated
  // later.
  gpuErrorReporter = {
    val: (e, r) => {
      console.error("GPU error:", e, "at:", r);
    }
  };
  loadAndCompileWebGpuWasCalled = !1;
  loadedModels = /* @__PURE__ */ new Set();
  converterFactory;
  constructor(e) {
    if (this.liteRtWasm = e, !this.liteRtWasm.loadAndCompileWebGpu)
      throw new Error("loadAndCompileWebGpu is not defined.");
    this.liteRtWasm.setupLogging();
  }
  pushErrorScopes() {
    if (!this.device)
      throw new Error("No GPU device provided.");
    h(this.device);
  }
  popErrorScopes(e) {
    if (!this.device)
      throw new Error("No GPU device provided.");
    d(this.device, e, this.gpuErrorReporter.val);
  }
  static async urlToUint8Array(e) {
    const r = await fetch(e);
    return new Uint8Array(await r.arrayBuffer());
  }
  static async readableStreamToUint8Array(e) {
    let r = 0, s = new Uint8Array(
      1024
      /* arbitrary starting size */
    );
    const o = 2e9;
    for (; ; ) {
      const { done: n, value: i } = await e.read();
      if (i) {
        if (s.byteLength < r + i.byteLength) {
          if (r + i.byteLength > o)
            throw new Error(`Model is too large (> ${o} bytes`);
          const a = new Uint8Array(Math.min(
            o,
            Math.max(s.byteLength, i.byteLength) * 2
          ));
          a.set(s), s = a;
        }
        s.set(i, r), r += i.byteLength;
      }
      if (n)
        break;
    }
    return s.slice(0, r);
  }
  /**
   * Initialize the WebGPU device for LiteRT.
   */
  async initializeDefaultWebGpuDevice() {
    if (this.device) {
      console.warn("WebGPU device is already initialized.");
      return;
    }
    if (!V())
      throw new Error("This browser does not support WebGPU.");
    const e = {
      powerPreference: "high-performance"
    }, r = await navigator.gpu.requestAdapter(e);
    if (!r)
      throw new Error("No GPU adapter found.");
    const s = r.info, o = {
      maxBufferSize: r.limits.maxBufferSize,
      maxStorageBufferBindingSize: r.limits.maxStorageBufferBindingSize,
      maxStorageBuffersPerShaderStage: r.limits.maxStorageBuffersPerShaderStage,
      maxTextureDimension2D: r.limits.maxTextureDimension2D
    }, n = [];
    for (const a of X)
      r.features.has(a) && n.push(a);
    const i = await r.requestDevice({
      requiredFeatures: n,
      requiredLimits: o
    });
    this.setWebGpuDevice(i, s);
  }
  /**
   * Set the error reporter for LiteRt.
   */
  setErrorReporter(e) {
    this.liteRtWasm.setErrorReporter(e);
  }
  /**
   * Set the WebGPU error reporter for LiteRt.
   */
  setGpuErrorReporter(e) {
    this.gpuErrorReporter.val = e;
  }
  /**
   * Set the WebGPU device and adapter info for LiteRT.
   */
  // TODO: Remove adapterInfo from the api, as the latest GPUDevice type should
  // have adapterInfo.
  setWebGpuDevice(e, r) {
    if (this.loadAndCompileWebGpuWasCalled)
      throw new Error(
        "The WebGPU device cannot be set after loading a WebGPU model."
      );
    if (this.device = e, !this.device.adapterInfo) {
      if (!r)
        throw new Error(
          "The device does not have adapter info, so adapterInfo must be provided."
        );
      this.device.adapterInfo = r;
    }
    this.liteRtWasm.preinitializedWebGPUDevice = this.device;
  }
  /**
   * Get the WebGPU device that LiteRT is using. If the device is not set,
   * initialize it.
   */
  async getWebGpuDevice() {
    return this.device || await this.initializeDefaultWebGpuDevice(), this.device;
  }
  /**
   * Get the WebGPU adapter info that LiteRT is using. If the WebGPU device is
   * not set, initialize it.
   */
  async getAdapterInfo() {
    return this.device || await this.initializeDefaultWebGpuDevice(), this.device.adapterInfo;
  }
  /**
   * Loads a LiteRt model.
   *
   * @param model The model data. This can be a string (the model url), a URL
   *     object, a Uint8Array (the model bytes), or a
   *     ReadableStreamDefaultReader (for streaming model loading).
   * @param compileOptions The options for compiling the model. This includes
   *     the accelerator to use ('webgpu' or 'wasm') and the WebGPU device
   *     (for direct GPU model inputs / outputs).
   * @returns A promise that resolves to the CompiledModel.
   */
  async loadAndCompile(e, r) {
    let s;
    if (typeof e == "string" || e instanceof URL)
      s = await g.urlToUint8Array(e);
    else if (e instanceof Uint8Array)
      s = e;
    else if (e instanceof ReadableStreamDefaultReader)
      s = await g.readableStreamToUint8Array(e);
    else
      throw new Error("Unsupported model type.");
    const o = this.liteRtWasm._malloc(s.byteLength);
    this.liteRtWasm.HEAPU8.set(s, o);
    let n;
    const i = () => {
      this.liteRtWasm._free(o), this.loadedModels.delete(n);
    };
    if (r.accelerator === "webgpu") {
      this.liteRtWasm.preinitializedWebGPUDevice || await this.initializeDefaultWebGpuDevice(), this.pushErrorScopes(), this.loadAndCompileWebGpuWasCalled = !0;
      const a = this.liteRtWasm.loadAndCompileWebGpu(o, s.byteLength);
      this.popErrorScopes("loadAndCompile"), n = new T(a, (c) => {
        if (!this.device)
          throw new Error("No GPU device provided.");
        return new K(
          c,
          this.device,
          this.gpuErrorReporter
        );
      }, i);
    } else {
      const a = this.liteRtWasm.loadAndCompileCpu(o, s.byteLength);
      n = new T(a, (c) => new O(c), i);
    }
    return this.loadedModels.add(n), n;
  }
  /**
   * Gets or creates a ConverterFactory for our tensor converters.
   */
  getConverterFactory() {
    return this.converterFactory || (this.converterFactory = new J(this.liteRtWasm, this.gpuErrorReporter)), this.converterFactory;
  }
  /**
   * Delete the LiteRt wasm module and all loaded models.
   */
  delete() {
    for (const e of this.loadedModels)
      e.delete();
  }
};
function Q(t, e) {
  if (!t) return e;
  if (!e) return t;
  const r = t.endsWith("/") ? t : t + "/", s = e.startsWith("/") ? e.substring(1) : e;
  return r + s;
}
var ee = new Uint8Array([
  0,
  97,
  115,
  109,
  1,
  0,
  0,
  0,
  1,
  5,
  1,
  96,
  0,
  1,
  123,
  3,
  2,
  1,
  0,
  10,
  15,
  1,
  13,
  0,
  65,
  1,
  253,
  15,
  65,
  2,
  253,
  15,
  253,
  128,
  2,
  11
]), te = new Uint8Array([
  0,
  97,
  115,
  109,
  1,
  0,
  0,
  0,
  1,
  4,
  1,
  96,
  0,
  0,
  3,
  2,
  1,
  0,
  5,
  4,
  1,
  3,
  1,
  1,
  10,
  11,
  1,
  9,
  0,
  65,
  0,
  254,
  16,
  2,
  0,
  26,
  11
]), u = {
  relaxedSimd: void 0,
  threads: void 0
};
async function D(t) {
  try {
    return await WebAssembly.instantiate(t), { supported: !0 };
  } catch (e) {
    return { supported: !1, error: e };
  }
}
var re = {
  relaxedSimd: () => (u.relaxedSimd === void 0 && (u.relaxedSimd = D(ee)), u.relaxedSimd),
  threads: () => {
    if (u.threads === void 0)
      try {
        typeof MessageChannel < "u" && new MessageChannel().port1.postMessage(new SharedArrayBuffer(1)), u.threads = D(te);
      } catch (t) {
        u.threads = Promise.resolve({ supported: !1, error: t });
      }
    return u.threads;
  }
};
async function se(t) {
  const e = re[t]?.();
  if (!e)
    throw new Error(`Unknown feature: ${t}`);
  return (await e).supported;
}
var oe = "litert_wasm_internal.js", ne = "litert_wasm_compat_internal.js";
async function ie(t, e) {
  const r = t;
  r.endsWith(".wasm") || r.endsWith(".js");
  const s = await se("relaxedSimd");
  let o = ne;
  s && (o = oe);
  let n = t;
  if (r.endsWith(".wasm"))
    throw new Error(
      "Please load the `.js` file corresponding to the `.wasm` file, or load the directory containing it."
    );
  return r.endsWith(".js") || (n = Q(t, o)), j(Z, n);
}
function pe(t, e) {
  if (B())
    throw new Error("LiteRT is already loading / loaded.");
  return E(ie(t).then((r) => (z(r), r)).catch((r) => {
    throw E(void 0), r;
  })), _();
}
function ae() {
  l.copyFunctions.wasm = {
    webgpu: {
      copyTo: A,
      moveTo: async (t) => {
        const e = await A(t);
        return t.delete(), e;
      }
    }
  }, l.copyFunctions.webgpu = {
    wasm: {
      copyTo: S,
      moveTo: async (t) => {
        const e = await S(t);
        return t.delete(), e;
      }
    }
  };
}
ae();
/**
 * @fileoverview A memoization utility for JavaScript.
 *
 * This utility provides a function `memoize` that can be used to memoize
 * functions. A memoized function will only be called once for each unique set
 * of arguments, and the result will be cached and returned on subsequent calls.
 *
 * Example usage:
 *
 * ```typescript
 * const memoizedAdd = memoize((a, b) => a + b);
 * console.log(memoizedAdd(1, 2)); // Output: 3
 * console.log(memoizedAdd(1, 2)); // Output: 3
 * ```
 *
 * In this example, the `memoizedAdd` function will only be called once, even
 * though it is called twice. The result of the first call will be cached and
 * returned on the second call.
 *
 * @license
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
export {
  l as T,
  ue as a,
  pe as l
};
