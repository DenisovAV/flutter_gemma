function Nl(n, e) {
  for (var t = 0; t < e.length; t++) {
    const r = e[t];
    if (typeof r != "string" && !Array.isArray(r)) {
      for (const s in r)
        if (s !== "default" && !(s in n)) {
          const o = Object.getOwnPropertyDescriptor(r, s);
          o && Object.defineProperty(n, s, o.get ? o : {
            enumerable: !0,
            get: () => r[s]
          });
        }
    }
  }
  return Object.freeze(Object.defineProperty(n, Symbol.toStringTag, { value: "Module" }));
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const kl = 1e-7, Al = 1e-4;
class Fl {
  constructor(e, t) {
    this.backend = e, this.dataMover = t, this.data = /* @__PURE__ */ new WeakMap(), this.dataIdsCount = 0;
  }
  get(e) {
    return this.data.has(e) || this.dataMover.moveData(this.backend, e), this.data.get(e);
  }
  set(e, t) {
    this.dataIdsCount++, this.data.set(e, t);
  }
  has(e) {
    return this.data.has(e);
  }
  delete(e) {
    return this.dataIdsCount--, this.data.delete(e);
  }
  numDataIds() {
    return this.dataIdsCount;
  }
}
class $i {
  refCount(e) {
    return Ae("refCount");
  }
  incRef(e) {
    return Ae("incRef");
  }
  timerAvailable() {
    return !0;
  }
  time(e) {
    return Ae("time");
  }
  read(e) {
    return Ae("read");
  }
  readSync(e) {
    return Ae("readSync");
  }
  readToGPU(e, t) {
    return Ae("readToGPU");
  }
  numDataIds() {
    return Ae("numDataIds");
  }
  disposeData(e, t) {
    return Ae("disposeData");
  }
  write(e, t, r) {
    return Ae("write");
  }
  move(e, t, r, s, o) {
    return Ae("move");
  }
  createTensorFromGPUData(e, t, r) {
    return Ae("createTensorFromGPUData");
  }
  memory() {
    return Ae("memory");
  }
  /** Returns the highest precision for floats in bits (e.g. 16 or 32) */
  floatPrecision() {
    return Ae("floatPrecision");
  }
  /** Returns the smallest representable number.  */
  epsilon() {
    return this.floatPrecision() === 32 ? kl : Al;
  }
  dispose() {
    return Ae("dispose");
  }
}
function Ae(n) {
  throw new Error(`'${n}' not yet implemented or not found in the registry. This kernel may not be supported by the tfjs backend you have chosen`);
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function wr(n, e, t) {
  return Math.max(n, Math.min(e, t));
}
function As(n) {
  return n % 2 === 0 ? n : n + 1;
}
function Ln(n, e, t) {
  const r = n[e];
  n[e] = n[t], n[t] = r;
}
function Dl(n) {
  let e = 0;
  for (let t = 0; t < n.length; t++)
    e += n[t];
  return e;
}
function O(n, e) {
  if (!n)
    throw new Error(typeof e == "string" ? e : e());
}
function vi(n, e, t = "") {
  O(ge(n, e), () => t + ` Shapes ${n} and ${e} must match`);
}
function _(n) {
  if (n.length === 0)
    return 1;
  let e = n[0];
  for (let t = 1; t < n.length; t++)
    e *= n[t];
  return e;
}
function ge(n, e) {
  if (n === e)
    return !0;
  if (n == null || e == null || n.length !== e.length)
    return !1;
  for (let t = 0; t < n.length; t++)
    if (n[t] !== e[t])
      return !1;
  return !0;
}
function Cr(n) {
  return n % 1 === 0;
}
function is(n) {
  const e = Math.ceil(Math.sqrt(n));
  return [e, Math.ceil(n / e)];
}
function dn(n, e) {
  return e <= n.length ? n : n + " ".repeat(e - n.length);
}
function wo(n, e = (s) => 0, t, r) {
  return new Promise((s, o) => {
    let i = 0;
    const a = () => {
      if (n()) {
        s();
        return;
      }
      i++;
      const c = e(i);
      if (t != null && i >= t) {
        o();
        return;
      }
      r != null ? r(a, c) : setTimeout(a, c);
    };
    a();
  });
}
function Ol(n, e) {
  let t = 1, r = -1;
  for (let o = 0; o < n.length; ++o)
    if (n[o] >= 0)
      t *= n[o];
    else if (n[o] === -1) {
      if (r !== -1)
        throw Error(`Shapes can only have 1 implicit size. Found -1 at dim ${r} and dim ${o}`);
      r = o;
    } else if (n[o] < 0)
      throw Error(`Shapes can not be < 0. Found ${n[o]} at dim ${o}`);
  if (r === -1) {
    if (e > 0 && e !== t)
      throw Error(`Size(${e}) must match the product of shape ${n}`);
    return n;
  }
  if (t === 0)
    throw Error(`Cannot infer the missing size in [${n}] when there are 0 elements`);
  if (e % t !== 0)
    throw Error(`The implicit shape can't be a fractional number. Got ${e} / ${t}`);
  const s = n.slice();
  return s[r] = e / t, s;
}
function Re(n, e) {
  const t = e.length;
  return n = n == null ? e.map((r, s) => s) : [].concat(n), O(n.every((r) => r >= -t && r < t), () => `All values in axis param must be in range [-${t}, ${t}) but got axis ${n}`), O(n.every((r) => Cr(r)), () => `All values in axis param must be integers but got axis ${n}`), n.map((r) => r < 0 ? t + r : r);
}
function jt(n, e) {
  const t = [], r = [];
  for (let s = 0; s < n.length; ++s)
    n[s] !== 1 && (t.push(n[s]), r.push(s));
  return { newShape: t, keptDims: r };
}
function Ut(n, e) {
  return de(n, e);
}
function de(n, e) {
  let t = null;
  if (n == null || n === "float32")
    t = new Float32Array(e);
  else if (n === "int32")
    t = new Int32Array(e);
  else if (n === "bool")
    t = new Uint8Array(e);
  else if (n === "string")
    t = new Array(e);
  else
    throw new Error(`Unknown data type ${n}`);
  return t;
}
function Pl(n, e) {
  for (let t = 0; t < n.length; t++) {
    const r = n[t];
    if (isNaN(r) || !isFinite(r))
      throw Error(`A tensor of type ${e} being uploaded contains ${r}.`);
  }
}
function _l(n) {
  return n === "bool" || n === "complex64" || n === "float32" || n === "int32" || n === "string";
}
function Bl(n, e) {
  return !(e === "complex64" || e === "float32" && n !== "complex64" || e === "int32" && n !== "float32" && n !== "complex64" || e === "bool" && n === "bool");
}
function br(n) {
  if (n === "float32" || n === "int32")
    return 4;
  if (n === "complex64")
    return 8;
  if (n === "bool")
    return 1;
  throw new Error(`Unknown dtype ${n}`);
}
function Ll(n) {
  if (n == null)
    return 0;
  let e = 0;
  return n.forEach((t) => e += t.length), e;
}
function Fr(n) {
  return typeof n == "string" || n instanceof String;
}
function Ml(n) {
  return typeof n == "boolean";
}
function Ul(n) {
  return typeof n == "number";
}
function Yn(n) {
  return Array.isArray(n) ? Yn(n[0]) : n instanceof Float32Array ? "float32" : n instanceof Int32Array || n instanceof Uint8Array || n instanceof Uint8ClampedArray ? "int32" : Ul(n) ? "float32" : Fr(n) ? "string" : Ml(n) ? "bool" : "float32";
}
function as(n) {
  return !!(n && n.constructor && n.call && n.apply);
}
function cs(n, e) {
  for (let t = e; t < n; ++t)
    if (n % t === 0)
      return t;
  return n;
}
function me(n) {
  const e = n.length;
  if (e < 2)
    return [];
  const t = new Array(e - 1);
  t[e - 2] = n[e - 1];
  for (let r = e - 3; r >= 0; --r)
    t[r] = t[r + 1] * n[r + 1];
  return t;
}
function Ii(n, e, t, r = !1) {
  const s = new Array();
  if (e.length === 1) {
    const o = e[0] * (r ? 2 : 1);
    for (let i = 0; i < o; i++)
      s[i] = t[n + i];
  } else {
    const o = e[0], i = e.slice(1), a = i.reduce((c, l) => c * l) * (r ? 2 : 1);
    for (let c = 0; c < o; c++)
      s[c] = Ii(n + c * a, i, t, r);
  }
  return s;
}
function Co(n, e, t = !1) {
  if (n.length === 0)
    return e[0];
  const r = n.reduce((s, o) => s * o) * (t ? 2 : 1);
  if (r === 0)
    return [];
  if (r !== e.length)
    throw new Error(`[${n}] does not match the input size ${e.length}${t ? " for a complex tensor" : ""}.`);
  return Ii(0, n, e, t);
}
function Vl(n, e) {
  const t = Rt(n, e);
  for (let r = 0; r < t.length; r++)
    t[r] = 1;
  return t;
}
function Rt(n, e) {
  if (e == null || e === "float32" || e === "complex64")
    return new Float32Array(n);
  if (e === "int32")
    return new Int32Array(n);
  if (e === "bool")
    return new Uint8Array(n);
  throw new Error(`Unknown data type ${e}`);
}
function Qn(n) {
  n.forEach((e) => {
    O(Number.isInteger(e) && e >= 0, () => `Tensor must have a shape comprised of positive integers but got shape [${n}].`);
  });
}
function ls(n, e, t) {
  if (e === 0)
    return 0;
  if (e === 1)
    return n[0];
  let r = n[n.length - 1];
  for (let s = 0; s < n.length - 1; ++s)
    r += t[s] * n[s];
  return r;
}
function Fs(n, e, t) {
  if (e === 0)
    return [];
  if (e === 1)
    return [n];
  const r = new Array(e);
  for (let s = 0; s < r.length - 1; ++s)
    r[s] = Math.floor(n / t[s]), n -= r[s] * t[s];
  return r[r.length - 1] = n, r;
}
function Ds(n) {
  return n && n.then && typeof n.then == "function";
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const bo = "tfjsflags";
class Wl {
  // tslint:disable-next-line: no-any
  constructor(e) {
    this.global = e, this.flags = {}, this.flagRegistry = {}, this.urlFlags = {}, this.getQueryParams = Gl, this.populateURLFlags();
  }
  setPlatform(e, t) {
    this.platform != null && (E().getBool("IS_TEST") || E().getBool("PROD") || console.warn(`Platform ${this.platformName} has already been set. Overwriting the platform with ${e}.`)), this.platformName = e, this.platform = t;
  }
  registerFlag(e, t, r) {
    if (this.flagRegistry[e] = { evaluationFn: t, setHook: r }, this.urlFlags[e] != null) {
      const s = this.urlFlags[e];
      E().getBool("IS_TEST") || E().getBool("PROD") || console.warn(`Setting feature override from URL ${e}: ${s}.`), this.set(e, s);
    }
  }
  async getAsync(e) {
    return e in this.flags ? this.flags[e] : (this.flags[e] = await this.evaluateFlag(e), this.flags[e]);
  }
  get(e) {
    if (e in this.flags)
      return this.flags[e];
    const t = this.evaluateFlag(e);
    if (Ds(t))
      throw new Error(`Flag ${e} cannot be synchronously evaluated. Please use getAsync() instead.`);
    return this.flags[e] = t, this.flags[e];
  }
  getNumber(e) {
    return this.get(e);
  }
  getBool(e) {
    return this.get(e);
  }
  getString(e) {
    return this.get(e);
  }
  getFlags() {
    return this.flags;
  }
  // For backwards compatibility.
  get features() {
    return this.flags;
  }
  set(e, t) {
    if (this.flagRegistry[e] == null)
      throw new Error(`Cannot set flag ${e} as it has not been registered.`);
    this.flags[e] = t, this.flagRegistry[e].setHook != null && this.flagRegistry[e].setHook(t);
  }
  evaluateFlag(e) {
    if (this.flagRegistry[e] == null)
      throw new Error(`Cannot evaluate flag '${e}': no evaluation function found.`);
    return this.flagRegistry[e].evaluationFn();
  }
  setFlags(e) {
    this.flags = Object.assign({}, e);
  }
  reset() {
    this.flags = {}, this.urlFlags = {}, this.populateURLFlags();
  }
  populateURLFlags() {
    if (typeof this.global > "u" || typeof this.global.location > "u" || typeof this.global.location.search > "u")
      return;
    const e = this.getQueryParams(this.global.location.search);
    bo in e && e[bo].split(",").forEach((r) => {
      const [s, o] = r.split(":");
      this.urlFlags[s] = Hl(s, o);
    });
  }
}
function Gl(n) {
  const e = {};
  return n.replace(/[?&]([^=?&]+)(?:=([^&]*))?/g, (t, ...r) => (zl(e, r[0], r[1]), r.join("="))), e;
}
function zl(n, e, t) {
  n[decodeURIComponent(e)] = decodeURIComponent(t || "");
}
function Hl(n, e) {
  const t = e.toLowerCase();
  return t === "true" || t === "false" ? t === "true" : `${+t}` === t ? +t : e;
}
function E() {
  return Si;
}
let Si = null;
function Xl(n) {
  Si = n;
}
const yo = globalThis || void 0 || self;
function jl(n) {
  return n && n.__esModule && Object.prototype.hasOwnProperty.call(n, "default") ? n.default : n;
}
var Ei = { exports: {} }, oe = Ei.exports = {}, st, ot;
function us() {
  throw new Error("setTimeout has not been defined");
}
function ds() {
  throw new Error("clearTimeout has not been defined");
}
(function() {
  try {
    typeof setTimeout == "function" ? st = setTimeout : st = us;
  } catch {
    st = us;
  }
  try {
    typeof clearTimeout == "function" ? ot = clearTimeout : ot = ds;
  } catch {
    ot = ds;
  }
})();
function Ri(n) {
  if (st === setTimeout)
    return setTimeout(n, 0);
  if ((st === us || !st) && setTimeout)
    return st = setTimeout, setTimeout(n, 0);
  try {
    return st(n, 0);
  } catch {
    try {
      return st.call(null, n, 0);
    } catch {
      return st.call(this, n, 0);
    }
  }
}
function ql(n) {
  if (ot === clearTimeout)
    return clearTimeout(n);
  if ((ot === ds || !ot) && clearTimeout)
    return ot = clearTimeout, clearTimeout(n);
  try {
    return ot(n);
  } catch {
    try {
      return ot.call(null, n);
    } catch {
      return ot.call(this, n);
    }
  }
}
var pt = [], hn = !1, Pt, mr = -1;
function Kl() {
  !hn || !Pt || (hn = !1, Pt.length ? pt = Pt.concat(pt) : mr = -1, pt.length && Ti());
}
function Ti() {
  if (!hn) {
    var n = Ri(Kl);
    hn = !0;
    for (var e = pt.length; e; ) {
      for (Pt = pt, pt = []; ++mr < e; )
        Pt && Pt[mr].run();
      mr = -1, e = pt.length;
    }
    Pt = null, hn = !1, ql(n);
  }
}
oe.nextTick = function(n) {
  var e = new Array(arguments.length - 1);
  if (arguments.length > 1)
    for (var t = 1; t < arguments.length; t++)
      e[t - 1] = arguments[t];
  pt.push(new Ni(n, e)), pt.length === 1 && !hn && Ri(Ti);
};
function Ni(n, e) {
  this.fun = n, this.array = e;
}
Ni.prototype.run = function() {
  this.fun.apply(null, this.array);
};
oe.title = "browser";
oe.browser = !0;
oe.env = {};
oe.argv = [];
oe.version = "";
oe.versions = {};
function mt() {
}
oe.on = mt;
oe.addListener = mt;
oe.once = mt;
oe.off = mt;
oe.removeListener = mt;
oe.removeAllListeners = mt;
oe.emit = mt;
oe.prependListener = mt;
oe.prependOnceListener = mt;
oe.listeners = function(n) {
  return [];
};
oe.binding = function(n) {
  throw new Error("process.binding is not supported");
};
oe.cwd = function() {
  return "/";
};
oe.chdir = function(n) {
  throw new Error("process.chdir is not supported");
};
oe.umask = function() {
  return 0;
};
var Yl = Ei.exports;
const fn = /* @__PURE__ */ jl(Yl);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
let qr;
function ki() {
  if (qr == null) {
    let n;
    if (typeof window < "u")
      n = window;
    else if (typeof yo < "u")
      n = yo;
    else if (typeof fn < "u")
      n = fn;
    else if (typeof self < "u")
      n = self;
    else
      throw new Error("Could not find a global object");
    qr = n;
  }
  return qr;
}
function Ql() {
  const n = ki();
  return n._tfGlobals == null && (n._tfGlobals = /* @__PURE__ */ new Map()), n._tfGlobals;
}
function Os(n, e) {
  const t = Ql();
  if (t.has(n))
    return t.get(n);
  {
    const r = e();
    return t.set(n, r), t.get(n);
  }
}
const Ai = "Abs", Zl = "Acos", Jl = "Acosh", Ps = "Add", eu = "AddN", tu = "All", nu = "Any", ru = "ArgMax", su = "ArgMin", ou = "Asin", iu = "Asinh", au = "Atan", cu = "Atanh", lu = "Atan2", uu = "AvgPool", du = "AvgPoolGrad", hu = "AvgPool3D", fu = "AvgPool3DGrad", pu = "BatchMatMul", mu = "BatchToSpaceND", gu = "Bincount", xu = "BitwiseAnd", wu = "BroadcastArgs", _s = "Cast", Cu = "Ceil", bu = "ClipByValue", Fi = "Complex", Di = "ComplexAbs", yu = "Concat", $u = "Conv2D", vu = "Conv2DBackpropFilter", Iu = "Conv2DBackpropInput", Su = "Conv3D", Eu = "Conv3DBackpropFilterV2", Ru = "Conv3DBackpropInputV2", Tu = "Cos", Nu = "Cosh", ku = "Cumprod", Au = "Cumsum", Fu = "CropAndResize", Du = "DenseBincount", Ou = "DepthToSpace", Pu = "DepthwiseConv2dNative", _u = "DepthwiseConv2dNativeBackpropFilter", Bu = "DepthwiseConv2dNativeBackpropInput", Lu = "Diag", Mu = "Dilation2D", Oi = "RealDiv", Uu = "Einsum", Pi = "Elu", Vu = "EluGrad", Wu = "Erf", Gu = "Equal", zu = "Exp", Hu = "ExpandDims", Xu = "Expm1", ju = "FFT", _i = "Fill", qu = "FlipLeftRight", Ku = "Floor", Bi = "FloorDiv", Yu = "FusedBatchNorm", Qu = "GatherV2", Zu = "GatherNd", Ju = "Greater", ed = "GreaterEqual", Bs = "Identity", td = "IFFT", nd = "Imag", rd = "IsFinite", sd = "IsInf", od = "IsNan", Li = "LeakyRelu", id = "Less", ad = "LessEqual", cd = "LinSpace", ld = "Log", ud = "Log1p", dd = "LogicalAnd", hd = "LogicalNot", fd = "LogicalOr", pd = "LRN", md = "LRNGrad", gd = "Max", Mi = "Maximum", xd = "MaxPool", wd = "MaxPoolGrad", Cd = "MaxPool3D", bd = "MaxPool3DGrad", yd = "MaxPoolWithArgmax", $d = "Mean", vd = "Min", Id = "Minimum", Sd = "MirrorPad", Ed = "Mod", Rd = "Multinomial", Ui = "Multiply", Td = "Neg", Nd = "NotEqual", kd = "NonMaxSuppressionV3", Ad = "NonMaxSuppressionV4", Fd = "NonMaxSuppressionV5", Dd = "OnesLike", Od = "OneHot", Pd = "Pack", _d = "PadV2", Vi = "Pow", Wi = "Prelu", Bd = "Prod", Ld = "RaggedGather", Md = "RaggedRange", Ud = "RaggedTensorToTensor", Vd = "Range", Wd = "Real", Gd = "Reciprocal", Gi = "Relu", zi = "Reshape", zd = "ResizeNearestNeighbor", Hd = "ResizeNearestNeighborGrad", Xd = "ResizeBilinear", jd = "ResizeBilinearGrad", Hi = "Relu6", qd = "Reverse", Kd = "Round", Yd = "Rsqrt", Qd = "ScatterNd", Zd = "TensorScatterUpdate", Jd = "SearchSorted", eh = "Select", th = "Selu", nh = "Slice", rh = "Sin", sh = "Sinh", oh = "Sign", Xi = "Sigmoid", ih = "Softplus", ji = "Sqrt", qi = "Sum", ah = "SpaceToBatchND", ch = "SplitV", lh = "Softmax", uh = "SparseFillEmptyRows", dh = "SparseReshape", hh = "SparseSegmentMean", fh = "SparseSegmentSum", ph = "SparseToDense", mh = "SquaredDifference", gh = "Square", xh = "StaticRegexReplace", wh = "StridedSlice", Ch = "StringNGrams", bh = "StringSplit", yh = "StringToHashBucketFast", Ki = "Sub", $h = "Tan", vh = "Tanh", Yi = "Tile", Ih = "TopK", Sh = "Transform", Eh = "Transpose", Rh = "Unique", Th = "Unpack", Nh = "UnsortedSegmentSum", Qi = "ZerosLike", Zi = "Step", kh = "FromPixels", Ah = "RotateWithOffset", Fh = "_FusedMatMul", Dh = "FusedConv2D", Oh = "FusedDepthwiseConv2D";
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Qe(...n) {
  E().getBool("IS_TEST") || E().getBool("PROD") || console.warn(...n);
}
function Ph(...n) {
  E().getBool("IS_TEST") || E().getBool("PROD") || console.log(...n);
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const yr = Os("kernelRegistry", () => /* @__PURE__ */ new Map()), _h = Os("gradRegistry", () => /* @__PURE__ */ new Map());
function $o(n, e) {
  const t = Ji(n, e);
  return yr.get(t);
}
function vo(n) {
  return _h.get(n);
}
function Io(n) {
  const e = yr.entries(), t = [];
  for (; ; ) {
    const { done: r, value: s } = e.next();
    if (r)
      break;
    const [o, i] = s, [a] = o.split("_");
    a === n && t.push(i);
  }
  return t;
}
function Bh(n) {
  const { kernelName: e, backendName: t } = n, r = Ji(e, t);
  yr.has(r) && Qe(`The kernel '${e}' for backend '${t}' is already registered`), yr.set(r, n);
}
function Ji(n, e) {
  return `${e}_${n}`;
}
/**
 * @license
 * Copyright 2023 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function ea(n) {
  return n instanceof Float32Array || n instanceof Int32Array || n instanceof Uint8Array || n instanceof Uint8ClampedArray;
}
function Lh(n) {
  return n && n.__esModule && Object.prototype.hasOwnProperty.call(n, "default") ? n.default : n;
}
var ta = Z, Ue = null;
try {
  Ue = new WebAssembly.Instance(new WebAssembly.Module(new Uint8Array([
    0,
    97,
    115,
    109,
    1,
    0,
    0,
    0,
    1,
    13,
    2,
    96,
    0,
    1,
    127,
    96,
    4,
    127,
    127,
    127,
    127,
    1,
    127,
    3,
    7,
    6,
    0,
    1,
    1,
    1,
    1,
    1,
    6,
    6,
    1,
    127,
    1,
    65,
    0,
    11,
    7,
    50,
    6,
    3,
    109,
    117,
    108,
    0,
    1,
    5,
    100,
    105,
    118,
    95,
    115,
    0,
    2,
    5,
    100,
    105,
    118,
    95,
    117,
    0,
    3,
    5,
    114,
    101,
    109,
    95,
    115,
    0,
    4,
    5,
    114,
    101,
    109,
    95,
    117,
    0,
    5,
    8,
    103,
    101,
    116,
    95,
    104,
    105,
    103,
    104,
    0,
    0,
    10,
    191,
    1,
    6,
    4,
    0,
    35,
    0,
    11,
    36,
    1,
    1,
    126,
    32,
    0,
    173,
    32,
    1,
    173,
    66,
    32,
    134,
    132,
    32,
    2,
    173,
    32,
    3,
    173,
    66,
    32,
    134,
    132,
    126,
    34,
    4,
    66,
    32,
    135,
    167,
    36,
    0,
    32,
    4,
    167,
    11,
    36,
    1,
    1,
    126,
    32,
    0,
    173,
    32,
    1,
    173,
    66,
    32,
    134,
    132,
    32,
    2,
    173,
    32,
    3,
    173,
    66,
    32,
    134,
    132,
    127,
    34,
    4,
    66,
    32,
    135,
    167,
    36,
    0,
    32,
    4,
    167,
    11,
    36,
    1,
    1,
    126,
    32,
    0,
    173,
    32,
    1,
    173,
    66,
    32,
    134,
    132,
    32,
    2,
    173,
    32,
    3,
    173,
    66,
    32,
    134,
    132,
    128,
    34,
    4,
    66,
    32,
    135,
    167,
    36,
    0,
    32,
    4,
    167,
    11,
    36,
    1,
    1,
    126,
    32,
    0,
    173,
    32,
    1,
    173,
    66,
    32,
    134,
    132,
    32,
    2,
    173,
    32,
    3,
    173,
    66,
    32,
    134,
    132,
    129,
    34,
    4,
    66,
    32,
    135,
    167,
    36,
    0,
    32,
    4,
    167,
    11,
    36,
    1,
    1,
    126,
    32,
    0,
    173,
    32,
    1,
    173,
    66,
    32,
    134,
    132,
    32,
    2,
    173,
    32,
    3,
    173,
    66,
    32,
    134,
    132,
    130,
    34,
    4,
    66,
    32,
    135,
    167,
    36,
    0,
    32,
    4,
    167,
    11
  ])), {}).exports;
} catch {
}
function Z(n, e, t) {
  this.low = n | 0, this.high = e | 0, this.unsigned = !!t;
}
Z.prototype.__isLong__;
Object.defineProperty(Z.prototype, "__isLong__", { value: !0 });
function Oe(n) {
  return (n && n.__isLong__) === !0;
}
Z.isLong = Oe;
var So = {}, Eo = {};
function qt(n, e) {
  var t, r, s;
  return e ? (n >>>= 0, (s = 0 <= n && n < 256) && (r = Eo[n], r) ? r : (t = J(n, (n | 0) < 0 ? -1 : 0, !0), s && (Eo[n] = t), t)) : (n |= 0, (s = -128 <= n && n < 128) && (r = So[n], r) ? r : (t = J(n, n < 0 ? -1 : 0, !1), s && (So[n] = t), t));
}
Z.fromInt = qt;
function Ve(n, e) {
  if (isNaN(n))
    return e ? _t : We;
  if (e) {
    if (n < 0)
      return _t;
    if (n >= na)
      return oa;
  } else {
    if (n <= -To)
      return Fe;
    if (n + 1 >= To)
      return sa;
  }
  return n < 0 ? Ve(-n, e).neg() : J(n % gn | 0, n / gn | 0, e);
}
Z.fromNumber = Ve;
function J(n, e, t) {
  return new Z(n, e, t);
}
Z.fromBits = J;
var $r = Math.pow;
function Ls(n, e, t) {
  if (n.length === 0)
    throw Error("empty string");
  if (n === "NaN" || n === "Infinity" || n === "+Infinity" || n === "-Infinity")
    return We;
  if (typeof e == "number" ? (t = e, e = !1) : e = !!e, t = t || 10, t < 2 || 36 < t)
    throw RangeError("radix");
  var r;
  if ((r = n.indexOf("-")) > 0)
    throw Error("interior hyphen");
  if (r === 0)
    return Ls(n.substring(1), e, t).neg();
  for (var s = Ve($r(t, 8)), o = We, i = 0; i < n.length; i += 8) {
    var a = Math.min(8, n.length - i), c = parseInt(n.substring(i, i + a), t);
    if (a < 8) {
      var l = Ve($r(t, a));
      o = o.mul(l).add(Ve(c));
    } else
      o = o.mul(s), o = o.add(Ve(c));
  }
  return o.unsigned = e, o;
}
Z.fromString = Ls;
function Je(n, e) {
  return typeof n == "number" ? Ve(n, e) : typeof n == "string" ? Ls(n, e) : J(n.low, n.high, typeof e == "boolean" ? e : n.unsigned);
}
Z.fromValue = Je;
var Ro = 65536, Mh = 1 << 24, gn = Ro * Ro, na = gn * gn, To = na / 2, No = qt(Mh), We = qt(0);
Z.ZERO = We;
var _t = qt(0, !0);
Z.UZERO = _t;
var un = qt(1);
Z.ONE = un;
var ra = qt(1, !0);
Z.UONE = ra;
var hs = qt(-1);
Z.NEG_ONE = hs;
var sa = J(-1, 2147483647, !1);
Z.MAX_VALUE = sa;
var oa = J(-1, -1, !0);
Z.MAX_UNSIGNED_VALUE = oa;
var Fe = J(0, -2147483648, !1);
Z.MIN_VALUE = Fe;
var P = Z.prototype;
P.toInt = function() {
  return this.unsigned ? this.low >>> 0 : this.low;
};
P.toNumber = function() {
  return this.unsigned ? (this.high >>> 0) * gn + (this.low >>> 0) : this.high * gn + (this.low >>> 0);
};
P.toString = function(e) {
  if (e = e || 10, e < 2 || 36 < e)
    throw RangeError("radix");
  if (this.isZero())
    return "0";
  if (this.isNegative())
    if (this.eq(Fe)) {
      var t = Ve(e), r = this.div(t), s = r.mul(t).sub(this);
      return r.toString(e) + s.toInt().toString(e);
    } else
      return "-" + this.neg().toString(e);
  for (var o = Ve($r(e, 6), this.unsigned), i = this, a = ""; ; ) {
    var c = i.div(o), l = i.sub(c.mul(o)).toInt() >>> 0, u = l.toString(e);
    if (i = c, i.isZero())
      return u + a;
    for (; u.length < 6; )
      u = "0" + u;
    a = "" + u + a;
  }
};
P.getHighBits = function() {
  return this.high;
};
P.getHighBitsUnsigned = function() {
  return this.high >>> 0;
};
P.getLowBits = function() {
  return this.low;
};
P.getLowBitsUnsigned = function() {
  return this.low >>> 0;
};
P.getNumBitsAbs = function() {
  if (this.isNegative())
    return this.eq(Fe) ? 64 : this.neg().getNumBitsAbs();
  for (var e = this.high != 0 ? this.high : this.low, t = 31; t > 0 && !(e & 1 << t); t--)
    ;
  return this.high != 0 ? t + 33 : t + 1;
};
P.isZero = function() {
  return this.high === 0 && this.low === 0;
};
P.eqz = P.isZero;
P.isNegative = function() {
  return !this.unsigned && this.high < 0;
};
P.isPositive = function() {
  return this.unsigned || this.high >= 0;
};
P.isOdd = function() {
  return (this.low & 1) === 1;
};
P.isEven = function() {
  return (this.low & 1) === 0;
};
P.equals = function(e) {
  return Oe(e) || (e = Je(e)), this.unsigned !== e.unsigned && this.high >>> 31 === 1 && e.high >>> 31 === 1 ? !1 : this.high === e.high && this.low === e.low;
};
P.eq = P.equals;
P.notEquals = function(e) {
  return !this.eq(
    /* validates */
    e
  );
};
P.neq = P.notEquals;
P.ne = P.notEquals;
P.lessThan = function(e) {
  return this.comp(
    /* validates */
    e
  ) < 0;
};
P.lt = P.lessThan;
P.lessThanOrEqual = function(e) {
  return this.comp(
    /* validates */
    e
  ) <= 0;
};
P.lte = P.lessThanOrEqual;
P.le = P.lessThanOrEqual;
P.greaterThan = function(e) {
  return this.comp(
    /* validates */
    e
  ) > 0;
};
P.gt = P.greaterThan;
P.greaterThanOrEqual = function(e) {
  return this.comp(
    /* validates */
    e
  ) >= 0;
};
P.gte = P.greaterThanOrEqual;
P.ge = P.greaterThanOrEqual;
P.compare = function(e) {
  if (Oe(e) || (e = Je(e)), this.eq(e))
    return 0;
  var t = this.isNegative(), r = e.isNegative();
  return t && !r ? -1 : !t && r ? 1 : this.unsigned ? e.high >>> 0 > this.high >>> 0 || e.high === this.high && e.low >>> 0 > this.low >>> 0 ? -1 : 1 : this.sub(e).isNegative() ? -1 : 1;
};
P.comp = P.compare;
P.negate = function() {
  return !this.unsigned && this.eq(Fe) ? Fe : this.not().add(un);
};
P.neg = P.negate;
P.add = function(e) {
  Oe(e) || (e = Je(e));
  var t = this.high >>> 16, r = this.high & 65535, s = this.low >>> 16, o = this.low & 65535, i = e.high >>> 16, a = e.high & 65535, c = e.low >>> 16, l = e.low & 65535, u = 0, d = 0, h = 0, f = 0;
  return f += o + l, h += f >>> 16, f &= 65535, h += s + c, d += h >>> 16, h &= 65535, d += r + a, u += d >>> 16, d &= 65535, u += t + i, u &= 65535, J(h << 16 | f, u << 16 | d, this.unsigned);
};
P.subtract = function(e) {
  return Oe(e) || (e = Je(e)), this.add(e.neg());
};
P.sub = P.subtract;
P.multiply = function(e) {
  if (this.isZero())
    return We;
  if (Oe(e) || (e = Je(e)), Ue) {
    var t = Ue.mul(
      this.low,
      this.high,
      e.low,
      e.high
    );
    return J(t, Ue.get_high(), this.unsigned);
  }
  if (e.isZero())
    return We;
  if (this.eq(Fe))
    return e.isOdd() ? Fe : We;
  if (e.eq(Fe))
    return this.isOdd() ? Fe : We;
  if (this.isNegative())
    return e.isNegative() ? this.neg().mul(e.neg()) : this.neg().mul(e).neg();
  if (e.isNegative())
    return this.mul(e.neg()).neg();
  if (this.lt(No) && e.lt(No))
    return Ve(this.toNumber() * e.toNumber(), this.unsigned);
  var r = this.high >>> 16, s = this.high & 65535, o = this.low >>> 16, i = this.low & 65535, a = e.high >>> 16, c = e.high & 65535, l = e.low >>> 16, u = e.low & 65535, d = 0, h = 0, f = 0, m = 0;
  return m += i * u, f += m >>> 16, m &= 65535, f += o * u, h += f >>> 16, f &= 65535, f += i * l, h += f >>> 16, f &= 65535, h += s * u, d += h >>> 16, h &= 65535, h += o * l, d += h >>> 16, h &= 65535, h += i * c, d += h >>> 16, h &= 65535, d += r * u + s * l + o * c + i * a, d &= 65535, J(f << 16 | m, d << 16 | h, this.unsigned);
};
P.mul = P.multiply;
P.divide = function(e) {
  if (Oe(e) || (e = Je(e)), e.isZero())
    throw Error("division by zero");
  if (Ue) {
    if (!this.unsigned && this.high === -2147483648 && e.low === -1 && e.high === -1)
      return this;
    var t = (this.unsigned ? Ue.div_u : Ue.div_s)(
      this.low,
      this.high,
      e.low,
      e.high
    );
    return J(t, Ue.get_high(), this.unsigned);
  }
  if (this.isZero())
    return this.unsigned ? _t : We;
  var r, s, o;
  if (this.unsigned) {
    if (e.unsigned || (e = e.toUnsigned()), e.gt(this))
      return _t;
    if (e.gt(this.shru(1)))
      return ra;
    o = _t;
  } else {
    if (this.eq(Fe)) {
      if (e.eq(un) || e.eq(hs))
        return Fe;
      if (e.eq(Fe))
        return un;
      var i = this.shr(1);
      return r = i.div(e).shl(1), r.eq(We) ? e.isNegative() ? un : hs : (s = this.sub(e.mul(r)), o = r.add(s.div(e)), o);
    } else if (e.eq(Fe))
      return this.unsigned ? _t : We;
    if (this.isNegative())
      return e.isNegative() ? this.neg().div(e.neg()) : this.neg().div(e).neg();
    if (e.isNegative())
      return this.div(e.neg()).neg();
    o = We;
  }
  for (s = this; s.gte(e); ) {
    r = Math.max(1, Math.floor(s.toNumber() / e.toNumber()));
    for (var a = Math.ceil(Math.log(r) / Math.LN2), c = a <= 48 ? 1 : $r(2, a - 48), l = Ve(r), u = l.mul(e); u.isNegative() || u.gt(s); )
      r -= c, l = Ve(r, this.unsigned), u = l.mul(e);
    l.isZero() && (l = un), o = o.add(l), s = s.sub(u);
  }
  return o;
};
P.div = P.divide;
P.modulo = function(e) {
  if (Oe(e) || (e = Je(e)), Ue) {
    var t = (this.unsigned ? Ue.rem_u : Ue.rem_s)(
      this.low,
      this.high,
      e.low,
      e.high
    );
    return J(t, Ue.get_high(), this.unsigned);
  }
  return this.sub(this.div(e).mul(e));
};
P.mod = P.modulo;
P.rem = P.modulo;
P.not = function() {
  return J(~this.low, ~this.high, this.unsigned);
};
P.and = function(e) {
  return Oe(e) || (e = Je(e)), J(this.low & e.low, this.high & e.high, this.unsigned);
};
P.or = function(e) {
  return Oe(e) || (e = Je(e)), J(this.low | e.low, this.high | e.high, this.unsigned);
};
P.xor = function(e) {
  return Oe(e) || (e = Je(e)), J(this.low ^ e.low, this.high ^ e.high, this.unsigned);
};
P.shiftLeft = function(e) {
  return Oe(e) && (e = e.toInt()), (e &= 63) === 0 ? this : e < 32 ? J(this.low << e, this.high << e | this.low >>> 32 - e, this.unsigned) : J(0, this.low << e - 32, this.unsigned);
};
P.shl = P.shiftLeft;
P.shiftRight = function(e) {
  return Oe(e) && (e = e.toInt()), (e &= 63) === 0 ? this : e < 32 ? J(this.low >>> e | this.high << 32 - e, this.high >> e, this.unsigned) : J(this.high >> e - 32, this.high >= 0 ? 0 : -1, this.unsigned);
};
P.shr = P.shiftRight;
P.shiftRightUnsigned = function(e) {
  if (Oe(e) && (e = e.toInt()), e &= 63, e === 0)
    return this;
  var t = this.high;
  if (e < 32) {
    var r = this.low;
    return J(r >>> e | t << 32 - e, t >>> e, this.unsigned);
  } else return e === 32 ? J(t, 0, this.unsigned) : J(t >>> e - 32, 0, this.unsigned);
};
P.shru = P.shiftRightUnsigned;
P.shr_u = P.shiftRightUnsigned;
P.toSigned = function() {
  return this.unsigned ? J(this.low, this.high, !1) : this;
};
P.toUnsigned = function() {
  return this.unsigned ? this : J(this.low, this.high, !0);
};
P.toBytes = function(e) {
  return e ? this.toBytesLE() : this.toBytesBE();
};
P.toBytesLE = function() {
  var e = this.high, t = this.low;
  return [
    t & 255,
    t >>> 8 & 255,
    t >>> 16 & 255,
    t >>> 24,
    e & 255,
    e >>> 8 & 255,
    e >>> 16 & 255,
    e >>> 24
  ];
};
P.toBytesBE = function() {
  var e = this.high, t = this.low;
  return [
    e >>> 24,
    e >>> 16 & 255,
    e >>> 8 & 255,
    e & 255,
    t >>> 24,
    t >>> 16 & 255,
    t >>> 8 & 255,
    t & 255
  ];
};
Z.fromBytes = function(e, t, r) {
  return r ? Z.fromBytesLE(e, t) : Z.fromBytesBE(e, t);
};
Z.fromBytesLE = function(e, t) {
  return new Z(
    e[0] | e[1] << 8 | e[2] << 16 | e[3] << 24,
    e[4] | e[5] << 8 | e[6] << 16 | e[7] << 24,
    t
  );
};
Z.fromBytesBE = function(e, t) {
  return new Z(
    e[4] << 24 | e[5] << 16 | e[6] << 8 | e[7],
    e[0] << 24 | e[1] << 16 | e[2] << 8 | e[3],
    t
  );
};
const ia = /* @__PURE__ */ Lh(ta), Uh = /* @__PURE__ */ Nl({
  __proto__: null,
  default: ia
}, [ta]);
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Ft = (
  // tslint:disable-next-line
  ia || Uh
);
function Dr(n) {
  return Ft.fromString(n, !0, 16);
}
const aa = Dr("c3a5c85c97cb3127"), At = Dr("b492b66fbe98f273"), ye = Dr("9ae16a3b2f90404f");
function fs(n) {
  return n.xor(n.shru(47));
}
function ca(n, e, t) {
  const r = n.slice(e, e + t);
  return Ft.fromBytes(Array.from(r), !0, !0);
}
function Q(n, e) {
  return ca(n, e, 8);
}
function ko(n, e) {
  return ca(n, e, 4);
}
function ue(n, e) {
  return e === 0 ? n : n.shru(e).or(n.shl(64 - e));
}
function Et(n, e, t = Dr("9ddfea08eb382d69")) {
  let r = n.xor(e).mul(t);
  r = r.xor(r.shru(47));
  let s = e.xor(r).mul(t);
  return s = s.xor(s.shru(47)), s = s.mul(t), s;
}
function Vh(n, e, t, r, s, o) {
  s = s.add(n), o = ue(o.add(s).add(r), 21);
  const i = s;
  return s = s.add(e), s = s.add(t), o = o.add(ue(s, 44)), [s.add(r), o.add(i)];
}
function ir(n, e, t, r) {
  return Vh(Q(n, e), Q(n, e + 8), Q(n, e + 16), Q(n, e + 24), t, r);
}
function Wh(n, e = n.length) {
  if (e >= 8) {
    const t = ye.add(e * 2), r = Q(n, 0).add(ye), s = Q(n, e - 8), o = ue(s, 37).mul(t).add(r), i = ue(r, 25).add(s).mul(t);
    return Et(o, i, t);
  }
  if (e >= 4) {
    const t = ye.add(e * 2), r = ko(n, 0);
    return Et(r.shl(3).add(e), ko(n, e - 4), t);
  }
  if (e > 0) {
    const t = n[0], r = n[e >> 1], s = n[e - 1], o = t + (r << 8), i = e + (s << 2);
    return fs(ye.mul(o).xor(aa.mul(i))).mul(ye);
  }
  return ye;
}
function Gh(n, e = n.length) {
  const t = ye.add(e * 2), r = Q(n, 0).mul(At), s = Q(n, 8), o = Q(n, e - 8).mul(t), i = Q(n, e - 16).mul(ye);
  return Et(ue(r.add(s), 43).add(ue(o, 30)).add(i), r.add(ue(s.add(ye), 18)).add(o), t);
}
function zh(n, e = n.length) {
  const t = ye.add(e * 2), r = Q(n, 0).mul(ye), s = Q(n, 8), o = Q(n, e - 8).mul(t), i = Q(n, e - 16).mul(ye), a = ue(r.add(s), 43).add(ue(o, 30)).add(i), c = Et(a, r.add(ue(s.add(ye), 18)).add(o), t), l = Q(n, 16).mul(t), u = Q(n, 24), d = a.add(Q(n, e - 32)).mul(t), h = c.add(Q(n, e - 24)).mul(t);
  return Et(ue(l.add(u), 43).add(ue(d, 30)).add(h), l.add(ue(u.add(r), 18)).add(d), t);
}
function Hh(n, e = n.length) {
  const t = Ft.fromNumber(81, !0);
  if (e <= 32)
    return e <= 16 ? Wh(n, e) : Gh(n, e);
  if (e <= 64)
    return zh(n, e);
  let r = t, s = t.mul(At).add(113), o = fs(s.mul(ye).add(113)).mul(ye), i = [Ft.UZERO, Ft.UZERO], a = [Ft.UZERO, Ft.UZERO];
  r = r.mul(ye).add(Q(n, 0));
  let c = 0;
  const l = (e - 1 >> 6) * 64, u = l + (e - 1 & 63) - 63;
  do
    r = ue(r.add(s).add(i[0]).add(Q(n, c + 8)), 37).mul(At), s = ue(s.add(i[1]).add(Q(n, c + 48)), 42).mul(At), r = r.xor(a[1]), s = s.add(i[0]).add(Q(n, c + 40)), o = ue(o.add(a[0]), 33).mul(At), i = ir(n, c, i[1].mul(At), r.add(a[0])), a = ir(n, c + 32, o.add(a[1]), s.add(Q(n, c + 16))), [o, r] = [r, o], c += 64;
  while (c !== l);
  const d = At.add(o.and(255).shl(1));
  return c = u, a[0] = a[0].add(e - 1 & 63), i[0] = i[0].add(a[0]), a[0] = a[0].add(i[0]), r = ue(r.add(s).add(i[0]).add(Q(n, c + 8)), 37).mul(d), s = ue(s.add(i[1]).add(Q(n, c + 48)), 42).mul(d), r = r.xor(a[1].mul(9)), s = s.add(i[0].mul(9).add(Q(n, c + 40))), o = ue(o.add(a[0]), 33).mul(d), i = ir(n, c, i[1].mul(d), r.add(a[0])), a = ir(n, c + 32, o.add(a[1]), s.add(Q(n, c + 16))), [o, r] = [r, o], Et(Et(i[0], a[0], d).add(fs(s).mul(aa)).add(o), Et(i[1], a[1], d).add(r), d);
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function vn(n, e) {
  return e === "string" ? Lt(n) : Or([n], e);
}
function Xh(n, e) {
  return n instanceof Float32Array && e === "float32" || n instanceof Int32Array && e === "int32" || n instanceof Uint8Array && e === "bool";
}
function Or(n, e) {
  if (e === "string")
    throw new Error("Cannot convert a string[] to a TypedArray");
  if (Array.isArray(n) && (n = Vt(n)), E().getBool("DEBUG") && Pl(n, e), Xh(n, e))
    return n;
  if (e == null || e === "float32" || e === "complex64")
    return new Float32Array(n);
  if (e === "int32")
    return new Int32Array(n);
  if (e === "bool") {
    const t = new Uint8Array(n.length);
    for (let r = 0; r < t.length; ++r)
      Math.round(n[r]) !== 0 && (t[r] = 1);
    return t;
  } else
    throw new Error(`Unknown data type ${e}`);
}
function qe() {
  return E().platform.now();
}
function Lt(n, e = "utf-8") {
  return e = e || "utf-8", E().platform.encode(n, e);
}
function xn(n, e = "utf-8") {
  return e = e || "utf-8", E().platform.decode(n, e);
}
function ze(n) {
  return E().platform.isTypedArray != null ? E().platform.isTypedArray(n) : ea(n);
}
function Vt(n, e = [], t = !1) {
  if (e == null && (e = []), typeof n == "boolean" || typeof n == "number" || typeof n == "string" || Ds(n) || n == null || ze(n) && t)
    e.push(n);
  else if (Array.isArray(n) || ze(n))
    for (let r = 0; r < n.length; ++r)
      Vt(n[r], e, t);
  else {
    let r = -1;
    for (const s of Object.keys(n))
      /^([1-9]+[0-9]*|0)$/.test(s) && (r = Math.max(r, Number(s)));
    for (let s = 0; s <= r; s++)
      Vt(n[s], e, t);
  }
  return e;
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class jh {
  constructor(e, t) {
    this.backendTimer = e, this.logger = t, t == null && (this.logger = new Kh());
  }
  profileKernel(e, t, r) {
    let s;
    const o = () => {
      s = r();
    };
    let i;
    const a = qe();
    if (this.backendTimer.timerAvailable())
      i = this.backendTimer.time(o);
    else {
      o();
      for (const l of s)
        l.dataSync();
      i = Promise.resolve({ kernelMs: qe() - a });
    }
    if (E().getBool("CHECK_COMPUTATION_FOR_ERRORS"))
      for (let l = 0; l < s.length; l++) {
        const u = s[l];
        u.data().then((d) => {
          qh(d, u.dtype, e);
        });
      }
    return {
      kernelName: e,
      outputs: s,
      inputs: t,
      timeMs: i.then((l) => l.kernelMs),
      extraInfo: i.then((l) => l.getExtraProfileInfo != null ? l.getExtraProfileInfo() : "")
    };
  }
  logKernelProfile(e) {
    const { kernelName: t, outputs: r, timeMs: s, inputs: o, extraInfo: i } = e;
    r.forEach((a) => {
      Promise.all([a.data(), s, i]).then((c) => {
        this.logger.logKernelProfile(t, a, c[0], c[1], o, c[2]);
      });
    });
  }
}
function qh(n, e, t) {
  if (e !== "float32")
    return !1;
  for (let r = 0; r < n.length; r++) {
    const s = n[r];
    if (isNaN(s) || !isFinite(s))
      return console.warn(`Found ${s} in the result of '${t}'`), !0;
  }
  return !1;
}
class Kh {
  logKernelProfile(e, t, r, s, o, i) {
    const a = typeof s == "number" ? dn(`${s}ms`, 9) : s.error, c = dn(e, 25), l = t.rank, u = t.size, d = dn(t.shape.toString(), 14);
    let h = "";
    for (const f in o) {
      const m = o[f];
      if (m != null) {
        const C = m.shape || t.shape, w = C.length;
        h += `${f}: ${w}D ${w > 0 ? C : ""} `;
      }
    }
    console.log(`%c${c}	%c${a}	%c${l}D ${d}	%c${u}	%c${h}	%c${i}`, "font-weight:bold", "color:red", "color:blue", "color: orange", "color: green", "color: steelblue");
  }
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Yh(n, e, t) {
  const r = {}, s = {};
  for (let c = 0; c < e.length; c++)
    r[e[c].id] = !0;
  for (let c = 0; c < n.length; c++) {
    const l = n[c], u = l.inputs;
    for (const d in u) {
      const h = u[d];
      let f = !1;
      for (let m = 0; m < e.length; m++)
        if (r[h.id]) {
          l.outputs.forEach((C) => r[C.id] = !0), f = !0, s[l.id] = !0;
          break;
        }
      if (f)
        break;
    }
  }
  const o = {};
  o[t.id] = !0;
  const i = {};
  for (let c = n.length - 1; c >= 0; c--) {
    const l = n[c], u = l.inputs;
    for (let d = 0; d < l.outputs.length; d++)
      if (o[l.outputs[d].id]) {
        for (const h in u)
          o[u[h].id] = !0, i[l.id] = !0;
        break;
      }
  }
  const a = [];
  for (let c = 0; c < n.length; c++) {
    const l = n[c];
    if (s[l.id] && i[l.id]) {
      const u = {};
      for (const h in l.inputs) {
        const f = l.inputs[h];
        r[f.id] && (u[h] = f);
      }
      const d = Object.assign({}, l);
      d.inputs = u, d.outputs = l.outputs, a.push(d);
    }
  }
  return a;
}
function Qh(n, e, t, r) {
  for (let s = e.length - 1; s >= 0; s--) {
    const o = e[s], i = [];
    if (o.outputs.forEach((c) => {
      const l = n[c.id];
      l != null ? i.push(l) : i.push(null);
    }), o.gradient == null)
      throw new Error(`Cannot compute gradient: gradient function not found for ${o.kernelName}.`);
    const a = o.gradient(i);
    for (const c in o.inputs) {
      if (!(c in a))
        throw new Error(`Cannot backprop through input ${c}. Available gradients found: ${Object.keys(a)}.`);
      const l = t(() => a[c]());
      if (l.dtype !== "float32")
        throw new Error(`Error in gradient for op ${o.kernelName}. The gradient of input ${c} must have 'float32' dtype, but has '${l.dtype}'`);
      const u = o.inputs[c];
      if (!ge(l.shape, u.shape))
        throw new Error(`Error in gradient for op ${o.kernelName}. The gradient of input '${c}' has shape '${l.shape}', which does not match the shape of the input '${u.shape}'`);
      if (n[u.id] == null)
        n[u.id] = l;
      else {
        const d = n[u.id];
        n[u.id] = r(d, l), d.dispose();
      }
    }
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Ao = 20, Mn = 3, Kr = 7;
function Zh(n, e, t, r) {
  const s = me(e), o = Jh(n, e, t, s), i = e.length, a = gr(n, e, t, s, o), c = ["Tensor"];
  return r && (c.push(`  dtype: ${t}`), c.push(`  rank: ${i}`), c.push(`  shape: [${e}]`), c.push("  values:")), c.push(a.map((l) => "    " + l).join(`
`)), c.join(`
`);
}
function Jh(n, e, t, r) {
  const s = _(e), o = r[r.length - 1], i = new Array(o).fill(0), a = e.length, c = t === "complex64" ? Vn(n) : n;
  if (a > 1)
    for (let l = 0; l < s / o; l++) {
      const u = l * o;
      for (let d = 0; d < o; d++)
        i[d] = Math.max(i[d], Un(c[u + d], 0, t).length);
    }
  return i;
}
function Un(n, e, t) {
  let r;
  return Array.isArray(n) ? r = `${parseFloat(n[0].toFixed(Kr))} + ${parseFloat(n[1].toFixed(Kr))}j` : Fr(n) ? r = `'${n}'` : t === "bool" ? r = la(n) : r = parseFloat(n.toFixed(Kr)).toString(), dn(r, e);
}
function la(n) {
  return n === 0 ? "false" : "true";
}
function gr(n, e, t, r, s, o = !0) {
  const i = t === "complex64" ? 2 : 1, a = e[0], c = e.length;
  if (c === 0) {
    if (t === "complex64") {
      const C = Vn(n);
      return [Un(C[0], 0, t)];
    }
    return t === "bool" ? [la(n[0])] : [n[0].toString()];
  }
  if (c === 1) {
    if (a > Ao) {
      const w = Mn * i;
      let x = Array.from(n.slice(0, w)), y = Array.from(n.slice((a - Mn) * i, a * i));
      return t === "complex64" && (x = Vn(x), y = Vn(y)), [
        "[" + x.map((v, I) => Un(v, s[I], t)).join(", ") + ", ..., " + y.map((v, I) => Un(v, s[a - Mn + I], t)).join(", ") + "]"
      ];
    }
    return [
      "[" + (t === "complex64" ? Vn(n) : Array.from(n)).map((w, x) => Un(w, s[x], t)).join(", ") + "]"
    ];
  }
  const l = e.slice(1), u = r.slice(1), d = r[0] * i, h = [];
  if (a > Ao) {
    for (let C = 0; C < Mn; C++) {
      const w = C * d, x = w + d;
      h.push(...gr(
        n.slice(w, x),
        l,
        t,
        u,
        s,
        !1
        /* isLast */
      ));
    }
    h.push("...");
    for (let C = a - Mn; C < a; C++) {
      const w = C * d, x = w + d;
      h.push(...gr(
        n.slice(w, x),
        l,
        t,
        u,
        s,
        C === a - 1
        /* isLast */
      ));
    }
  } else
    for (let C = 0; C < a; C++) {
      const w = C * d, x = w + d;
      h.push(...gr(
        n.slice(w, x),
        l,
        t,
        u,
        s,
        C === a - 1
        /* isLast */
      ));
    }
  const f = c === 2 ? "," : "";
  h[0] = "[" + (a > 0 ? h[0] + f : "");
  for (let C = 1; C < h.length - 1; C++)
    h[C] = " " + h[C] + f;
  let m = `,
`;
  for (let C = 2; C < c; C++)
    m += `
`;
  return h[h.length - 1] = " " + h[h.length - 1] + "]" + (o ? "" : m), h;
}
function Vn(n) {
  const e = [];
  for (let t = 0; t < n.length; t += 2)
    e.push([n[t], n[t + 1]]);
  return e;
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class vr {
  constructor(e, t, r) {
    if (this.dtype = t, this.shape = e.slice(), this.size = _(e), r != null) {
      const s = r.length;
      O(s === this.size, () => `Length of values '${s}' does not match the size inferred by the shape '${this.size}'.`);
    }
    if (t === "complex64")
      throw new Error("complex64 dtype TensorBuffers are not supported. Please create a TensorBuffer for the real and imaginary parts separately and call tf.complex(real, imag).");
    this.values = r || de(t, this.size), this.strides = me(e);
  }
  /**
   * Sets a value in the buffer at a given location.
   *
   * @param value The value to set.
   * @param locs  The location indices.
   *
   * @doc {heading: 'Tensors', subheading: 'Creation'}
   */
  set(e, ...t) {
    t.length === 0 && (t = [0]), O(t.length === this.rank, () => `The number of provided coordinates (${t.length}) must match the rank (${this.rank})`);
    const r = this.locToIndex(t);
    this.values[r] = e;
  }
  /**
   * Returns the value in the buffer at the provided location.
   *
   * @param locs The location indices.
   *
   * @doc {heading: 'Tensors', subheading: 'Creation'}
   */
  get(...e) {
    e.length === 0 && (e = [0]);
    let t = 0;
    for (const s of e) {
      if (s < 0 || s >= this.shape[t]) {
        const o = `Requested out of range element at ${e}.   Buffer shape=${this.shape}`;
        throw new Error(o);
      }
      t++;
    }
    let r = e[e.length - 1];
    for (let s = 0; s < e.length - 1; ++s)
      r += this.strides[s] * e[s];
    return this.values[r];
  }
  locToIndex(e) {
    if (this.rank === 0)
      return 0;
    if (this.rank === 1)
      return e[0];
    let t = e[e.length - 1];
    for (let r = 0; r < e.length - 1; ++r)
      t += this.strides[r] * e[r];
    return t;
  }
  indexToLoc(e) {
    if (this.rank === 0)
      return [];
    if (this.rank === 1)
      return [e];
    const t = new Array(this.shape.length);
    for (let r = 0; r < t.length - 1; ++r)
      t[r] = Math.floor(e / this.strides[r]), e -= t[r] * this.strides[r];
    return t[t.length - 1] = e, t;
  }
  get rank() {
    return this.shape.length;
  }
  /**
   * Creates an immutable `tf.Tensor` object from the buffer.
   *
   * @doc {heading: 'Tensors', subheading: 'Creation'}
   */
  toTensor() {
    return Ke().makeTensor(this.values, this.shape, this.dtype);
  }
}
let Ke = null, cn = null;
function ef(n) {
  Ke = n;
}
function tf(n) {
  cn = n;
}
class Me {
  constructor(e, t, r, s) {
    this.kept = !1, this.isDisposedInternal = !1, this.shape = e.slice(), this.dtype = t || "float32", this.size = _(e), this.strides = me(e), this.dataId = r, this.id = s, this.rankType = this.rank < 5 ? this.rank.toString() : "higher";
  }
  get rank() {
    return this.shape.length;
  }
  /**
   * Returns a promise of `tf.TensorBuffer` that holds the underlying data.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  async buffer() {
    const e = await this.data();
    return cn.buffer(this.shape, this.dtype, e);
  }
  /**
   * Returns a `tf.TensorBuffer` that holds the underlying data.
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  bufferSync() {
    return cn.buffer(this.shape, this.dtype, this.dataSync());
  }
  /**
   * Returns the tensor data as a nested array. The transfer of data is done
   * asynchronously.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  async array() {
    const e = await this.data();
    return Co(this.shape, e, this.dtype === "complex64");
  }
  /**
   * Returns the tensor data as a nested array. The transfer of data is done
   * synchronously.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  arraySync() {
    return Co(this.shape, this.dataSync(), this.dtype === "complex64");
  }
  /**
   * Asynchronously downloads the values from the `tf.Tensor`. Returns a
   * promise of `TypedArray` that resolves when the computation has finished.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  async data() {
    this.throwIfDisposed();
    const e = Ke().read(this.dataId);
    if (this.dtype === "string") {
      const t = await e;
      try {
        return t.map((r) => xn(r));
      } catch {
        throw new Error("Failed to decode the string bytes into utf-8. To get the original bytes, call tensor.bytes().");
      }
    }
    return e;
  }
  /**
   * Copy the tensor's data to a new GPU resource. Comparing to the `dataSync()`
   * and `data()`, this method prevents data from being downloaded to CPU.
   *
   * For WebGL backend, the data will be stored on a densely packed texture.
   * This means that the texture will use the RGBA channels to store value.
   *
   * For WebGPU backend, the data will be stored on a buffer. There is no
   * parameter, so can not use a user-defined size to create the buffer.
   *
   * @param options:
   *     For WebGL,
   *         - customTexShape: Optional. If set, will use the user defined
   *     texture shape to create the texture.
   *
   * @returns For WebGL backend, a GPUData contains the new texture and
   *     its information.
   *     {
   *        tensorRef: The tensor that is associated with this texture,
   *        texture: WebGLTexture,
   *        texShape: [number, number] // [height, width]
   *     }
   *
   *     For WebGPU backend, a GPUData contains the new buffer.
   *     {
   *        tensorRef: The tensor that is associated with this buffer,
   *        buffer: GPUBuffer,
   *     }
   *
   *     Remember to dispose the GPUData after it is used by
   *     `res.tensorRef.dispose()`.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  dataToGPU(e) {
    return this.throwIfDisposed(), Ke().readToGPU(this.dataId, e);
  }
  /**
   * Synchronously downloads the values from the `tf.Tensor`. This blocks the
   * UI thread until the values are ready, which can cause performance issues.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  dataSync() {
    this.throwIfDisposed();
    const e = Ke().readSync(this.dataId);
    if (this.dtype === "string")
      try {
        return e.map((t) => xn(t));
      } catch {
        throw new Error("Failed to decode the string bytes into utf-8. To get the original bytes, call tensor.bytes().");
      }
    return e;
  }
  /** Returns the underlying bytes of the tensor's data. */
  async bytes() {
    this.throwIfDisposed();
    const e = await Ke().read(this.dataId);
    return this.dtype === "string" ? e : new Uint8Array(e.buffer);
  }
  /**
   * Disposes `tf.Tensor` from memory.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  dispose() {
    this.isDisposed || (Ke().disposeTensor(this), this.isDisposedInternal = !0);
  }
  get isDisposed() {
    return this.isDisposedInternal;
  }
  throwIfDisposed() {
    if (this.isDisposed)
      throw new Error("Tensor is disposed.");
  }
  /**
   * Prints the `tf.Tensor`. See `tf.print` for details.
   *
   * @param verbose Whether to print verbose information about the tensor,
   *    including dtype and size.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  print(e = !1) {
    return cn.print(this, e);
  }
  /**
   * Returns a copy of the tensor. See `tf.clone` for details.
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  clone() {
    return this.throwIfDisposed(), cn.clone(this);
  }
  /**
   * Returns a human-readable description of the tensor. Useful for logging.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  toString(e = !1) {
    const t = this.dataSync();
    return Zh(t, this.shape, this.dtype, e);
  }
  cast(e) {
    return this.throwIfDisposed(), cn.cast(this, e);
  }
  variable(e = !0, t, r) {
    return this.throwIfDisposed(), Ke().makeVariable(this, e, t, r);
  }
}
Object.defineProperty(Me, Symbol.hasInstance, {
  value: (n) => !!n && n.data != null && n.dataSync != null && n.throwIfDisposed != null
});
function nf() {
  return Os("Tensor", () => Me);
}
nf();
class Ir extends Me {
  constructor(e, t, r, s) {
    super(e.shape, e.dtype, e.dataId, s), this.trainable = t, this.name = r;
  }
  /**
   * Assign a new `tf.Tensor` to this variable. The new `tf.Tensor` must have
   * the same shape and dtype as the old `tf.Tensor`.
   *
   * @param newValue New tensor to be assigned to this variable.
   *
   * @doc {heading: 'Tensors', subheading: 'Classes'}
   */
  assign(e) {
    if (e.dtype !== this.dtype)
      throw new Error(`dtype of the new value (${e.dtype}) and previous value (${this.dtype}) must match`);
    if (!ge(e.shape, this.shape))
      throw new Error(`shape of the new value (${e.shape}) and previous value (${this.shape}) must match`);
    Ke().disposeTensor(this), this.dataId = e.dataId, Ke().incRef(
      this,
      null
      /* backend */
    );
  }
  dispose() {
    Ke().disposeVariable(this), this.isDisposedInternal = !0;
  }
}
Object.defineProperty(Ir, Symbol.hasInstance, {
  value: (n) => n instanceof Me && n.assign != null && n.assign instanceof Function
});
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
var Fo;
(function(n) {
  n.R0 = "R0", n.R1 = "R1", n.R2 = "R2", n.R3 = "R3", n.R4 = "R4", n.R5 = "R5", n.R6 = "R6";
})(Fo || (Fo = {}));
var ps;
(function(n) {
  n.float32 = "float32", n.int32 = "int32", n.bool = "int32", n.complex64 = "complex64";
})(ps || (ps = {}));
var ms;
(function(n) {
  n.float32 = "float32", n.int32 = "int32", n.bool = "bool", n.complex64 = "complex64";
})(ms || (ms = {}));
var gs;
(function(n) {
  n.float32 = "float32", n.int32 = "float32", n.bool = "float32", n.complex64 = "complex64";
})(gs || (gs = {}));
var xs;
(function(n) {
  n.float32 = "complex64", n.int32 = "complex64", n.bool = "complex64", n.complex64 = "complex64";
})(xs || (xs = {}));
const rf = {
  float32: gs,
  int32: ps,
  bool: ms,
  complex64: xs
};
function dt(n, e) {
  if (n === "string" || e === "string") {
    if (n === "string" && e === "string")
      return "string";
    throw new Error(`Can not upcast ${n} with ${e}`);
  }
  return rf[n][e];
}
function Ms(n) {
  return dt(n, "int32");
}
function ua(n) {
  return n != null && typeof n == "object" && "texture" in n && n.texture instanceof WebGLTexture;
}
function da(n) {
  return typeof GPUBuffer < "u" && n != null && typeof n == "object" && "buffer" in n && n.buffer instanceof GPUBuffer;
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Kt(n, e) {
  if (n.dtype === e.dtype)
    return [n, e];
  const t = dt(n.dtype, e.dtype);
  return [n.cast(t), e.cast(t)];
}
function ha(n) {
  const e = [];
  return fa(n, e, /* @__PURE__ */ new Set()), e;
}
function fa(n, e, t) {
  if (n == null)
    return;
  if (n instanceof Me) {
    e.push(n);
    return;
  }
  if (!sf(n))
    return;
  const r = n;
  for (const s in r) {
    const o = r[s];
    t.has(o) || (t.add(o), fa(o, e, t));
  }
}
function sf(n) {
  return Array.isArray(n) || typeof n == "object";
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Yr(n) {
  return n.kernelName != null;
}
class Do {
  constructor() {
    this.registeredVariables = {}, this.nextTapeNodeId = 0, this.numBytes = 0, this.numTensors = 0, this.numStringTensors = 0, this.numDataBuffers = 0, this.gradientDepth = 0, this.kernelDepth = 0, this.scopeStack = [], this.numDataMovesStack = [], this.nextScopeId = 0, this.tensorInfo = /* @__PURE__ */ new WeakMap(), this.profiling = !1, this.activeProfile = {
      newBytes: 0,
      newTensors: 0,
      peakBytes: 0,
      kernels: [],
      result: null,
      get kernelNames() {
        return Array.from(new Set(this.kernels.map((e) => e.name)));
      }
    };
  }
  dispose() {
    for (const e in this.registeredVariables)
      this.registeredVariables[e].dispose();
  }
}
class wn {
  constructor(e) {
    this.ENV = e, this.registry = {}, this.registryFactory = {}, this.pendingBackendInitId = 0, this.state = new Do();
  }
  async ready() {
    if (this.pendingBackendInit != null)
      return this.pendingBackendInit.then(() => {
      });
    if (this.backendInstance != null)
      return;
    const e = this.getSortedBackends();
    for (let t = 0; t < e.length; t++) {
      const r = e[t];
      if (await this.initializeBackend(r).success) {
        await this.setBackend(r);
        return;
      }
    }
    throw new Error("Could not initialize any backends, all backend initializations failed.");
  }
  get backend() {
    if (this.pendingBackendInit != null)
      throw new Error(`Backend '${this.backendName}' has not yet been initialized. Make sure to await tf.ready() or await tf.setBackend() before calling other methods`);
    if (this.backendInstance == null) {
      const { name: e, asyncInit: t } = this.initializeBackendsAndReturnBest();
      if (t)
        throw new Error(`The highest priority backend '${e}' has not yet been initialized. Make sure to await tf.ready() or await tf.setBackend() before calling other methods`);
      this.setBackend(e);
    }
    return this.backendInstance;
  }
  backendNames() {
    return Object.keys(this.registryFactory);
  }
  findBackend(e) {
    if (!(e in this.registry))
      if (e in this.registryFactory) {
        const { asyncInit: t } = this.initializeBackend(e);
        if (t)
          return null;
      } else
        return null;
    return this.registry[e];
  }
  findBackendFactory(e) {
    return e in this.registryFactory ? this.registryFactory[e].factory : null;
  }
  registerBackend(e, t, r = 1) {
    return e in this.registryFactory ? (Qe(`${e} backend was already registered. Reusing existing backend factory.`), !1) : (this.registryFactory[e] = { factory: t, priority: r }, !0);
  }
  async setBackend(e) {
    if (this.registryFactory[e] == null)
      throw new Error(`Backend name '${e}' not found in registry`);
    if (this.backendName = e, this.registry[e] == null) {
      this.backendInstance = null;
      const { success: t, asyncInit: r } = this.initializeBackend(e);
      if (!(r ? await t : t))
        return !1;
    }
    return this.backendInstance = this.registry[e], this.setupRegisteredKernels(), this.profiler = new jh(this.backendInstance), !0;
  }
  setupRegisteredKernels() {
    Io(this.backendName).forEach((t) => {
      t.setupFunc != null && t.setupFunc(this.backendInstance);
    });
  }
  disposeRegisteredKernels(e) {
    Io(e).forEach((r) => {
      r.disposeFunc != null && r.disposeFunc(this.registry[e]);
    });
  }
  /**
   * Initializes a backend by looking up the backend name in the factory
   * registry and calling the factory method. Returns a boolean representing
   * whether the initialization of the backend suceeded. Throws an error if
   * there is no backend in the factory registry.
   */
  initializeBackend(e) {
    const t = this.registryFactory[e];
    if (t == null)
      throw new Error(`Cannot initialize backend ${e}, no registration found.`);
    try {
      const r = t.factory();
      if (r && !(r instanceof $i) && typeof r.then == "function") {
        const s = ++this.pendingBackendInitId, o = r.then((i) => s < this.pendingBackendInitId ? !1 : (this.registry[e] = i, this.pendingBackendInit = null, !0)).catch((i) => (s < this.pendingBackendInitId || (this.pendingBackendInit = null, Qe(`Initialization of backend ${e} failed`), Qe(i.stack || i.message)), !1));
        return this.pendingBackendInit = o, { success: o, asyncInit: !0 };
      } else
        return this.registry[e] = r, { success: !0, asyncInit: !1 };
    } catch (r) {
      return Qe(`Initialization of backend ${e} failed`), Qe(r.stack || r.message), { success: !1, asyncInit: !1 };
    }
  }
  removeBackend(e) {
    if (!(e in this.registryFactory))
      throw new Error(`${e} backend not found in registry`);
    this.backendName === e && this.pendingBackendInit != null && this.pendingBackendInitId++, e in this.registry && (this.disposeRegisteredKernels(e), this.registry[e].dispose(), delete this.registry[e]), delete this.registryFactory[e], this.backendName === e && (this.pendingBackendInit = null, this.backendName = null, this.backendInstance = null);
  }
  getSortedBackends() {
    if (Object.keys(this.registryFactory).length === 0)
      throw new Error("No backend found in registry.");
    return Object.keys(this.registryFactory).sort((e, t) => this.registryFactory[t].priority - this.registryFactory[e].priority);
  }
  initializeBackendsAndReturnBest() {
    const e = this.getSortedBackends();
    for (let t = 0; t < e.length; t++) {
      const r = e[t], { success: s, asyncInit: o } = this.initializeBackend(r);
      if (o || s)
        return { name: r, asyncInit: o };
    }
    throw new Error("Could not initialize any backends, all backend initializations failed.");
  }
  moveData(e, t) {
    const r = this.state.tensorInfo.get(t), s = r.backend, o = this.readSync(t), i = s.refCount(t);
    s.disposeData(t, !0), r.backend = e, e.move(t, o, r.shape, r.dtype, i), this.shouldCheckForMemLeaks() && this.state.numDataMovesStack[this.state.numDataMovesStack.length - 1]++;
  }
  tidy(e, t) {
    let r = null;
    if (t == null) {
      if (typeof e != "function")
        throw new Error("Please provide a function to tidy()");
      t = e;
    } else {
      if (typeof e != "string" && !(e instanceof String))
        throw new Error("When calling with two arguments, the first argument to tidy() must be a string");
      if (typeof t != "function")
        throw new Error("When calling with two arguments, the 2nd argument to tidy() must be a function");
      r = e;
    }
    let s;
    return this.scopedRun(() => this.startScope(r), () => this.endScope(s), () => (s = t(), s instanceof Promise && console.error("Cannot return a Promise inside of tidy."), s));
  }
  scopedRun(e, t, r) {
    e();
    try {
      const s = r();
      return t(), s;
    } catch (s) {
      throw t(), s;
    }
  }
  nextTensorId() {
    return wn.nextTensorId++;
  }
  nextVariableId() {
    return wn.nextVariableId++;
  }
  /**
   * This method is called instead of the public-facing tensor.clone() when
   * saving a tensor for backwards pass. It makes sure to add the clone
   * operation to the tape regardless of being called inside a kernel
   * execution.
   */
  clone(e) {
    const t = M.runKernel(Bs, { x: e }), r = { x: e }, s = (i) => ({
      x: () => {
        const a = "float32", c = { x: i }, l = { dtype: a };
        return M.runKernel(
          _s,
          c,
          // tslint:disable-next-line: no-unnecessary-type-assertion
          l
        );
      }
    }), o = [];
    return this.addTapeNode(this.state.activeScope.name, r, [t], s, o, {}), t;
  }
  /**
   * Execute a kernel with the given name and return the output tensor.
   *
   * @param kernelName The name of the kernel to execute.
   * @param inputs A map of input names to tensors.
   * @param attrs A map of attribute names to their values. An attribute is a
   *     primitive (non-tensor) input to the kernel.
   * @param inputsToSave A list of tensors, inputs to save for the backprop
   *     computation.
   * @param outputsToSave A list of booleans, specifying which output to save
   *     for the backprop computation. These are booleans since the output
   * tensors are not visible to the user.
   */
  runKernel(e, t, r) {
    if (this.backendName == null && this.backend, !($o(e, this.backendName) != null))
      throw new Error(`Kernel '${e}' not registered for backend '${this.backendName}'`);
    return this.runKernelFunc({ kernelName: e, inputs: t, attrs: r });
  }
  shouldCheckForMemLeaks() {
    return this.ENV.getBool("IS_TEST");
  }
  checkKernelForMemLeak(e, t, r) {
    const s = this.backend.numDataIds();
    let o = 0;
    r.forEach((c) => {
      o += c.dtype === "complex64" ? 3 : 1;
    });
    const i = this.state.numDataMovesStack[this.state.numDataMovesStack.length - 1], a = s - t - o - i;
    if (a > 0)
      throw new Error(`Backend '${this.backendName}' has an internal memory leak (${a} data ids) after running '${e}'`);
  }
  /**
   * Internal helper method to execute a kernel Func
   *
   * Use `runKernel` to execute kernels from outside of engine.
   */
  runKernelFunc(e) {
    let t, r = [];
    const s = this.isTapeOn(), o = this.state.numBytes, i = this.state.numTensors;
    this.shouldCheckForMemLeaks() && this.state.numDataMovesStack.push(0);
    let a;
    this.backendName == null && this.backend;
    let c;
    const l = Yr(e) ? e.kernelName : this.state.activeScope != null ? this.state.activeScope.name : "";
    if (Yr(e)) {
      const { kernelName: m, inputs: C, attrs: w } = e;
      this.backendName == null && this.backend;
      const x = $o(m, this.backendName);
      O(x != null, () => `Cannot find registered kernel '${m}' for backend '${this.backendName}'`), a = () => {
        const y = this.backend.numDataIds();
        c = x.kernelFunc({ inputs: C, attrs: w, backend: this.backend });
        const v = Array.isArray(c) ? c : [c];
        this.shouldCheckForMemLeaks() && this.checkKernelForMemLeak(m, y, v);
        const I = v.map((T) => T.rank != null ? T : this.makeTensorFromTensorInfo(T));
        if (s) {
          const T = this.getTensorsForGradient(m, C, I);
          r = this.saveTensorsForBackwardMode(T);
        }
        return I;
      };
    } else {
      const { forwardFunc: m } = e, C = (w) => {
        s && (r = w.map((x) => this.keep(this.clone(x))));
      };
      a = () => {
        const w = this.backend.numDataIds();
        c = this.tidy(() => m(this.backend, C));
        const x = Array.isArray(c) ? c : [c];
        return this.shouldCheckForMemLeaks() && this.checkKernelForMemLeak(l, w, x), x;
      };
    }
    const { inputs: u, attrs: d } = e, h = Yr(e) ? null : e.backwardsFunc;
    let f;
    return this.scopedRun(
      // Stop recording to a tape when running a kernel.
      () => this.state.kernelDepth++,
      () => this.state.kernelDepth--,
      () => {
        !this.ENV.getBool("DEBUG") && !this.state.profiling ? t = a() : (f = this.profiler.profileKernel(l, u, () => a()), this.ENV.getBool("DEBUG") && this.profiler.logKernelProfile(f), t = f.outputs);
      }
    ), s && this.addTapeNode(l, u, t, h, r, d), this.state.profiling && this.state.activeProfile.kernels.push({
      name: l,
      bytesAdded: this.state.numBytes - o,
      totalBytesSnapshot: this.state.numBytes,
      tensorsAdded: this.state.numTensors - i,
      totalTensorsSnapshot: this.state.numTensors,
      inputShapes: Object.keys(u).map((m) => u[m] != null ? u[m].shape : null),
      outputShapes: t.map((m) => m.shape),
      kernelTimeMs: f.timeMs,
      extraInfo: f.extraInfo
    }), Array.isArray(c) ? t : t[0];
  }
  /**
   * Saves tensors used in forward mode for use in backward mode.
   *
   * @param tensors the list of tensors to save.
   */
  saveTensorsForBackwardMode(e) {
    return e.map((r) => this.keep(this.clone(r)));
  }
  /**
   * Returns a list of tensors to save for a given gradient calculation.
   *
   * @param kernelName name of kernel to look up gradient for.
   * @param inputs a map of input tensors.
   * @param outputs an array of output tensors from forward mode of kernel.
   */
  getTensorsForGradient(e, t, r) {
    const s = vo(e);
    if (s != null) {
      const o = s.inputsToSave || [], i = s.outputsToSave || [];
      let a;
      s.saveAllInputs ? (O(Array.isArray(t), () => "saveAllInputs is true, expected inputs to be an array."), a = Object.keys(t).map((l) => t[l])) : a = o.map((l) => t[l]);
      const c = r.filter((l, u) => i[u]);
      return a.concat(c);
    }
    return [];
  }
  /**
   * Internal method used by public APIs for tensor creation. Makes a new
   * tensor with the provided shape, dtype and values. It always
   * creates a new data id and writes the values to the underlying backend.
   */
  makeTensor(e, t, r, s) {
    if (e == null)
      throw new Error("Values passed to engine.makeTensor() are null");
    r = r || "float32", s = s || this.backend;
    let o = e;
    r === "string" && Fr(e[0]) && (o = e.map((c) => Lt(c)));
    const i = s.write(o, t, r), a = new Me(t, r, i, this.nextTensorId());
    if (this.trackTensor(a, s), r === "string") {
      const c = this.state.tensorInfo.get(i), l = Ll(o);
      this.state.numBytes += l - c.bytes, c.bytes = l;
    }
    return a;
  }
  /**
   * Internal method used by backends. Makes a new tensor
   * that is a wrapper around an existing data id. It doesn't create
   * a new data id, only increments the ref count used in memory tracking.
   * @deprecated
   */
  makeTensorFromDataId(e, t, r, s) {
    r = r || "float32";
    const o = { dataId: e, shape: t, dtype: r };
    return this.makeTensorFromTensorInfo(o, s);
  }
  /**
   * Internal method used by backends. Makes a new tensor that is a wrapper
   * around an existing data id in TensorInfo. It doesn't create a new data id,
   * only increments the ref count used in memory tracking.
   */
  makeTensorFromTensorInfo(e, t) {
    const { dataId: r, shape: s, dtype: o } = e, i = new Me(s, o, r, this.nextTensorId());
    return this.trackTensor(i, t), i;
  }
  makeVariable(e, t = !0, r, s) {
    r = r || this.nextVariableId().toString(), s != null && s !== e.dtype && (e = e.cast(s));
    const o = new Ir(e, t, r, this.nextTensorId());
    if (this.state.registeredVariables[o.name] != null)
      throw new Error(`Variable with name ${o.name} was already registered`);
    return this.state.registeredVariables[o.name] = o, this.incRef(o, this.backend), o;
  }
  trackTensor(e, t) {
    this.state.numTensors++, e.dtype === "string" && this.state.numStringTensors++;
    let r = 0;
    e.dtype !== "complex64" && e.dtype !== "string" && (r = e.size * br(e.dtype)), this.state.numBytes += r, this.state.tensorInfo.has(e.dataId) || (this.state.numDataBuffers++, this.state.tensorInfo.set(e.dataId, {
      backend: t || this.backend,
      dtype: e.dtype,
      shape: e.shape,
      bytes: r
    })), e instanceof Ir || this.track(e);
  }
  // Track the tensor by dataId and increase the refCount for the dataId in the
  // backend.
  // TODO(pyu10055): This is currently used by makeVariable method, to increase
  // refCount on the backend for the dataId. It can potentially be replaced with
  // Identity op indead of calling backend directly.
  incRef(e, t) {
    this.trackTensor(e, t), this.backend.incRef(e.dataId);
  }
  removeDataId(e, t) {
    this.state.tensorInfo.has(e) && this.state.tensorInfo.get(e).backend === t && (this.state.tensorInfo.delete(e), this.state.numDataBuffers--);
  }
  disposeTensor(e) {
    if (!this.state.tensorInfo.has(e.dataId))
      return;
    const t = this.state.tensorInfo.get(e.dataId);
    if (this.state.numTensors--, e.dtype === "string" && (this.state.numStringTensors--, this.state.numBytes -= t.bytes), e.dtype !== "complex64" && e.dtype !== "string") {
      const r = e.size * br(e.dtype);
      this.state.numBytes -= r;
    }
    t.backend.disposeData(e.dataId) && this.removeDataId(e.dataId, t.backend);
  }
  disposeVariables() {
    for (const e in this.state.registeredVariables) {
      const t = this.state.registeredVariables[e];
      this.disposeVariable(t);
    }
  }
  disposeVariable(e) {
    this.disposeTensor(e), this.state.registeredVariables[e.name] != null && delete this.state.registeredVariables[e.name];
  }
  memory() {
    const e = this.backend.memory();
    return e.numTensors = this.state.numTensors, e.numDataBuffers = this.state.numDataBuffers, e.numBytes = this.state.numBytes, this.state.numStringTensors > 0 && (e.unreliable = !0, e.reasons == null && (e.reasons = []), e.reasons.push("Memory usage by string tensors is approximate (2 bytes per character)")), e;
  }
  async profile(e) {
    this.state.profiling = !0;
    const t = this.state.numBytes, r = this.state.numTensors;
    this.state.activeProfile.kernels = [], this.state.activeProfile.result = await e(), this.state.profiling = !1, this.state.activeProfile.peakBytes = Math.max(...this.state.activeProfile.kernels.map((s) => s.totalBytesSnapshot)), this.state.activeProfile.newBytes = this.state.numBytes - t, this.state.activeProfile.newTensors = this.state.numTensors - r;
    for (const s of this.state.activeProfile.kernels)
      s.kernelTimeMs = await s.kernelTimeMs, s.extraInfo = await s.extraInfo;
    return this.state.activeProfile;
  }
  isTapeOn() {
    return this.state.gradientDepth > 0 && this.state.kernelDepth === 0;
  }
  addTapeNode(e, t, r, s, o, i) {
    const a = { id: this.state.nextTapeNodeId++, kernelName: e, inputs: t, outputs: r, saved: o }, c = vo(e);
    c != null && (s = c.gradFunc), s != null && (a.gradient = (l) => (l = l.map((u, d) => {
      if (u == null) {
        const h = r[d], f = Rt(h.size, h.dtype);
        return this.makeTensor(f, h.shape, h.dtype);
      }
      return u;
    }), s(l.length > 1 ? l : l[0], o, i))), this.state.activeTape.push(a);
  }
  keep(e) {
    return e.kept = !0, e;
  }
  startTape() {
    this.state.gradientDepth === 0 && (this.state.activeTape = []), this.state.gradientDepth++;
  }
  endTape() {
    this.state.gradientDepth--;
  }
  /**
   * Start a scope. Use this with endScope() to achieve the same functionality
   * as scope() without the need for a function closure.
   */
  startScope(e) {
    const t = {
      track: [],
      name: "unnamed scope",
      id: this.state.nextScopeId++
    };
    e && (t.name = e), this.state.scopeStack.push(t), this.state.activeScope = t;
  }
  /**
   * End a scope. Use this with startScope() to achieve the same functionality
   * as scope() without the need for a function closure.
   */
  endScope(e) {
    const t = ha(e), r = new Set(t.map((o) => o.id));
    for (let o = 0; o < this.state.activeScope.track.length; o++) {
      const i = this.state.activeScope.track[o];
      !i.kept && !r.has(i.id) && i.dispose();
    }
    const s = this.state.scopeStack.pop();
    this.state.activeScope = this.state.scopeStack.length === 0 ? null : this.state.scopeStack[this.state.scopeStack.length - 1], t.forEach((o) => {
      !o.kept && o.scopeId === s.id && this.track(o);
    });
  }
  /**
   * Returns gradients of `f` with respect to each of the `xs`. The gradients
   * returned are of the same length as `xs`, but some might be null if `f`
   * was not a function of that `x`. It also takes optional dy to multiply the
   * gradient, which defaults to `1`.
   */
  gradients(e, t, r, s = !1) {
    if (O(t.length > 0, () => "gradients() received an empty list of xs."), r != null && r.dtype !== "float32")
      throw new Error(`dy must have 'float32' dtype, but has '${r.dtype}'`);
    const o = this.scopedRun(() => this.startTape(), () => this.endTape(), () => this.tidy("forward", e));
    O(o instanceof Me, () => "The result y returned by f() must be a tensor.");
    const i = Yh(this.state.activeTape, t, o);
    if (!s && i.length === 0 && t.length > 0)
      throw new Error("Cannot compute gradient of y=f(x) with respect to x. Make sure that the f you passed encloses all operations that lead from x to y.");
    return this.tidy("backward", () => {
      const a = {};
      a[o.id] = r ?? of(o.shape), Qh(
        a,
        i,
        // Pass the tidy function to avoid circular dep with `tape.ts`.
        (l) => this.tidy(l),
        // Pass an add function to avoide a circular dep with `tape.ts`.
        af
      );
      const c = t.map((l) => a[l.id]);
      return this.state.gradientDepth === 0 && (this.state.activeTape.forEach((l) => {
        for (const u of l.saved)
          u.dispose();
      }), this.state.activeTape = null), { value: o, grads: c };
    });
  }
  customGrad(e) {
    return O(as(e), () => "The f passed in customGrad(f) must be a function."), (...t) => {
      O(t.every((a) => a instanceof Me), () => "The args passed in customGrad(f)(x1, x2,...) must all be tensors");
      let r;
      const s = {};
      t.forEach((a, c) => {
        s[c] = a;
      });
      const o = (a, c) => (r = e(...t, c), O(r.value instanceof Me, () => "The function f passed in customGrad(f) must return an object where `obj.value` is a tensor"), O(as(r.gradFunc), () => "The function f passed in customGrad(f) must return an object where `obj.gradFunc` is a function."), r.value), i = (a, c) => {
        const l = r.gradFunc(a, c), u = Array.isArray(l) ? l : [l];
        O(u.length === t.length, () => "The function f passed in customGrad(f) must return an object where `obj.gradFunc` is a function that returns the same number of tensors as inputs passed to f(...)."), O(u.every((h) => h instanceof Me), () => "The function f passed in customGrad(f) must return an object where `obj.gradFunc` is a function that returns a list of only tensors.");
        const d = {};
        return u.forEach((h, f) => {
          d[f] = () => h;
        }), d;
      };
      return this.runKernelFunc({
        forwardFunc: o,
        backwardsFunc: i,
        inputs: s
      });
    };
  }
  readSync(e) {
    return this.state.tensorInfo.get(e).backend.readSync(e);
  }
  read(e) {
    return this.state.tensorInfo.get(e).backend.read(e);
  }
  readToGPU(e, t) {
    return this.state.tensorInfo.get(e).backend.readToGPU(e, t);
  }
  async time(e) {
    const t = qe(), r = await this.backend.time(e);
    return r.wallMs = qe() - t, r;
  }
  /**
   * Tracks a Tensor in the current scope to be automatically cleaned up
   * when the current scope ends, and returns the value.
   *
   * @param result The Tensor to track in the current scope.
   */
  track(e) {
    return this.state.activeScope != null && (e.scopeId = this.state.activeScope.id, this.state.activeScope.track.push(e)), e;
  }
  get registeredVariables() {
    return this.state.registeredVariables;
  }
  /**
   * Resets the engine state. Removes all backends but does not remove
   * registered backend factories.
   */
  reset() {
    this.pendingBackendInitId++, this.state.dispose(), this.ENV.reset(), this.state = new Do();
    for (const e in this.registry)
      this.disposeRegisteredKernels(e), this.registry[e].dispose(), delete this.registry[e];
    this.backendName = null, this.backendInstance = null, this.pendingBackendInit = null;
  }
}
wn.nextTensorId = 0;
wn.nextVariableId = 0;
function of(n) {
  const e = Vl(_(n), "float32");
  return M.makeTensor(e, n, "float32");
}
function pa() {
  const n = ki();
  if (n._tfengine == null) {
    const e = new Wl(n);
    n._tfengine = new wn(e);
  }
  return Xl(n._tfengine.ENV), ef(() => n._tfengine), n._tfengine;
}
const M = pa();
function af(n, e) {
  const t = { a: n, b: e };
  return M.runKernel(Ps, t);
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function cf() {
  return typeof navigator < "u" && navigator != null;
}
function ma(n) {
  if (n || cf()) {
    if (n || (n = navigator), n.product === "ReactNative")
      return !0;
    const e = n.userAgent || n.vendor || // tslint:disable-next-line:no-any
    (typeof window < "u" ? window.opera : "");
    if (!e) {
      const t = n;
      return t.userAgentData && t.userAgentData.mobile;
    }
    return /(android|bb\d+|meego).+mobile|avantgo|bada\/|blackberry|blazer|compal|elaine|fennec|hiptop|iemobile|ip(hone|od)|iris|kindle|lge |maemo|midp|mmp|mobile.+firefox|netfront|opera m(ob|in)i|palm( os)?|phone|p(ixi|re)\/|plucker|pocket|psp|series(4|6)0|symbian|treo|up\.(browser|link)|vodafone|wap|windows ce|xda|xiino/i.test(e) || // tslint:disable-next-line:max-line-length
    /1207|6310|6590|3gso|4thp|50[1-6]i|770s|802s|a wa|abac|ac(er|oo|s\-)|ai(ko|rn)|al(av|ca|co)|amoi|an(ex|ny|yw)|aptu|ar(ch|go)|as(te|us)|attw|au(di|\-m|r |s )|avan|be(ck|ll|nq)|bi(lb|rd)|bl(ac|az)|br(e|v)w|bumb|bw\-(n|u)|c55\/|capi|ccwa|cdm\-|cell|chtm|cldc|cmd\-|co(mp|nd)|craw|da(it|ll|ng)|dbte|dc\-s|devi|dica|dmob|do(c|p)o|ds(12|\-d)|el(49|ai)|em(l2|ul)|er(ic|k0)|esl8|ez([4-7]0|os|wa|ze)|fetc|fly(\-|_)|g1 u|g560|gene|gf\-5|g\-mo|go(\.w|od)|gr(ad|un)|haie|hcit|hd\-(m|p|t)|hei\-|hi(pt|ta)|hp( i|ip)|hs\-c|ht(c(\-| |_|a|g|p|s|t)|tp)|hu(aw|tc)|i\-(20|go|ma)|i230|iac( |\-|\/)|ibro|idea|ig01|ikom|im1k|inno|ipaq|iris|ja(t|v)a|jbro|jemu|jigs|kddi|keji|kgt( |\/)|klon|kpt |kwc\-|kyo(c|k)|le(no|xi)|lg( g|\/(k|l|u)|50|54|\-[a-w])|libw|lynx|m1\-w|m3ga|m50\/|ma(te|ui|xo)|mc(01|21|ca)|m\-cr|me(rc|ri)|mi(o8|oa|ts)|mmef|mo(01|02|bi|de|do|t(\-| |o|v)|zz)|mt(50|p1|v )|mwbp|mywa|n10[0-2]|n20[2-3]|n30(0|2)|n50(0|2|5)|n7(0(0|1)|10)|ne((c|m)\-|on|tf|wf|wg|wt)|nok(6|i)|nzph|o2im|op(ti|wv)|oran|owg1|p800|pan(a|d|t)|pdxg|pg(13|\-([1-8]|c))|phil|pire|pl(ay|uc)|pn\-2|po(ck|rt|se)|prox|psio|pt\-g|qa\-a|qc(07|12|21|32|60|\-[2-7]|i\-)|qtek|r380|r600|raks|rim9|ro(ve|zo)|s55\/|sa(ge|ma|mm|ms|ny|va)|sc(01|h\-|oo|p\-)|sdk\/|se(c(\-|0|1)|47|mc|nd|ri)|sgh\-|shar|sie(\-|m)|sk\-0|sl(45|id)|sm(al|ar|b3|it|t5)|so(ft|ny)|sp(01|h\-|v\-|v )|sy(01|mb)|t2(18|50)|t6(00|10|18)|ta(gt|lk)|tcl\-|tdg\-|tel(i|m)|tim\-|t\-mo|to(pl|sh)|ts(70|m\-|m3|m5)|tx\-9|up(\.b|g1|si)|utst|v400|v750|veri|vi(rg|te)|vk(40|5[0-3]|\-v)|vm40|voda|vulc|vx(52|53|60|61|70|80|81|83|85|98)|w3c(\-| )|webc|whit|wi(g |nc|nw)|wmlb|wonu|x700|yas\-|your|zeto|zte\-/i.test(e.substr(0, 4));
  }
  return !1;
}
function ga() {
  return typeof window < "u" && window.document != null || //@ts-ignore
  typeof WorkerGlobalScope < "u";
}
const Ee = E();
Ee.registerFlag("DEBUG", () => !1, (n) => {
  n && console.warn("Debugging mode is ON. The output of every math call will be downloaded to CPU and checked for NaNs. This significantly impacts performance.");
});
Ee.registerFlag("IS_BROWSER", () => ga());
Ee.registerFlag("IS_NODE", () => typeof fn < "u" && typeof fn.versions < "u" && typeof fn.versions.node < "u");
Ee.registerFlag("IS_CHROME", () => typeof navigator < "u" && navigator != null && navigator.userAgent != null && /Chrome/.test(navigator.userAgent) && /Google Inc/.test(navigator.vendor));
Ee.registerFlag("IS_SAFARI", () => typeof navigator < "u" && navigator != null && navigator.userAgent != null && /Safari/.test(navigator.userAgent) && /Apple/.test(navigator.vendor));
Ee.registerFlag("PROD", () => !1);
Ee.registerFlag("TENSORLIKE_CHECK_SHAPE_CONSISTENCY", () => Ee.getBool("DEBUG"));
Ee.registerFlag("DEPRECATION_WARNINGS_ENABLED", () => !0);
Ee.registerFlag("IS_TEST", () => !1);
Ee.registerFlag("CHECK_COMPUTATION_FOR_ERRORS", () => Ee.getBool("DEBUG"));
Ee.registerFlag("WRAP_TO_IMAGEBITMAP", () => !1);
Ee.registerFlag("CANVAS2D_WILL_READ_FREQUENTLY_FOR_GPU", () => !1);
Ee.registerFlag("USE_SETTIMEOUTCUSTOM", () => !1);
var Us = {}, Pr = {};
Pr.byteLength = df;
Pr.toByteArray = ff;
Pr.fromByteArray = gf;
var at = [], Le = [], lf = typeof Uint8Array < "u" ? Uint8Array : Array, Qr = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
for (var on = 0, uf = Qr.length; on < uf; ++on)
  at[on] = Qr[on], Le[Qr.charCodeAt(on)] = on;
Le[45] = 62;
Le[95] = 63;
function xa(n) {
  var e = n.length;
  if (e % 4 > 0)
    throw new Error("Invalid string. Length must be a multiple of 4");
  var t = n.indexOf("=");
  t === -1 && (t = e);
  var r = t === e ? 0 : 4 - t % 4;
  return [t, r];
}
function df(n) {
  var e = xa(n), t = e[0], r = e[1];
  return (t + r) * 3 / 4 - r;
}
function hf(n, e, t) {
  return (e + t) * 3 / 4 - t;
}
function ff(n) {
  var e, t = xa(n), r = t[0], s = t[1], o = new lf(hf(n, r, s)), i = 0, a = s > 0 ? r - 4 : r, c;
  for (c = 0; c < a; c += 4)
    e = Le[n.charCodeAt(c)] << 18 | Le[n.charCodeAt(c + 1)] << 12 | Le[n.charCodeAt(c + 2)] << 6 | Le[n.charCodeAt(c + 3)], o[i++] = e >> 16 & 255, o[i++] = e >> 8 & 255, o[i++] = e & 255;
  return s === 2 && (e = Le[n.charCodeAt(c)] << 2 | Le[n.charCodeAt(c + 1)] >> 4, o[i++] = e & 255), s === 1 && (e = Le[n.charCodeAt(c)] << 10 | Le[n.charCodeAt(c + 1)] << 4 | Le[n.charCodeAt(c + 2)] >> 2, o[i++] = e >> 8 & 255, o[i++] = e & 255), o;
}
function pf(n) {
  return at[n >> 18 & 63] + at[n >> 12 & 63] + at[n >> 6 & 63] + at[n & 63];
}
function mf(n, e, t) {
  for (var r, s = [], o = e; o < t; o += 3)
    r = (n[o] << 16 & 16711680) + (n[o + 1] << 8 & 65280) + (n[o + 2] & 255), s.push(pf(r));
  return s.join("");
}
function gf(n) {
  for (var e, t = n.length, r = t % 3, s = [], o = 16383, i = 0, a = t - r; i < a; i += o)
    s.push(mf(n, i, i + o > a ? a : i + o));
  return r === 1 ? (e = n[t - 1], s.push(
    at[e >> 2] + at[e << 4 & 63] + "=="
  )) : r === 2 && (e = (n[t - 2] << 8) + n[t - 1], s.push(
    at[e >> 10] + at[e >> 4 & 63] + at[e << 2 & 63] + "="
  )), s.join("");
}
var Vs = {};
/*! ieee754. BSD-3-Clause License. Feross Aboukhadijeh <https://feross.org/opensource> */
Vs.read = function(n, e, t, r, s) {
  var o, i, a = s * 8 - r - 1, c = (1 << a) - 1, l = c >> 1, u = -7, d = t ? s - 1 : 0, h = t ? -1 : 1, f = n[e + d];
  for (d += h, o = f & (1 << -u) - 1, f >>= -u, u += a; u > 0; o = o * 256 + n[e + d], d += h, u -= 8)
    ;
  for (i = o & (1 << -u) - 1, o >>= -u, u += r; u > 0; i = i * 256 + n[e + d], d += h, u -= 8)
    ;
  if (o === 0)
    o = 1 - l;
  else {
    if (o === c)
      return i ? NaN : (f ? -1 : 1) * (1 / 0);
    i = i + Math.pow(2, r), o = o - l;
  }
  return (f ? -1 : 1) * i * Math.pow(2, o - r);
};
Vs.write = function(n, e, t, r, s, o) {
  var i, a, c, l = o * 8 - s - 1, u = (1 << l) - 1, d = u >> 1, h = s === 23 ? Math.pow(2, -24) - Math.pow(2, -77) : 0, f = r ? 0 : o - 1, m = r ? 1 : -1, C = e < 0 || e === 0 && 1 / e < 0 ? 1 : 0;
  for (e = Math.abs(e), isNaN(e) || e === 1 / 0 ? (a = isNaN(e) ? 1 : 0, i = u) : (i = Math.floor(Math.log(e) / Math.LN2), e * (c = Math.pow(2, -i)) < 1 && (i--, c *= 2), i + d >= 1 ? e += h / c : e += h * Math.pow(2, 1 - d), e * c >= 2 && (i++, c /= 2), i + d >= u ? (a = 0, i = u) : i + d >= 1 ? (a = (e * c - 1) * Math.pow(2, s), i = i + d) : (a = e * Math.pow(2, d - 1) * Math.pow(2, s), i = 0)); s >= 8; n[t + f] = a & 255, f += m, a /= 256, s -= 8)
    ;
  for (i = i << s | a, l += s; l > 0; n[t + f] = i & 255, f += m, i /= 256, l -= 8)
    ;
  n[t + f - m] |= C * 128;
};
/*!
 * The buffer module from node.js, for the browser.
 *
 * @author   Feross Aboukhadijeh <https://feross.org>
 * @license  MIT
 */
(function(n) {
  const e = Pr, t = Vs, r = typeof Symbol == "function" && typeof Symbol.for == "function" ? Symbol.for("nodejs.util.inspect.custom") : null;
  n.Buffer = u, n.SlowBuffer = T, n.INSPECT_MAX_BYTES = 50;
  const s = 2147483647;
  n.kMaxLength = s;
  const { Uint8Array: o, ArrayBuffer: i, SharedArrayBuffer: a } = globalThis;
  u.TYPED_ARRAY_SUPPORT = c(), !u.TYPED_ARRAY_SUPPORT && typeof console < "u" && typeof console.error == "function" && console.error(
    "This browser lacks typed array (Uint8Array) support which is required by `buffer` v5.x. Use `buffer` v4.x if you require old browser support."
  );
  function c() {
    try {
      const b = new o(1), p = { foo: function() {
        return 42;
      } };
      return Object.setPrototypeOf(p, o.prototype), Object.setPrototypeOf(b, p), b.foo() === 42;
    } catch {
      return !1;
    }
  }
  Object.defineProperty(u.prototype, "parent", {
    enumerable: !0,
    get: function() {
      if (u.isBuffer(this))
        return this.buffer;
    }
  }), Object.defineProperty(u.prototype, "offset", {
    enumerable: !0,
    get: function() {
      if (u.isBuffer(this))
        return this.byteOffset;
    }
  });
  function l(b) {
    if (b > s)
      throw new RangeError('The value "' + b + '" is invalid for option "size"');
    const p = new o(b);
    return Object.setPrototypeOf(p, u.prototype), p;
  }
  function u(b, p, g) {
    if (typeof b == "number") {
      if (typeof p == "string")
        throw new TypeError(
          'The "string" argument must be of type string. Received type number'
        );
      return m(b);
    }
    return d(b, p, g);
  }
  u.poolSize = 8192;
  function d(b, p, g) {
    if (typeof b == "string")
      return C(b, p);
    if (i.isView(b))
      return x(b);
    if (b == null)
      throw new TypeError(
        "The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof b
      );
    if (rt(b, i) || b && rt(b.buffer, i) || typeof a < "u" && (rt(b, a) || b && rt(b.buffer, a)))
      return y(b, p, g);
    if (typeof b == "number")
      throw new TypeError(
        'The "value" argument must not be of type number. Received type number'
      );
    const $ = b.valueOf && b.valueOf();
    if ($ != null && $ !== b)
      return u.from($, p, g);
    const S = v(b);
    if (S) return S;
    if (typeof Symbol < "u" && Symbol.toPrimitive != null && typeof b[Symbol.toPrimitive] == "function")
      return u.from(b[Symbol.toPrimitive]("string"), p, g);
    throw new TypeError(
      "The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof b
    );
  }
  u.from = function(b, p, g) {
    return d(b, p, g);
  }, Object.setPrototypeOf(u.prototype, o.prototype), Object.setPrototypeOf(u, o);
  function h(b) {
    if (typeof b != "number")
      throw new TypeError('"size" argument must be of type number');
    if (b < 0)
      throw new RangeError('The value "' + b + '" is invalid for option "size"');
  }
  function f(b, p, g) {
    return h(b), b <= 0 ? l(b) : p !== void 0 ? typeof g == "string" ? l(b).fill(p, g) : l(b).fill(p) : l(b);
  }
  u.alloc = function(b, p, g) {
    return f(b, p, g);
  };
  function m(b) {
    return h(b), l(b < 0 ? 0 : I(b) | 0);
  }
  u.allocUnsafe = function(b) {
    return m(b);
  }, u.allocUnsafeSlow = function(b) {
    return m(b);
  };
  function C(b, p) {
    if ((typeof p != "string" || p === "") && (p = "utf8"), !u.isEncoding(p))
      throw new TypeError("Unknown encoding: " + p);
    const g = A(b, p) | 0;
    let $ = l(g);
    const S = $.write(b, p);
    return S !== g && ($ = $.slice(0, S)), $;
  }
  function w(b) {
    const p = b.length < 0 ? 0 : I(b.length) | 0, g = l(p);
    for (let $ = 0; $ < p; $ += 1)
      g[$] = b[$] & 255;
    return g;
  }
  function x(b) {
    if (rt(b, o)) {
      const p = new o(b);
      return y(p.buffer, p.byteOffset, p.byteLength);
    }
    return w(b);
  }
  function y(b, p, g) {
    if (p < 0 || b.byteLength < p)
      throw new RangeError('"offset" is outside of buffer bounds');
    if (b.byteLength < p + (g || 0))
      throw new RangeError('"length" is outside of buffer bounds');
    let $;
    return p === void 0 && g === void 0 ? $ = new o(b) : g === void 0 ? $ = new o(b, p) : $ = new o(b, p, g), Object.setPrototypeOf($, u.prototype), $;
  }
  function v(b) {
    if (u.isBuffer(b)) {
      const p = I(b.length) | 0, g = l(p);
      return g.length === 0 || b.copy(g, 0, 0, p), g;
    }
    if (b.length !== void 0)
      return typeof b.length != "number" || jr(b.length) ? l(0) : w(b);
    if (b.type === "Buffer" && Array.isArray(b.data))
      return w(b.data);
  }
  function I(b) {
    if (b >= s)
      throw new RangeError("Attempt to allocate Buffer larger than maximum size: 0x" + s.toString(16) + " bytes");
    return b | 0;
  }
  function T(b) {
    return +b != b && (b = 0), u.alloc(+b);
  }
  u.isBuffer = function(p) {
    return p != null && p._isBuffer === !0 && p !== u.prototype;
  }, u.compare = function(p, g) {
    if (rt(p, o) && (p = u.from(p, p.offset, p.byteLength)), rt(g, o) && (g = u.from(g, g.offset, g.byteLength)), !u.isBuffer(p) || !u.isBuffer(g))
      throw new TypeError(
        'The "buf1", "buf2" arguments must be one of type Buffer or Uint8Array'
      );
    if (p === g) return 0;
    let $ = p.length, S = g.length;
    for (let R = 0, N = Math.min($, S); R < N; ++R)
      if (p[R] !== g[R]) {
        $ = p[R], S = g[R];
        break;
      }
    return $ < S ? -1 : S < $ ? 1 : 0;
  }, u.isEncoding = function(p) {
    switch (String(p).toLowerCase()) {
      case "hex":
      case "utf8":
      case "utf-8":
      case "ascii":
      case "latin1":
      case "binary":
      case "base64":
      case "ucs2":
      case "ucs-2":
      case "utf16le":
      case "utf-16le":
        return !0;
      default:
        return !1;
    }
  }, u.concat = function(p, g) {
    if (!Array.isArray(p))
      throw new TypeError('"list" argument must be an Array of Buffers');
    if (p.length === 0)
      return u.alloc(0);
    let $;
    if (g === void 0)
      for (g = 0, $ = 0; $ < p.length; ++$)
        g += p[$].length;
    const S = u.allocUnsafe(g);
    let R = 0;
    for ($ = 0; $ < p.length; ++$) {
      let N = p[$];
      if (rt(N, o))
        R + N.length > S.length ? (u.isBuffer(N) || (N = u.from(N)), N.copy(S, R)) : o.prototype.set.call(
          S,
          N,
          R
        );
      else if (u.isBuffer(N))
        N.copy(S, R);
      else
        throw new TypeError('"list" argument must be an Array of Buffers');
      R += N.length;
    }
    return S;
  };
  function A(b, p) {
    if (u.isBuffer(b))
      return b.length;
    if (i.isView(b) || rt(b, i))
      return b.byteLength;
    if (typeof b != "string")
      throw new TypeError(
        'The "string" argument must be one of type string, Buffer, or ArrayBuffer. Received type ' + typeof b
      );
    const g = b.length, $ = arguments.length > 2 && arguments[2] === !0;
    if (!$ && g === 0) return 0;
    let S = !1;
    for (; ; )
      switch (p) {
        case "ascii":
        case "latin1":
        case "binary":
          return g;
        case "utf8":
        case "utf-8":
          return Xr(b).length;
        case "ucs2":
        case "ucs-2":
        case "utf16le":
        case "utf-16le":
          return g * 2;
        case "hex":
          return g >>> 1;
        case "base64":
          return xo(b).length;
        default:
          if (S)
            return $ ? -1 : Xr(b).length;
          p = ("" + p).toLowerCase(), S = !0;
      }
  }
  u.byteLength = A;
  function F(b, p, g) {
    let $ = !1;
    if ((p === void 0 || p < 0) && (p = 0), p > this.length || ((g === void 0 || g > this.length) && (g = this.length), g <= 0) || (g >>>= 0, p >>>= 0, g <= p))
      return "";
    for (b || (b = "utf8"); ; )
      switch (b) {
        case "hex":
          return nn(this, p, g);
        case "utf8":
        case "utf-8":
          return ke(this, p, g);
        case "ascii":
          return Ct(this, p, g);
        case "latin1":
        case "binary":
          return bt(this, p, g);
        case "base64":
          return Ne(this, p, g);
        case "ucs2":
        case "ucs-2":
        case "utf16le":
        case "utf-16le":
          return Pn(this, p, g);
        default:
          if ($) throw new TypeError("Unknown encoding: " + b);
          b = (b + "").toLowerCase(), $ = !0;
      }
  }
  u.prototype._isBuffer = !0;
  function k(b, p, g) {
    const $ = b[p];
    b[p] = b[g], b[g] = $;
  }
  u.prototype.swap16 = function() {
    const p = this.length;
    if (p % 2 !== 0)
      throw new RangeError("Buffer size must be a multiple of 16-bits");
    for (let g = 0; g < p; g += 2)
      k(this, g, g + 1);
    return this;
  }, u.prototype.swap32 = function() {
    const p = this.length;
    if (p % 4 !== 0)
      throw new RangeError("Buffer size must be a multiple of 32-bits");
    for (let g = 0; g < p; g += 4)
      k(this, g, g + 3), k(this, g + 1, g + 2);
    return this;
  }, u.prototype.swap64 = function() {
    const p = this.length;
    if (p % 8 !== 0)
      throw new RangeError("Buffer size must be a multiple of 64-bits");
    for (let g = 0; g < p; g += 8)
      k(this, g, g + 7), k(this, g + 1, g + 6), k(this, g + 2, g + 5), k(this, g + 3, g + 4);
    return this;
  }, u.prototype.toString = function() {
    const p = this.length;
    return p === 0 ? "" : arguments.length === 0 ? ke(this, 0, p) : F.apply(this, arguments);
  }, u.prototype.toLocaleString = u.prototype.toString, u.prototype.equals = function(p) {
    if (!u.isBuffer(p)) throw new TypeError("Argument must be a Buffer");
    return this === p ? !0 : u.compare(this, p) === 0;
  }, u.prototype.inspect = function() {
    let p = "";
    const g = n.INSPECT_MAX_BYTES;
    return p = this.toString("hex", 0, g).replace(/(.{2})/g, "$1 ").trim(), this.length > g && (p += " ... "), "<Buffer " + p + ">";
  }, r && (u.prototype[r] = u.prototype.inspect), u.prototype.compare = function(p, g, $, S, R) {
    if (rt(p, o) && (p = u.from(p, p.offset, p.byteLength)), !u.isBuffer(p))
      throw new TypeError(
        'The "target" argument must be one of type Buffer or Uint8Array. Received type ' + typeof p
      );
    if (g === void 0 && (g = 0), $ === void 0 && ($ = p ? p.length : 0), S === void 0 && (S = 0), R === void 0 && (R = this.length), g < 0 || $ > p.length || S < 0 || R > this.length)
      throw new RangeError("out of range index");
    if (S >= R && g >= $)
      return 0;
    if (S >= R)
      return -1;
    if (g >= $)
      return 1;
    if (g >>>= 0, $ >>>= 0, S >>>= 0, R >>>= 0, this === p) return 0;
    let N = R - S, W = $ - g;
    const ne = Math.min(N, W), ee = this.slice(S, R), re = p.slice(g, $);
    for (let Y = 0; Y < ne; ++Y)
      if (ee[Y] !== re[Y]) {
        N = ee[Y], W = re[Y];
        break;
      }
    return N < W ? -1 : W < N ? 1 : 0;
  };
  function U(b, p, g, $, S) {
    if (b.length === 0) return -1;
    if (typeof g == "string" ? ($ = g, g = 0) : g > 2147483647 ? g = 2147483647 : g < -2147483648 && (g = -2147483648), g = +g, jr(g) && (g = S ? 0 : b.length - 1), g < 0 && (g = b.length + g), g >= b.length) {
      if (S) return -1;
      g = b.length - 1;
    } else if (g < 0)
      if (S) g = 0;
      else return -1;
    if (typeof p == "string" && (p = u.from(p, $)), u.isBuffer(p))
      return p.length === 0 ? -1 : V(b, p, g, $, S);
    if (typeof p == "number")
      return p = p & 255, typeof o.prototype.indexOf == "function" ? S ? o.prototype.indexOf.call(b, p, g) : o.prototype.lastIndexOf.call(b, p, g) : V(b, [p], g, $, S);
    throw new TypeError("val must be string, number or Buffer");
  }
  function V(b, p, g, $, S) {
    let R = 1, N = b.length, W = p.length;
    if ($ !== void 0 && ($ = String($).toLowerCase(), $ === "ucs2" || $ === "ucs-2" || $ === "utf16le" || $ === "utf-16le")) {
      if (b.length < 2 || p.length < 2)
        return -1;
      R = 2, N /= 2, W /= 2, g /= 2;
    }
    function ne(re, Y) {
      return R === 1 ? re[Y] : re.readUInt16BE(Y * R);
    }
    let ee;
    if (S) {
      let re = -1;
      for (ee = g; ee < N; ee++)
        if (ne(b, ee) === ne(p, re === -1 ? 0 : ee - re)) {
          if (re === -1 && (re = ee), ee - re + 1 === W) return re * R;
        } else
          re !== -1 && (ee -= ee - re), re = -1;
    } else
      for (g + W > N && (g = N - W), ee = g; ee >= 0; ee--) {
        let re = !0;
        for (let Y = 0; Y < W; Y++)
          if (ne(b, ee + Y) !== ne(p, Y)) {
            re = !1;
            break;
          }
        if (re) return ee;
      }
    return -1;
  }
  u.prototype.includes = function(p, g, $) {
    return this.indexOf(p, g, $) !== -1;
  }, u.prototype.indexOf = function(p, g, $) {
    return U(this, p, g, $, !0);
  }, u.prototype.lastIndexOf = function(p, g, $) {
    return U(this, p, g, $, !1);
  };
  function G(b, p, g, $) {
    g = Number(g) || 0;
    const S = b.length - g;
    $ ? ($ = Number($), $ > S && ($ = S)) : $ = S;
    const R = p.length;
    $ > R / 2 && ($ = R / 2);
    let N;
    for (N = 0; N < $; ++N) {
      const W = parseInt(p.substr(N * 2, 2), 16);
      if (jr(W)) return N;
      b[g + N] = W;
    }
    return N;
  }
  function j(b, p, g, $) {
    return or(Xr(p, b.length - g), b, g, $);
  }
  function be(b, p, g, $) {
    return or(Sl(p), b, g, $);
  }
  function ie(b, p, g, $) {
    return or(xo(p), b, g, $);
  }
  function ce(b, p, g, $) {
    return or(El(p, b.length - g), b, g, $);
  }
  u.prototype.write = function(p, g, $, S) {
    if (g === void 0)
      S = "utf8", $ = this.length, g = 0;
    else if ($ === void 0 && typeof g == "string")
      S = g, $ = this.length, g = 0;
    else if (isFinite(g))
      g = g >>> 0, isFinite($) ? ($ = $ >>> 0, S === void 0 && (S = "utf8")) : (S = $, $ = void 0);
    else
      throw new Error(
        "Buffer.write(string, encoding, offset[, length]) is no longer supported"
      );
    const R = this.length - g;
    if (($ === void 0 || $ > R) && ($ = R), p.length > 0 && ($ < 0 || g < 0) || g > this.length)
      throw new RangeError("Attempt to write outside buffer bounds");
    S || (S = "utf8");
    let N = !1;
    for (; ; )
      switch (S) {
        case "hex":
          return G(this, p, g, $);
        case "utf8":
        case "utf-8":
          return j(this, p, g, $);
        case "ascii":
        case "latin1":
        case "binary":
          return be(this, p, g, $);
        case "base64":
          return ie(this, p, g, $);
        case "ucs2":
        case "ucs-2":
        case "utf16le":
        case "utf-16le":
          return ce(this, p, g, $);
        default:
          if (N) throw new TypeError("Unknown encoding: " + S);
          S = ("" + S).toLowerCase(), N = !0;
      }
  }, u.prototype.toJSON = function() {
    return {
      type: "Buffer",
      data: Array.prototype.slice.call(this._arr || this, 0)
    };
  };
  function Ne(b, p, g) {
    return p === 0 && g === b.length ? e.fromByteArray(b) : e.fromByteArray(b.slice(p, g));
  }
  function ke(b, p, g) {
    g = Math.min(b.length, g);
    const $ = [];
    let S = p;
    for (; S < g; ) {
      const R = b[S];
      let N = null, W = R > 239 ? 4 : R > 223 ? 3 : R > 191 ? 2 : 1;
      if (S + W <= g) {
        let ne, ee, re, Y;
        switch (W) {
          case 1:
            R < 128 && (N = R);
            break;
          case 2:
            ne = b[S + 1], (ne & 192) === 128 && (Y = (R & 31) << 6 | ne & 63, Y > 127 && (N = Y));
            break;
          case 3:
            ne = b[S + 1], ee = b[S + 2], (ne & 192) === 128 && (ee & 192) === 128 && (Y = (R & 15) << 12 | (ne & 63) << 6 | ee & 63, Y > 2047 && (Y < 55296 || Y > 57343) && (N = Y));
            break;
          case 4:
            ne = b[S + 1], ee = b[S + 2], re = b[S + 3], (ne & 192) === 128 && (ee & 192) === 128 && (re & 192) === 128 && (Y = (R & 15) << 18 | (ne & 63) << 12 | (ee & 63) << 6 | re & 63, Y > 65535 && Y < 1114112 && (N = Y));
        }
      }
      N === null ? (N = 65533, W = 1) : N > 65535 && (N -= 65536, $.push(N >>> 10 & 1023 | 55296), N = 56320 | N & 1023), $.push(N), S += W;
    }
    return nt($);
  }
  const le = 4096;
  function nt(b) {
    const p = b.length;
    if (p <= le)
      return String.fromCharCode.apply(String, b);
    let g = "", $ = 0;
    for (; $ < p; )
      g += String.fromCharCode.apply(
        String,
        b.slice($, $ += le)
      );
    return g;
  }
  function Ct(b, p, g) {
    let $ = "";
    g = Math.min(b.length, g);
    for (let S = p; S < g; ++S)
      $ += String.fromCharCode(b[S] & 127);
    return $;
  }
  function bt(b, p, g) {
    let $ = "";
    g = Math.min(b.length, g);
    for (let S = p; S < g; ++S)
      $ += String.fromCharCode(b[S]);
    return $;
  }
  function nn(b, p, g) {
    const $ = b.length;
    (!p || p < 0) && (p = 0), (!g || g < 0 || g > $) && (g = $);
    let S = "";
    for (let R = p; R < g; ++R)
      S += Rl[b[R]];
    return S;
  }
  function Pn(b, p, g) {
    const $ = b.slice(p, g);
    let S = "";
    for (let R = 0; R < $.length - 1; R += 2)
      S += String.fromCharCode($[R] + $[R + 1] * 256);
    return S;
  }
  u.prototype.slice = function(p, g) {
    const $ = this.length;
    p = ~~p, g = g === void 0 ? $ : ~~g, p < 0 ? (p += $, p < 0 && (p = 0)) : p > $ && (p = $), g < 0 ? (g += $, g < 0 && (g = 0)) : g > $ && (g = $), g < p && (g = p);
    const S = this.subarray(p, g);
    return Object.setPrototypeOf(S, u.prototype), S;
  };
  function ae(b, p, g) {
    if (b % 1 !== 0 || b < 0) throw new RangeError("offset is not uint");
    if (b + p > g) throw new RangeError("Trying to access beyond buffer length");
  }
  u.prototype.readUintLE = u.prototype.readUIntLE = function(p, g, $) {
    p = p >>> 0, g = g >>> 0, $ || ae(p, g, this.length);
    let S = this[p], R = 1, N = 0;
    for (; ++N < g && (R *= 256); )
      S += this[p + N] * R;
    return S;
  }, u.prototype.readUintBE = u.prototype.readUIntBE = function(p, g, $) {
    p = p >>> 0, g = g >>> 0, $ || ae(p, g, this.length);
    let S = this[p + --g], R = 1;
    for (; g > 0 && (R *= 256); )
      S += this[p + --g] * R;
    return S;
  }, u.prototype.readUint8 = u.prototype.readUInt8 = function(p, g) {
    return p = p >>> 0, g || ae(p, 1, this.length), this[p];
  }, u.prototype.readUint16LE = u.prototype.readUInt16LE = function(p, g) {
    return p = p >>> 0, g || ae(p, 2, this.length), this[p] | this[p + 1] << 8;
  }, u.prototype.readUint16BE = u.prototype.readUInt16BE = function(p, g) {
    return p = p >>> 0, g || ae(p, 2, this.length), this[p] << 8 | this[p + 1];
  }, u.prototype.readUint32LE = u.prototype.readUInt32LE = function(p, g) {
    return p = p >>> 0, g || ae(p, 4, this.length), (this[p] | this[p + 1] << 8 | this[p + 2] << 16) + this[p + 3] * 16777216;
  }, u.prototype.readUint32BE = u.prototype.readUInt32BE = function(p, g) {
    return p = p >>> 0, g || ae(p, 4, this.length), this[p] * 16777216 + (this[p + 1] << 16 | this[p + 2] << 8 | this[p + 3]);
  }, u.prototype.readBigUInt64LE = yt(function(p) {
    p = p >>> 0, sn(p, "offset");
    const g = this[p], $ = this[p + 7];
    (g === void 0 || $ === void 0) && Bn(p, this.length - 8);
    const S = g + this[++p] * 2 ** 8 + this[++p] * 2 ** 16 + this[++p] * 2 ** 24, R = this[++p] + this[++p] * 2 ** 8 + this[++p] * 2 ** 16 + $ * 2 ** 24;
    return BigInt(S) + (BigInt(R) << BigInt(32));
  }), u.prototype.readBigUInt64BE = yt(function(p) {
    p = p >>> 0, sn(p, "offset");
    const g = this[p], $ = this[p + 7];
    (g === void 0 || $ === void 0) && Bn(p, this.length - 8);
    const S = g * 2 ** 24 + this[++p] * 2 ** 16 + this[++p] * 2 ** 8 + this[++p], R = this[++p] * 2 ** 24 + this[++p] * 2 ** 16 + this[++p] * 2 ** 8 + $;
    return (BigInt(S) << BigInt(32)) + BigInt(R);
  }), u.prototype.readIntLE = function(p, g, $) {
    p = p >>> 0, g = g >>> 0, $ || ae(p, g, this.length);
    let S = this[p], R = 1, N = 0;
    for (; ++N < g && (R *= 256); )
      S += this[p + N] * R;
    return R *= 128, S >= R && (S -= Math.pow(2, 8 * g)), S;
  }, u.prototype.readIntBE = function(p, g, $) {
    p = p >>> 0, g = g >>> 0, $ || ae(p, g, this.length);
    let S = g, R = 1, N = this[p + --S];
    for (; S > 0 && (R *= 256); )
      N += this[p + --S] * R;
    return R *= 128, N >= R && (N -= Math.pow(2, 8 * g)), N;
  }, u.prototype.readInt8 = function(p, g) {
    return p = p >>> 0, g || ae(p, 1, this.length), this[p] & 128 ? (255 - this[p] + 1) * -1 : this[p];
  }, u.prototype.readInt16LE = function(p, g) {
    p = p >>> 0, g || ae(p, 2, this.length);
    const $ = this[p] | this[p + 1] << 8;
    return $ & 32768 ? $ | 4294901760 : $;
  }, u.prototype.readInt16BE = function(p, g) {
    p = p >>> 0, g || ae(p, 2, this.length);
    const $ = this[p + 1] | this[p] << 8;
    return $ & 32768 ? $ | 4294901760 : $;
  }, u.prototype.readInt32LE = function(p, g) {
    return p = p >>> 0, g || ae(p, 4, this.length), this[p] | this[p + 1] << 8 | this[p + 2] << 16 | this[p + 3] << 24;
  }, u.prototype.readInt32BE = function(p, g) {
    return p = p >>> 0, g || ae(p, 4, this.length), this[p] << 24 | this[p + 1] << 16 | this[p + 2] << 8 | this[p + 3];
  }, u.prototype.readBigInt64LE = yt(function(p) {
    p = p >>> 0, sn(p, "offset");
    const g = this[p], $ = this[p + 7];
    (g === void 0 || $ === void 0) && Bn(p, this.length - 8);
    const S = this[p + 4] + this[p + 5] * 2 ** 8 + this[p + 6] * 2 ** 16 + ($ << 24);
    return (BigInt(S) << BigInt(32)) + BigInt(g + this[++p] * 2 ** 8 + this[++p] * 2 ** 16 + this[++p] * 2 ** 24);
  }), u.prototype.readBigInt64BE = yt(function(p) {
    p = p >>> 0, sn(p, "offset");
    const g = this[p], $ = this[p + 7];
    (g === void 0 || $ === void 0) && Bn(p, this.length - 8);
    const S = (g << 24) + // Overflow
    this[++p] * 2 ** 16 + this[++p] * 2 ** 8 + this[++p];
    return (BigInt(S) << BigInt(32)) + BigInt(this[++p] * 2 ** 24 + this[++p] * 2 ** 16 + this[++p] * 2 ** 8 + $);
  }), u.prototype.readFloatLE = function(p, g) {
    return p = p >>> 0, g || ae(p, 4, this.length), t.read(this, p, !0, 23, 4);
  }, u.prototype.readFloatBE = function(p, g) {
    return p = p >>> 0, g || ae(p, 4, this.length), t.read(this, p, !1, 23, 4);
  }, u.prototype.readDoubleLE = function(p, g) {
    return p = p >>> 0, g || ae(p, 8, this.length), t.read(this, p, !0, 52, 8);
  }, u.prototype.readDoubleBE = function(p, g) {
    return p = p >>> 0, g || ae(p, 8, this.length), t.read(this, p, !1, 52, 8);
  };
  function he(b, p, g, $, S, R) {
    if (!u.isBuffer(b)) throw new TypeError('"buffer" argument must be a Buffer instance');
    if (p > S || p < R) throw new RangeError('"value" argument is out of bounds');
    if (g + $ > b.length) throw new RangeError("Index out of range");
  }
  u.prototype.writeUintLE = u.prototype.writeUIntLE = function(p, g, $, S) {
    if (p = +p, g = g >>> 0, $ = $ >>> 0, !S) {
      const W = Math.pow(2, 8 * $) - 1;
      he(this, p, g, $, W, 0);
    }
    let R = 1, N = 0;
    for (this[g] = p & 255; ++N < $ && (R *= 256); )
      this[g + N] = p / R & 255;
    return g + $;
  }, u.prototype.writeUintBE = u.prototype.writeUIntBE = function(p, g, $, S) {
    if (p = +p, g = g >>> 0, $ = $ >>> 0, !S) {
      const W = Math.pow(2, 8 * $) - 1;
      he(this, p, g, $, W, 0);
    }
    let R = $ - 1, N = 1;
    for (this[g + R] = p & 255; --R >= 0 && (N *= 256); )
      this[g + R] = p / N & 255;
    return g + $;
  }, u.prototype.writeUint8 = u.prototype.writeUInt8 = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 1, 255, 0), this[g] = p & 255, g + 1;
  }, u.prototype.writeUint16LE = u.prototype.writeUInt16LE = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 2, 65535, 0), this[g] = p & 255, this[g + 1] = p >>> 8, g + 2;
  }, u.prototype.writeUint16BE = u.prototype.writeUInt16BE = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 2, 65535, 0), this[g] = p >>> 8, this[g + 1] = p & 255, g + 2;
  }, u.prototype.writeUint32LE = u.prototype.writeUInt32LE = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 4, 4294967295, 0), this[g + 3] = p >>> 24, this[g + 2] = p >>> 16, this[g + 1] = p >>> 8, this[g] = p & 255, g + 4;
  }, u.prototype.writeUint32BE = u.prototype.writeUInt32BE = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 4, 4294967295, 0), this[g] = p >>> 24, this[g + 1] = p >>> 16, this[g + 2] = p >>> 8, this[g + 3] = p & 255, g + 4;
  };
  function _n(b, p, g, $, S) {
    go(p, $, S, b, g, 7);
    let R = Number(p & BigInt(4294967295));
    b[g++] = R, R = R >> 8, b[g++] = R, R = R >> 8, b[g++] = R, R = R >> 8, b[g++] = R;
    let N = Number(p >> BigInt(32) & BigInt(4294967295));
    return b[g++] = N, N = N >> 8, b[g++] = N, N = N >> 8, b[g++] = N, N = N >> 8, b[g++] = N, g;
  }
  function uo(b, p, g, $, S) {
    go(p, $, S, b, g, 7);
    let R = Number(p & BigInt(4294967295));
    b[g + 7] = R, R = R >> 8, b[g + 6] = R, R = R >> 8, b[g + 5] = R, R = R >> 8, b[g + 4] = R;
    let N = Number(p >> BigInt(32) & BigInt(4294967295));
    return b[g + 3] = N, N = N >> 8, b[g + 2] = N, N = N >> 8, b[g + 1] = N, N = N >> 8, b[g] = N, g + 8;
  }
  u.prototype.writeBigUInt64LE = yt(function(p, g = 0) {
    return _n(this, p, g, BigInt(0), BigInt("0xffffffffffffffff"));
  }), u.prototype.writeBigUInt64BE = yt(function(p, g = 0) {
    return uo(this, p, g, BigInt(0), BigInt("0xffffffffffffffff"));
  }), u.prototype.writeIntLE = function(p, g, $, S) {
    if (p = +p, g = g >>> 0, !S) {
      const ne = Math.pow(2, 8 * $ - 1);
      he(this, p, g, $, ne - 1, -ne);
    }
    let R = 0, N = 1, W = 0;
    for (this[g] = p & 255; ++R < $ && (N *= 256); )
      p < 0 && W === 0 && this[g + R - 1] !== 0 && (W = 1), this[g + R] = (p / N >> 0) - W & 255;
    return g + $;
  }, u.prototype.writeIntBE = function(p, g, $, S) {
    if (p = +p, g = g >>> 0, !S) {
      const ne = Math.pow(2, 8 * $ - 1);
      he(this, p, g, $, ne - 1, -ne);
    }
    let R = $ - 1, N = 1, W = 0;
    for (this[g + R] = p & 255; --R >= 0 && (N *= 256); )
      p < 0 && W === 0 && this[g + R + 1] !== 0 && (W = 1), this[g + R] = (p / N >> 0) - W & 255;
    return g + $;
  }, u.prototype.writeInt8 = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 1, 127, -128), p < 0 && (p = 255 + p + 1), this[g] = p & 255, g + 1;
  }, u.prototype.writeInt16LE = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 2, 32767, -32768), this[g] = p & 255, this[g + 1] = p >>> 8, g + 2;
  }, u.prototype.writeInt16BE = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 2, 32767, -32768), this[g] = p >>> 8, this[g + 1] = p & 255, g + 2;
  }, u.prototype.writeInt32LE = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 4, 2147483647, -2147483648), this[g] = p & 255, this[g + 1] = p >>> 8, this[g + 2] = p >>> 16, this[g + 3] = p >>> 24, g + 4;
  }, u.prototype.writeInt32BE = function(p, g, $) {
    return p = +p, g = g >>> 0, $ || he(this, p, g, 4, 2147483647, -2147483648), p < 0 && (p = 4294967295 + p + 1), this[g] = p >>> 24, this[g + 1] = p >>> 16, this[g + 2] = p >>> 8, this[g + 3] = p & 255, g + 4;
  }, u.prototype.writeBigInt64LE = yt(function(p, g = 0) {
    return _n(this, p, g, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
  }), u.prototype.writeBigInt64BE = yt(function(p, g = 0) {
    return uo(this, p, g, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
  });
  function ho(b, p, g, $, S, R) {
    if (g + $ > b.length) throw new RangeError("Index out of range");
    if (g < 0) throw new RangeError("Index out of range");
  }
  function fo(b, p, g, $, S) {
    return p = +p, g = g >>> 0, S || ho(b, p, g, 4), t.write(b, p, g, $, 23, 4), g + 4;
  }
  u.prototype.writeFloatLE = function(p, g, $) {
    return fo(this, p, g, !0, $);
  }, u.prototype.writeFloatBE = function(p, g, $) {
    return fo(this, p, g, !1, $);
  };
  function po(b, p, g, $, S) {
    return p = +p, g = g >>> 0, S || ho(b, p, g, 8), t.write(b, p, g, $, 52, 8), g + 8;
  }
  u.prototype.writeDoubleLE = function(p, g, $) {
    return po(this, p, g, !0, $);
  }, u.prototype.writeDoubleBE = function(p, g, $) {
    return po(this, p, g, !1, $);
  }, u.prototype.copy = function(p, g, $, S) {
    if (!u.isBuffer(p)) throw new TypeError("argument should be a Buffer");
    if ($ || ($ = 0), !S && S !== 0 && (S = this.length), g >= p.length && (g = p.length), g || (g = 0), S > 0 && S < $ && (S = $), S === $ || p.length === 0 || this.length === 0) return 0;
    if (g < 0)
      throw new RangeError("targetStart out of bounds");
    if ($ < 0 || $ >= this.length) throw new RangeError("Index out of range");
    if (S < 0) throw new RangeError("sourceEnd out of bounds");
    S > this.length && (S = this.length), p.length - g < S - $ && (S = p.length - g + $);
    const R = S - $;
    return this === p && typeof o.prototype.copyWithin == "function" ? this.copyWithin(g, $, S) : o.prototype.set.call(
      p,
      this.subarray($, S),
      g
    ), R;
  }, u.prototype.fill = function(p, g, $, S) {
    if (typeof p == "string") {
      if (typeof g == "string" ? (S = g, g = 0, $ = this.length) : typeof $ == "string" && (S = $, $ = this.length), S !== void 0 && typeof S != "string")
        throw new TypeError("encoding must be a string");
      if (typeof S == "string" && !u.isEncoding(S))
        throw new TypeError("Unknown encoding: " + S);
      if (p.length === 1) {
        const N = p.charCodeAt(0);
        (S === "utf8" && N < 128 || S === "latin1") && (p = N);
      }
    } else typeof p == "number" ? p = p & 255 : typeof p == "boolean" && (p = Number(p));
    if (g < 0 || this.length < g || this.length < $)
      throw new RangeError("Out of range index");
    if ($ <= g)
      return this;
    g = g >>> 0, $ = $ === void 0 ? this.length : $ >>> 0, p || (p = 0);
    let R;
    if (typeof p == "number")
      for (R = g; R < $; ++R)
        this[R] = p;
    else {
      const N = u.isBuffer(p) ? p : u.from(p, S), W = N.length;
      if (W === 0)
        throw new TypeError('The value "' + p + '" is invalid for argument "value"');
      for (R = 0; R < $ - g; ++R)
        this[R + g] = N[R % W];
    }
    return this;
  };
  const rn = {};
  function Hr(b, p, g) {
    rn[b] = class extends g {
      constructor() {
        super(), Object.defineProperty(this, "message", {
          value: p.apply(this, arguments),
          writable: !0,
          configurable: !0
        }), this.name = `${this.name} [${b}]`, this.stack, delete this.name;
      }
      get code() {
        return b;
      }
      set code(S) {
        Object.defineProperty(this, "code", {
          configurable: !0,
          enumerable: !0,
          value: S,
          writable: !0
        });
      }
      toString() {
        return `${this.name} [${b}]: ${this.message}`;
      }
    };
  }
  Hr(
    "ERR_BUFFER_OUT_OF_BOUNDS",
    function(b) {
      return b ? `${b} is outside of buffer bounds` : "Attempt to access memory outside buffer bounds";
    },
    RangeError
  ), Hr(
    "ERR_INVALID_ARG_TYPE",
    function(b, p) {
      return `The "${b}" argument must be of type number. Received type ${typeof p}`;
    },
    TypeError
  ), Hr(
    "ERR_OUT_OF_RANGE",
    function(b, p, g) {
      let $ = `The value of "${b}" is out of range.`, S = g;
      return Number.isInteger(g) && Math.abs(g) > 2 ** 32 ? S = mo(String(g)) : typeof g == "bigint" && (S = String(g), (g > BigInt(2) ** BigInt(32) || g < -(BigInt(2) ** BigInt(32))) && (S = mo(S)), S += "n"), $ += ` It must be ${p}. Received ${S}`, $;
    },
    RangeError
  );
  function mo(b) {
    let p = "", g = b.length;
    const $ = b[0] === "-" ? 1 : 0;
    for (; g >= $ + 4; g -= 3)
      p = `_${b.slice(g - 3, g)}${p}`;
    return `${b.slice(0, g)}${p}`;
  }
  function $l(b, p, g) {
    sn(p, "offset"), (b[p] === void 0 || b[p + g] === void 0) && Bn(p, b.length - (g + 1));
  }
  function go(b, p, g, $, S, R) {
    if (b > g || b < p) {
      const N = typeof p == "bigint" ? "n" : "";
      let W;
      throw p === 0 || p === BigInt(0) ? W = `>= 0${N} and < 2${N} ** ${(R + 1) * 8}${N}` : W = `>= -(2${N} ** ${(R + 1) * 8 - 1}${N}) and < 2 ** ${(R + 1) * 8 - 1}${N}`, new rn.ERR_OUT_OF_RANGE("value", W, b);
    }
    $l($, S, R);
  }
  function sn(b, p) {
    if (typeof b != "number")
      throw new rn.ERR_INVALID_ARG_TYPE(p, "number", b);
  }
  function Bn(b, p, g) {
    throw Math.floor(b) !== b ? (sn(b, g), new rn.ERR_OUT_OF_RANGE("offset", "an integer", b)) : p < 0 ? new rn.ERR_BUFFER_OUT_OF_BOUNDS() : new rn.ERR_OUT_OF_RANGE(
      "offset",
      `>= 0 and <= ${p}`,
      b
    );
  }
  const vl = /[^+/0-9A-Za-z-_]/g;
  function Il(b) {
    if (b = b.split("=")[0], b = b.trim().replace(vl, ""), b.length < 2) return "";
    for (; b.length % 4 !== 0; )
      b = b + "=";
    return b;
  }
  function Xr(b, p) {
    p = p || 1 / 0;
    let g;
    const $ = b.length;
    let S = null;
    const R = [];
    for (let N = 0; N < $; ++N) {
      if (g = b.charCodeAt(N), g > 55295 && g < 57344) {
        if (!S) {
          if (g > 56319) {
            (p -= 3) > -1 && R.push(239, 191, 189);
            continue;
          } else if (N + 1 === $) {
            (p -= 3) > -1 && R.push(239, 191, 189);
            continue;
          }
          S = g;
          continue;
        }
        if (g < 56320) {
          (p -= 3) > -1 && R.push(239, 191, 189), S = g;
          continue;
        }
        g = (S - 55296 << 10 | g - 56320) + 65536;
      } else S && (p -= 3) > -1 && R.push(239, 191, 189);
      if (S = null, g < 128) {
        if ((p -= 1) < 0) break;
        R.push(g);
      } else if (g < 2048) {
        if ((p -= 2) < 0) break;
        R.push(
          g >> 6 | 192,
          g & 63 | 128
        );
      } else if (g < 65536) {
        if ((p -= 3) < 0) break;
        R.push(
          g >> 12 | 224,
          g >> 6 & 63 | 128,
          g & 63 | 128
        );
      } else if (g < 1114112) {
        if ((p -= 4) < 0) break;
        R.push(
          g >> 18 | 240,
          g >> 12 & 63 | 128,
          g >> 6 & 63 | 128,
          g & 63 | 128
        );
      } else
        throw new Error("Invalid code point");
    }
    return R;
  }
  function Sl(b) {
    const p = [];
    for (let g = 0; g < b.length; ++g)
      p.push(b.charCodeAt(g) & 255);
    return p;
  }
  function El(b, p) {
    let g, $, S;
    const R = [];
    for (let N = 0; N < b.length && !((p -= 2) < 0); ++N)
      g = b.charCodeAt(N), $ = g >> 8, S = g % 256, R.push(S), R.push($);
    return R;
  }
  function xo(b) {
    return e.toByteArray(Il(b));
  }
  function or(b, p, g, $) {
    let S;
    for (S = 0; S < $ && !(S + g >= p.length || S >= b.length); ++S)
      p[S + g] = b[S];
    return S;
  }
  function rt(b, p) {
    return b instanceof p || b != null && b.constructor != null && b.constructor.name != null && b.constructor.name === p.name;
  }
  function jr(b) {
    return b !== b;
  }
  const Rl = function() {
    const b = "0123456789abcdef", p = new Array(256);
    for (let g = 0; g < 16; ++g) {
      const $ = g * 16;
      for (let S = 0; S < 16; ++S)
        p[$ + S] = b[g] + b[S];
    }
    return p;
  }();
  function yt(b) {
    return typeof BigInt > "u" ? Tl : b;
  }
  function Tl() {
    throw new Error("BigInt not supported");
  }
})(Us);
const _r = Us.Buffer, AE = Us.Buffer;
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function xf(n, e) {
  let t = n;
  if (ze(n))
    return e === "string" ? [] : [n.length];
  if (ua(n)) {
    const s = n.channels || "RGBA";
    return [n.height, n.width * s.length];
  } else if (da(n))
    return [n.buffer.size / (e == null ? 4 : br(e))];
  if (!Array.isArray(n))
    return [];
  const r = [];
  for (; Array.isArray(t) || ze(t) && e !== "string"; )
    r.push(t.length), t = t[0];
  return Array.isArray(n) && E().getBool("TENSORLIKE_CHECK_SHAPE_CONSISTENCY") && wa(n, r, []), r;
}
function wa(n, e, t) {
  if (t = t || [], !Array.isArray(n) && !ze(n)) {
    O(e.length === 0, () => `Element arr[${t.join("][")}] is a primitive, but should be an array/TypedArray of ${e[0]} elements`);
    return;
  }
  O(e.length > 0, () => `Element arr[${t.join("][")}] should be a primitive, but is an array of ${n.length} elements`), O(n.length === e[0], () => `Element arr[${t.join("][")}] should have ${e[0]} elements, but has ${n.length} elements`);
  const r = e.slice(1);
  for (let s = 0; s < n.length; ++s)
    wa(n[s], r, t.concat(s));
}
function Oo(n, e, t, r) {
  if (n !== "string_or_numeric") {
    if (n == null)
      throw new Error("Expected dtype cannot be null.");
    if (n !== "numeric" && n !== e || n === "numeric" && e === "string")
      throw new Error(`Argument '${t}' passed to '${r}' must be ${n} tensor, but got ${e} tensor`);
  }
}
function X(n, e, t, r = "numeric") {
  if (n instanceof Me)
    return Oo(r, n.dtype, e, t), n;
  let s = Yn(n);
  if (s !== "string" && ["bool", "int32", "float32"].indexOf(r) >= 0 && (s = r), Oo(r, s, e, t), n == null || !ze(n) && !Array.isArray(n) && typeof n != "number" && typeof n != "boolean" && typeof n != "string") {
    const c = n == null ? "null" : n.constructor.name;
    throw new Error(`Argument '${e}' passed to '${t}' must be a Tensor or TensorLike, but got '${c}'`);
  }
  const o = xf(n, s);
  !ze(n) && !Array.isArray(n) && (n = [n]);
  const a = s !== "string" ? Or(n, s) : Vt(n, [], !0);
  return M.makeTensor(a, o, s);
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const wf = "__op";
function te(n) {
  const e = Object.keys(n);
  if (e.length !== 1)
    throw new Error(`Please provide an object with a single key (operation name) mapping to a function. Got an object with ${e.length} keys.`);
  let t = e[0];
  const r = n[t];
  t.endsWith("_") && (t = t.substring(0, t.length - 1)), t = t + wf;
  const s = (...o) => {
    M.startScope(t);
    try {
      const i = r(...o);
      return Ds(i) && console.error("Cannot return a Promise inside of tidy."), M.endScope(i), i;
    } catch (i) {
      throw M.endScope(null), i;
    }
  };
  return Object.defineProperty(s, "name", { value: t, configurable: !0 }), s;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Cf(n, e) {
  const t = X(n, "real", "complex"), r = X(e, "imag", "complex");
  vi(t.shape, r.shape, `real and imag shapes, ${t.shape} and ${r.shape}, must match in call to tf.complex().`);
  const s = { real: t, imag: r };
  return M.runKernel(Fi, s);
}
const bf = /* @__PURE__ */ te({ complex_: Cf });
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function yf(n, e, t, r) {
  if (r == null)
    r = Yn(n);
  else if (r === "complex64")
    throw new Error("Cannot construct a complex64 tensor directly. Please use tf.complex(real, imag).");
  if (da(n) || ua(n)) {
    if (r !== "float32" && r !== "int32")
      throw new Error(`Creating tensor from GPU data only supports 'float32'|'int32' dtype, while the dtype is ${r}.`);
    return M.backend.createTensorFromGPUData(n, e || t, r);
  }
  if (!ze(n) && !Array.isArray(n) && typeof n != "number" && typeof n != "boolean" && typeof n != "string")
    throw new Error("values passed to tensor(values) must be a number/boolean/string or an array of numbers/booleans/strings, or a TypedArray");
  if (e != null) {
    Qn(e);
    const s = _(e), o = _(t);
    O(s === o, () => `Based on the provided shape, [${e}], the tensor should have ${s} values but has ${o}`);
    for (let i = 0; i < t.length; ++i) {
      const a = t[i], c = i === t.length - 1 ? a !== _(e.slice(i)) : !0;
      O(t[i] === e[i] || !c, () => `Error creating a new Tensor. Inferred shape (${t}) does not match the provided shape (${e}). `);
    }
  }
  return !ze(n) && !Array.isArray(n) && (n = [n]), e = e || t, n = r !== "string" ? Or(n, r) : Vt(n, [], !0), M.makeTensor(n, e, r);
}
class Yt {
  /**
   * Concatenate a number of ArrayBuffers into one.
   *
   * @param buffers An array of ArrayBuffers to concatenate, or a single
   *     ArrayBuffer.
   * @returns Result of concatenating `buffers` in order.
   */
  static join(e) {
    return new Yt(e).slice();
  }
  constructor(e) {
    if (this.shards = [], this.previousShardIndex = 0, e == null || (e instanceof Array || (e = [e]), e = e.map((r) => ze(r) ? r.buffer : r), e.length === 0))
      return;
    this.bufferUniformSize = e[0].byteLength;
    let t = 0;
    for (let r = 0; r < e.length; r++) {
      const s = e[r];
      r !== e.length - 1 && s.byteLength !== this.bufferUniformSize && (this.bufferUniformSize = void 0);
      const o = t + s.byteLength;
      this.shards.push({ buffer: s, start: t, end: o }), t = o;
    }
    this.shards.length === 0 && (this.byteLength = 0), this.byteLength = this.shards[this.shards.length - 1].end;
  }
  slice(e = 0, t = this.byteLength) {
    if (this.shards.length === 0)
      return new ArrayBuffer(0);
    if (e = isNaN(Number(e)) ? 0 : e, t = isNaN(Number(t)) ? 0 : t, e = Math.max(0, e), t = Math.min(this.byteLength, t), t <= e)
      return new ArrayBuffer(0);
    const r = this.findShardForByte(e);
    if (r === -1)
      throw new Error(`Could not find start shard for byte ${e}`);
    const s = t - e, o = new ArrayBuffer(s), i = new Uint8Array(o);
    let a = 0;
    for (let c = r; c < this.shards.length; c++) {
      const l = this.shards[c], d = e + a - l.start, h = a, m = Math.min(t, l.end) - l.start, C = new Uint8Array(l.buffer, d, m - d);
      if (i.set(C, h), a += C.length, t < l.end)
        break;
    }
    return o;
  }
  /**
   * Get the index of the shard that contains the byte at `byteIndex`.
   */
  findShardForByte(e) {
    if (this.shards.length === 0 || e < 0 || e >= this.byteLength)
      return -1;
    if (this.bufferUniformSize != null)
      return this.previousShardIndex = Math.floor(e / this.bufferUniformSize), this.previousShardIndex;
    function t(s) {
      return e < s.start ? -1 : e >= s.end ? 1 : 0;
    }
    if (t(this.shards[this.previousShardIndex]) === 0)
      return this.previousShardIndex;
    const r = $f(this.shards, t);
    return r === -1 ? -1 : (this.previousShardIndex = r, this.previousShardIndex);
  }
}
function $f(n, e) {
  let t = 0, r = n.length;
  for (; t <= r; ) {
    const s = Math.floor((r - t) / 2) + t, o = e(n[s]);
    if (o === 0)
      return s;
    o < 0 ? r = s : t = s + 1;
  }
  return -1;
}
const Ws = typeof _r < "u" && (typeof Blob > "u" || typeof atob > "u" || typeof btoa > "u");
function Po(n) {
  return Ws ? _r.byteLength(n, "utf8") : new Blob([n]).size;
}
function vf(n) {
  if (Ws)
    return _r.from(n).toString("base64");
  const e = new Uint8Array(n);
  let t = "";
  for (let r = 0, s = e.length; r < s; r++)
    t += String.fromCharCode(e[r]);
  return btoa(t);
}
function If(n) {
  if (Ws) {
    const r = _r.from(n, "base64");
    return r.buffer.slice(r.byteOffset, r.byteOffset + r.byteLength);
  }
  const e = atob(n), t = new Uint8Array(e.length);
  for (let r = 0; r < e.length; ++r)
    t.set([e.charCodeAt(r)], r);
  return t.buffer;
}
function Ca(n, e) {
  const t = {
    modelTopology: n.modelTopology,
    format: n.format,
    generatedBy: n.generatedBy,
    convertedBy: n.convertedBy,
    weightsManifest: e
  };
  return n.signature != null && (t.signature = n.signature), n.userDefinedMetadata != null && (t.userDefinedMetadata = n.userDefinedMetadata), n.modelInitializer != null && (t.modelInitializer = n.modelInitializer), n.initializerSignature != null && (t.initializerSignature = n.initializerSignature), n.trainingConfig != null && (t.trainingConfig = n.trainingConfig), t;
}
function Sf(n, e, t) {
  const r = {
    modelTopology: n.modelTopology,
    format: n.format,
    generatedBy: n.generatedBy,
    convertedBy: n.convertedBy
  };
  if (n.trainingConfig != null && (r.trainingConfig = n.trainingConfig), n.weightsManifest != null) {
    if (!e)
      throw new Error("modelJSON has weightsManifest but weightSpecs is null");
    if (!t)
      throw new Error("modelJSON has weightsManifest but weightData is null");
    r.weightSpecs = e, r.weightData = t;
  }
  return n.signature != null && (r.signature = n.signature), n.userDefinedMetadata != null && (r.userDefinedMetadata = n.userDefinedMetadata), n.modelInitializer != null && (r.modelInitializer = n.modelInitializer), n.initializerSignature != null && (r.initializerSignature = n.initializerSignature), r;
}
async function Ef(n, e) {
  let t, r;
  return n.weightsManifest != null && ([t, r] = await e(n.weightsManifest)), Sf(n, t, r);
}
function Br(n) {
  if (n.modelTopology instanceof ArrayBuffer)
    throw new Error("Expected JSON model topology, received ArrayBuffer.");
  return {
    dateSaved: /* @__PURE__ */ new Date(),
    modelTopologyType: "JSON",
    modelTopologyBytes: n.modelTopology == null ? 0 : Po(JSON.stringify(n.modelTopology)),
    weightSpecsBytes: n.weightSpecs == null ? 0 : Po(JSON.stringify(n.weightSpecs)),
    weightDataBytes: n.weightData == null ? 0 : new Yt(n.weightData).byteLength
  };
}
function Rf(n) {
  const e = [];
  for (const t of n)
    e.push(...t.weights);
  return e;
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class fe {
  constructor() {
    this.saveRouters = [], this.loadRouters = [];
  }
  static getInstance() {
    return fe.instance == null && (fe.instance = new fe()), fe.instance;
  }
  /**
   * Register a save-handler router.
   *
   * @param saveRouter A function that maps a URL-like string onto an instance
   * of `IOHandler` with the `save` method defined or `null`.
   */
  static registerSaveRouter(e) {
    fe.getInstance().saveRouters.push(e);
  }
  /**
   * Register a load-handler router.
   *
   * @param loadRouter A function that maps a URL-like string onto an instance
   * of `IOHandler` with the `load` method defined or `null`.
   */
  static registerLoadRouter(e) {
    fe.getInstance().loadRouters.push(e);
  }
  /**
   * Look up IOHandler for saving, given a URL-like string.
   *
   * @param url
   * @returns If only one match is found, an instance of IOHandler with the
   * `save` method defined. If no match is found, `null`.
   * @throws Error, if more than one match is found.
   */
  static getSaveHandlers(e) {
    return fe.getHandlers(e, "save");
  }
  /**
   * Look up IOHandler for loading, given a URL-like string.
   *
   * @param url
   * @param loadOptions Optional, custom load options.
   * @returns All valid handlers for `url`, given the currently registered
   *   handler routers.
   */
  static getLoadHandlers(e, t) {
    return fe.getHandlers(e, "load", t);
  }
  static getHandlers(e, t, r) {
    const s = [];
    return (t === "load" ? fe.getInstance().loadRouters : fe.getInstance().saveRouters).forEach((i) => {
      const a = i(e, r);
      a !== null && s.push(a);
    }), s;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ws = "tensorflowjs", Cs = 1, Bt = "models_store", It = "model_info_store";
function ba() {
  if (!E().getBool("IS_BROWSER"))
    throw new Error("Failed to obtain IndexedDB factory because the current environmentis not a web browser.");
  const n = typeof window > "u" ? self : window, e = n.indexedDB || n.mozIndexedDB || n.webkitIndexedDB || n.msIndexedDB || n.shimIndexedDB;
  if (e == null)
    throw new Error("The current browser does not appear to support IndexedDB.");
  return e;
}
function bs(n) {
  const e = n.result;
  e.createObjectStore(Bt, { keyPath: "modelPath" }), e.createObjectStore(It, { keyPath: "modelPath" });
}
class Wt {
  constructor(e) {
    if (this.indexedDB = ba(), e == null || !e)
      throw new Error("For IndexedDB, modelPath must not be null, undefined or empty.");
    this.modelPath = e;
  }
  async save(e) {
    if (e.modelTopology instanceof ArrayBuffer)
      throw new Error("BrowserLocalStorage.save() does not support saving model topology in binary formats yet.");
    return this.databaseAction(this.modelPath, e);
  }
  async load() {
    return this.databaseAction(this.modelPath);
  }
  /**
   * Perform database action to put model artifacts into or read model artifacts
   * from IndexedDB object store.
   *
   * Whether the action is put or get depends on whether `modelArtifacts` is
   * specified. If it is specified, the action will be put; otherwise the action
   * will be get.
   *
   * @param modelPath A unique string path for the model.
   * @param modelArtifacts If specified, it will be the model artifacts to be
   *   stored in IndexedDB.
   * @returns A `Promise` of `SaveResult`, if the action is put, or a `Promise`
   *   of `ModelArtifacts`, if the action is get.
   */
  databaseAction(e, t) {
    return new Promise((r, s) => {
      const o = this.indexedDB.open(ws, Cs);
      o.onupgradeneeded = () => bs(o), o.onsuccess = () => {
        const i = o.result;
        if (t == null) {
          const a = i.transaction(Bt, "readonly"), l = a.objectStore(Bt).get(this.modelPath);
          l.onsuccess = () => {
            if (l.result == null)
              return i.close(), s(new Error(`Cannot find model with path '${this.modelPath}' in IndexedDB.`));
            r(l.result.modelArtifacts);
          }, l.onerror = (u) => (i.close(), s(l.error)), a.oncomplete = () => i.close();
        } else {
          t.weightData = Yt.join(t.weightData);
          const a = Br(t), c = i.transaction(It, "readwrite");
          let l = c.objectStore(It), u;
          try {
            u = l.put({ modelPath: this.modelPath, modelArtifactsInfo: a });
          } catch (h) {
            return s(h);
          }
          let d;
          u.onsuccess = () => {
            d = i.transaction(Bt, "readwrite");
            const h = d.objectStore(Bt);
            let f;
            try {
              f = h.put({
                modelPath: this.modelPath,
                modelArtifacts: t,
                modelArtifactsInfo: a
              });
            } catch (m) {
              return s(m);
            }
            f.onsuccess = () => r({ modelArtifactsInfo: a }), f.onerror = (m) => {
              l = c.objectStore(It);
              const C = l.delete(this.modelPath);
              C.onsuccess = () => (i.close(), s(f.error)), C.onerror = (w) => (i.close(), s(f.error));
            };
          }, u.onerror = (h) => (i.close(), s(u.error)), c.oncomplete = () => {
            d == null ? i.close() : d.oncomplete = () => i.close();
          };
        }
      }, o.onerror = (i) => s(o.error);
    });
  }
}
Wt.URL_SCHEME = "indexeddb://";
const ya = (n) => E().getBool("IS_BROWSER") && !Array.isArray(n) && n.startsWith(Wt.URL_SCHEME) ? Tf(n.slice(Wt.URL_SCHEME.length)) : null;
fe.registerSaveRouter(ya);
fe.registerLoadRouter(ya);
function Tf(n) {
  return new Wt(n);
}
function Nf(n) {
  return n.startsWith(Wt.URL_SCHEME) ? n.slice(Wt.URL_SCHEME.length) : n;
}
class kf {
  constructor() {
    this.indexedDB = ba();
  }
  async listModels() {
    return new Promise((e, t) => {
      const r = this.indexedDB.open(ws, Cs);
      r.onupgradeneeded = () => bs(r), r.onsuccess = () => {
        const s = r.result, o = s.transaction(It, "readonly"), a = o.objectStore(It).getAll();
        a.onsuccess = () => {
          const c = {};
          for (const l of a.result)
            c[l.modelPath] = l.modelArtifactsInfo;
          e(c);
        }, a.onerror = (c) => (s.close(), t(a.error)), o.oncomplete = () => s.close();
      }, r.onerror = (s) => t(r.error);
    });
  }
  async removeModel(e) {
    return e = Nf(e), new Promise((t, r) => {
      const s = this.indexedDB.open(ws, Cs);
      s.onupgradeneeded = () => bs(s), s.onsuccess = () => {
        const o = s.result, i = o.transaction(It, "readwrite"), a = i.objectStore(It), c = a.get(e);
        let l;
        c.onsuccess = () => {
          if (c.result == null)
            return o.close(), r(new Error(`Cannot find model with path '${e}' in IndexedDB.`));
          {
            const u = a.delete(e), d = () => {
              l = o.transaction(Bt, "readwrite");
              const f = l.objectStore(Bt).delete(e);
              f.onsuccess = () => t(c.result.modelArtifactsInfo), f.onerror = (m) => r(c.error);
            };
            u.onsuccess = d, u.onerror = (h) => (d(), o.close(), r(c.error));
          }
        }, c.onerror = (u) => (o.close(), r(c.error)), i.oncomplete = () => {
          l == null ? o.close() : l.oncomplete = () => o.close();
        };
      }, s.onerror = (o) => r(s.error);
    });
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ft = "/", ln = "tensorflowjs_models", $a = "info", Af = "model_topology", Ff = "weight_specs", Df = "weight_data", Of = "model_metadata";
function va(n) {
  return {
    info: [ln, n, $a].join(ft),
    topology: [ln, n, Af].join(ft),
    weightSpecs: [ln, n, Ff].join(ft),
    weightData: [ln, n, Df].join(ft),
    modelMetadata: [ln, n, Of].join(ft)
  };
}
function Ia(n) {
  for (const e of Object.values(n))
    window.localStorage.removeItem(e);
}
function Pf(n) {
  const e = n.split(ft);
  if (e.length < 3)
    throw new Error(`Invalid key format: ${n}`);
  return e.slice(1, e.length - 1).join(ft);
}
function _f(n) {
  return n.startsWith(Gt.URL_SCHEME) ? n.slice(Gt.URL_SCHEME.length) : n;
}
class Gt {
  constructor(e) {
    if (!E().getBool("IS_BROWSER") || typeof window > "u" || typeof window.localStorage > "u")
      throw new Error("The current environment does not support local storage.");
    if (this.LS = window.localStorage, e == null || !e)
      throw new Error("For local storage, modelPath must not be null, undefined or empty.");
    this.modelPath = e, this.keys = va(this.modelPath);
  }
  /**
   * Save model artifacts to browser local storage.
   *
   * See the documentation to `browserLocalStorage` for details on the saved
   * artifacts.
   *
   * @param modelArtifacts The model artifacts to be stored.
   * @returns An instance of SaveResult.
   */
  async save(e) {
    if (e.modelTopology instanceof ArrayBuffer)
      throw new Error("BrowserLocalStorage.save() does not support saving model topology in binary formats yet.");
    {
      const t = JSON.stringify(e.modelTopology), r = JSON.stringify(e.weightSpecs), s = Br(e), o = Yt.join(e.weightData);
      try {
        this.LS.setItem(this.keys.info, JSON.stringify(s)), this.LS.setItem(this.keys.topology, t), this.LS.setItem(this.keys.weightSpecs, r), this.LS.setItem(this.keys.weightData, vf(o));
        const i = {
          format: e.format,
          generatedBy: e.generatedBy,
          convertedBy: e.convertedBy,
          signature: e.signature != null ? e.signature : void 0,
          userDefinedMetadata: e.userDefinedMetadata != null ? e.userDefinedMetadata : void 0,
          modelInitializer: e.modelInitializer != null ? e.modelInitializer : void 0,
          initializerSignature: e.initializerSignature != null ? e.initializerSignature : void 0,
          trainingConfig: e.trainingConfig != null ? e.trainingConfig : void 0
        };
        return this.LS.setItem(this.keys.modelMetadata, JSON.stringify(i)), { modelArtifactsInfo: s };
      } catch {
        throw Ia(this.keys), new Error(`Failed to save model '${this.modelPath}' to local storage: size quota being exceeded is a possible cause of this failure: modelTopologyBytes=${s.modelTopologyBytes}, weightSpecsBytes=${s.weightSpecsBytes}, weightDataBytes=${s.weightDataBytes}.`);
      }
    }
  }
  /**
   * Load a model from local storage.
   *
   * See the documentation to `browserLocalStorage` for details on the saved
   * artifacts.
   *
   * @returns The loaded model (if loading succeeds).
   */
  async load() {
    const e = JSON.parse(this.LS.getItem(this.keys.info));
    if (e == null)
      throw new Error(`In local storage, there is no model with name '${this.modelPath}'`);
    if (e.modelTopologyType !== "JSON")
      throw new Error("BrowserLocalStorage does not support loading non-JSON model topology yet.");
    const t = {}, r = JSON.parse(this.LS.getItem(this.keys.topology));
    if (r == null)
      throw new Error(`In local storage, the topology of model '${this.modelPath}' is missing.`);
    t.modelTopology = r;
    const s = JSON.parse(this.LS.getItem(this.keys.weightSpecs));
    if (s == null)
      throw new Error(`In local storage, the weight specs of model '${this.modelPath}' are missing.`);
    t.weightSpecs = s;
    const o = this.LS.getItem(this.keys.modelMetadata);
    if (o != null) {
      const a = JSON.parse(o);
      t.format = a.format, t.generatedBy = a.generatedBy, t.convertedBy = a.convertedBy, a.signature != null && (t.signature = a.signature), a.userDefinedMetadata != null && (t.userDefinedMetadata = a.userDefinedMetadata), a.modelInitializer != null && (t.modelInitializer = a.modelInitializer), a.initializerSignature != null && (t.initializerSignature = a.initializerSignature), a.trainingConfig != null && (t.trainingConfig = a.trainingConfig);
    }
    const i = this.LS.getItem(this.keys.weightData);
    if (i == null)
      throw new Error(`In local storage, the binary weight values of model '${this.modelPath}' are missing.`);
    return t.weightData = If(i), t;
  }
}
Gt.URL_SCHEME = "localstorage://";
const Sa = (n) => E().getBool("IS_BROWSER") && !Array.isArray(n) && n.startsWith(Gt.URL_SCHEME) ? Bf(n.slice(Gt.URL_SCHEME.length)) : null;
fe.registerSaveRouter(Sa);
fe.registerLoadRouter(Sa);
function Bf(n) {
  return new Gt(n);
}
class Lf {
  constructor() {
    O(E().getBool("IS_BROWSER"), () => "Current environment is not a web browser"), O(typeof window > "u" || typeof window.localStorage < "u", () => "Current browser does not appear to support localStorage"), this.LS = window.localStorage;
  }
  async listModels() {
    const e = {}, t = ln + ft, r = ft + $a;
    for (let s = 0; s < this.LS.length; ++s) {
      const o = this.LS.key(s);
      if (o.startsWith(t) && o.endsWith(r)) {
        const i = Pf(o);
        e[i] = JSON.parse(this.LS.getItem(o));
      }
    }
    return e;
  }
  async removeModel(e) {
    e = _f(e);
    const t = va(e);
    if (this.LS.getItem(t.info) == null)
      throw new Error(`Cannot find model at path '${e}'`);
    const r = JSON.parse(this.LS.getItem(t.info));
    return Ia(t), r;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const _o = "://";
class it {
  constructor() {
    this.managers = {};
  }
  static getInstance() {
    return it.instance == null && (it.instance = new it()), it.instance;
  }
  /**
   * Register a save-handler router.
   *
   * @param saveRouter A function that maps a URL-like string onto an instance
   * of `IOHandler` with the `save` method defined or `null`.
   */
  static registerManager(e, t) {
    O(e != null, () => "scheme must not be undefined or null."), e.endsWith(_o) && (e = e.slice(0, e.indexOf(_o))), O(e.length > 0, () => "scheme must not be an empty string.");
    const r = it.getInstance();
    O(r.managers[e] == null, () => `A model store manager is already registered for scheme '${e}'.`), r.managers[e] = t;
  }
  static getManager(e) {
    const t = it.getInstance().managers[e];
    if (t == null)
      throw new Error(`Cannot find model manager for scheme '${e}'`);
    return t;
  }
  static getSchemes() {
    return Object.keys(it.getInstance().managers);
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Mf {
  constructor() {
    this.messageName = "setTimeoutCustom", this.functionRefs = [], this.handledMessageCount = 0, this.hasEventListener = !1;
  }
  fetch(e, t) {
    return fetch(e, t);
  }
  now() {
    return performance.now();
  }
  encode(e, t) {
    if (t !== "utf-8" && t !== "utf8")
      throw new Error(`Browser's encoder only supports utf-8, but got ${t}`);
    return this.textEncoder == null && (this.textEncoder = new TextEncoder()), this.textEncoder.encode(e);
  }
  decode(e, t) {
    return new TextDecoder(t).decode(e);
  }
  // If the setTimeout nesting level is greater than 5 and timeout is less
  // than 4ms, timeout will be clamped to 4ms, which hurts the perf.
  // Interleaving window.postMessage and setTimeout will trick the browser and
  // avoid the clamp.
  setTimeoutCustom(e, t) {
    if (typeof window > "u" || !E().getBool("USE_SETTIMEOUTCUSTOM")) {
      setTimeout(e, t);
      return;
    }
    this.functionRefs.push(e), setTimeout(() => {
      window.postMessage({ name: this.messageName, index: this.functionRefs.length - 1 }, "*");
    }, t), this.hasEventListener || (this.hasEventListener = !0, window.addEventListener("message", (r) => {
      if (r.source === window && r.data.name === this.messageName) {
        r.stopPropagation();
        const s = this.functionRefs[r.data.index];
        s(), this.handledMessageCount++, this.handledMessageCount === this.functionRefs.length && (this.functionRefs = [], this.handledMessageCount = 0);
      }
    }, !0));
  }
  isTypedArray(e) {
    return ea(e);
  }
}
if (E().get("IS_BROWSER")) {
  E().setPlatform("browser", new Mf());
  try {
    it.registerManager(Gt.URL_SCHEME, new Lf());
  } catch {
  }
  try {
    it.registerManager(Wt.URL_SCHEME, new kf());
  } catch {
  }
}
const Uf = {
  // tslint:disable-next-line:no-require-imports
  importFetch: () => require("node-fetch")
};
let Zr;
class Vf {
  constructor() {
    this.util = require("util"), this.textEncoder = new this.util.TextEncoder();
  }
  fetch(e, t) {
    return E().global.fetch != null ? E().global.fetch(e, t) : (Zr == null && (Zr = Uf.importFetch()), Zr(e, t));
  }
  now() {
    const e = fn.hrtime();
    return e[0] * 1e3 + e[1] / 1e6;
  }
  encode(e, t) {
    if (t !== "utf-8" && t !== "utf8")
      throw new Error(`Node built-in encoder only supports utf-8, but got ${t}`);
    return this.textEncoder.encode(e);
  }
  decode(e, t) {
    return e.length === 0 ? "" : new this.util.TextDecoder(t).decode(e);
  }
  isTypedArray(e) {
    return this.util.types.isFloat32Array(e) || this.util.types.isInt32Array(e) || this.util.types.isUint8Array(e) || this.util.types.isUint8ClampedArray(e);
  }
}
E().get("IS_NODE") && !E().get("IS_BROWSER") && E().setPlatform("node", new Vf());
/**
 * @license
 * Copyright 2020 Google Inc. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function xe(n, e = "float32", t) {
  return e = e || "float32", Qn(n), new vr(n, e, t);
}
/**
 * @license
 * Copyright 2020 Google Inc. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Wf(n, e) {
  const t = X(n, "x", "cast");
  if (!_l(e))
    throw new Error(`Failed to cast to unknown dtype ${e}`);
  if (e === "string" && t.dtype !== "string" || e !== "string" && t.dtype === "string")
    throw new Error("Only strings can be casted to strings");
  const r = { x: t }, s = { dtype: e };
  return M.runKernel(_s, r, s);
}
const Sr = /* @__PURE__ */ te({ cast_: Wf });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Gf(n) {
  const t = { x: X(n, "x", "clone", "string_or_numeric") };
  return M.runKernel(Bs, t);
}
const Ea = /* @__PURE__ */ te({ clone_: Gf });
/**
 * @license
 * Copyright 2020 Google Inc. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function zf(n, e = !1) {
  console.log(n.toString(e));
}
/**
 * @license
 * Copyright 2020 Google Inc. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
pa();
const Hf = {
  buffer: xe,
  cast: Sr,
  clone: Ea,
  print: zf
};
tf(Hf);
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function FE() {
  M.disposeVariables();
}
function $t() {
  return M;
}
function DE() {
  return M.memory();
}
function se(n, e) {
  return M.tidy(n, e);
}
function _e(n) {
  ha(n).forEach((t) => t.dispose());
}
function Xf(n) {
  return M.keep(n);
}
function OE(n) {
  return M.setBackend(n);
}
function PE() {
  return M.ready();
}
function jf(n, e, t = 1) {
  return M.registerBackend(n, e, t);
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function qf(n, e) {
  let t = X(n, "a", "add"), r = X(e, "b", "add");
  [t, r] = Kt(t, r);
  const s = { a: t, b: r };
  return M.runKernel(Ps, s);
}
const q = /* @__PURE__ */ te({ add_: qf });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Kf(n, e) {
  let t = X(n, "a", "floorDiv"), r = X(e, "b", "floorDiv");
  [t, r] = Kt(t, r);
  const s = { a: t, b: r };
  return M.runKernel(Bi, s);
}
const Yf = /* @__PURE__ */ te({ floorDiv_: Kf });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Qf(n, e) {
  let t = X(n, "a", "div"), r = X(e, "b", "div");
  if ([t, r] = Kt(t, r), t.dtype === "int32" && r.dtype === "int32")
    return Yf(t, r);
  const s = { a: t, b: r }, o = {};
  return M.runKernel(Oi, s, o);
}
const lt = /* @__PURE__ */ te({ div_: Qf });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Zf(n, e) {
  let t = X(n, "a", "mul"), r = X(e, "b", "mul");
  [t, r] = Kt(t, r);
  const s = { a: t, b: r };
  return M.runKernel(Ui, s);
}
const z = /* @__PURE__ */ te({ mul_: Zf });
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Jf(n) {
  const e = X(n, "x", "abs");
  if (e.dtype === "complex64") {
    const t = { x: e };
    return M.runKernel(Di, t);
  } else {
    const t = { x: e };
    return M.runKernel(Ai, t);
  }
}
const ep = /* @__PURE__ */ te({ abs_: Jf });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ra(n, e, t, r, s = "NHWC", o) {
  const i = n[3], a = [...e, i], c = En(s);
  return et(n, a, t, o, r, null, null, c);
}
function In(n, e, t, r, s, o, i = "channelsLast") {
  const [a, c] = zn(e);
  let l;
  if (i === "channelsLast")
    l = [a, c, n[3], n[3]];
  else if (i === "channelsFirst")
    l = [a, c, n[1], n[1]];
  else
    throw new Error(`Unknown dataFormat ${i}`);
  return et(n, l, t, r, s, o, !1, i);
}
function Zn(n, e, t, r, s, o, i = "NDHWC") {
  const [a, c, l] = ys(e);
  let u, d;
  if (i === "NDHWC")
    d = "channelsLast", u = [a, c, l, n[4], n[4]];
  else if (i === "NCDHW")
    d = "channelsFirst", u = [a, c, l, n[1], n[1]];
  else
    throw new Error(`Unknown dataFormat ${i}`);
  return Jn(n, u, t, r, s, !1, d, o);
}
function et(n, e, t, r, s, o, i = !1, a = "channelsLast") {
  let [c, l, u, d] = [-1, -1, -1, -1];
  if (a === "channelsLast")
    [c, l, u, d] = n;
  else if (a === "channelsFirst")
    [c, d, l, u] = n;
  else
    throw new Error(`Unknown dataFormat ${a}`);
  const [h, f, , m] = e, [C, w] = zn(t), [x, y] = zn(r), v = pn(h, x), I = pn(f, y), { padInfo: T, outHeight: A, outWidth: F } = rp(s, l, u, C, w, v, I, o, a), k = i ? m * d : m;
  let U;
  return a === "channelsFirst" ? U = [c, k, A, F] : a === "channelsLast" && (U = [c, A, F, k]), {
    batchSize: c,
    dataFormat: a,
    inHeight: l,
    inWidth: u,
    inChannels: d,
    outHeight: A,
    outWidth: F,
    outChannels: k,
    padInfo: T,
    strideHeight: C,
    strideWidth: w,
    filterHeight: h,
    filterWidth: f,
    effectiveFilterHeight: v,
    effectiveFilterWidth: I,
    dilationHeight: x,
    dilationWidth: y,
    inShape: n,
    outShape: U,
    filterShape: e
  };
}
function Jn(n, e, t, r, s, o = !1, i = "channelsLast", a) {
  let [c, l, u, d, h] = [-1, -1, -1, -1, -1];
  if (i === "channelsLast")
    [c, l, u, d, h] = n;
  else if (i === "channelsFirst")
    [c, h, l, u, d] = n;
  else
    throw new Error(`Unknown dataFormat ${i}`);
  const [f, m, C, , w] = e, [x, y, v] = ys(t), [I, T, A] = ys(r), F = pn(f, I), k = pn(m, T), U = pn(C, A), { padInfo: V, outDepth: G, outHeight: j, outWidth: be } = sp(s, l, u, d, x, y, v, F, k, U, a), ie = o ? w * h : w;
  let ce;
  return i === "channelsFirst" ? ce = [c, ie, G, j, be] : i === "channelsLast" && (ce = [c, G, j, be, ie]), {
    batchSize: c,
    dataFormat: i,
    inDepth: l,
    inHeight: u,
    inWidth: d,
    inChannels: h,
    outDepth: G,
    outHeight: j,
    outWidth: be,
    outChannels: ie,
    padInfo: V,
    strideDepth: x,
    strideHeight: y,
    strideWidth: v,
    filterDepth: f,
    filterHeight: m,
    filterWidth: C,
    effectiveFilterDepth: F,
    effectiveFilterHeight: k,
    effectiveFilterWidth: U,
    dilationDepth: I,
    dilationHeight: T,
    dilationWidth: A,
    inShape: n,
    outShape: ce,
    filterShape: e
  };
}
function tp(n, e, t, r, s) {
  r == null && (r = Gs(n, e, t));
  const o = n[0], i = n[1], a = Hn((o - e + 2 * r) / t + 1, s), c = Hn((i - e + 2 * r) / t + 1, s);
  return [a, c];
}
function np(n, e, t, r, s, o) {
  s == null && (s = Gs(n, e[0], r[0]));
  const i = [0, 0, 0, t];
  for (let a = 0; a < 3; a++)
    n[a] + 2 * s >= e[a] && (i[a] = Hn((n[a] - e[a] + 2 * s) / r[a] + 1, o));
  return i;
}
function Gs(n, e, t, r = 1) {
  const s = pn(e, r);
  return Math.floor((n[0] * (t - 1) - t + s) / 2);
}
function zn(n) {
  return typeof n == "number" ? [n, n, n] : n.length === 2 ? [n[0], n[1], 1] : n;
}
function ys(n) {
  return typeof n == "number" ? [n, n, n] : n;
}
function pn(n, e) {
  return e <= 1 ? n : n + (n - 1) * (e - 1);
}
function rp(n, e, t, r, s, o, i, a, c) {
  let l, u, d;
  if (typeof n == "number") {
    l = { top: n, bottom: n, left: n, right: n, type: n === 0 ? "VALID" : "NUMBER" };
    const f = tp([e, t], o, r, n, a);
    u = f[0], d = f[1];
  } else if (n === "same") {
    u = Math.ceil(e / r), d = Math.ceil(t / s);
    const h = Math.max(0, (u - 1) * r + o - e), f = Math.max(0, (d - 1) * s + i - t), m = Math.floor(h / 2), C = h - m, w = Math.floor(f / 2), x = f - w;
    l = { top: m, bottom: C, left: w, right: x, type: "SAME" };
  } else if (n === "valid")
    l = { top: 0, bottom: 0, left: 0, right: 0, type: "VALID" }, u = Math.ceil((e - o + 1) / r), d = Math.ceil((t - i + 1) / s);
  else if (typeof n == "object") {
    const h = c === "channelsLast" ? n[1][0] : n[2][0], f = c === "channelsLast" ? n[1][1] : n[2][1], m = c === "channelsLast" ? n[2][0] : n[3][0], C = c === "channelsLast" ? n[2][1] : n[3][1];
    l = { top: h, bottom: f, left: m, right: C, type: h === 0 && f === 0 && m === 0 && C === 0 ? "VALID" : "EXPLICIT" }, u = Hn((e - o + h + f) / r + 1, a), d = Hn((t - i + m + C) / s + 1, a);
  } else
    throw Error(`Unknown padding parameter: ${n}`);
  return { padInfo: l, outHeight: u, outWidth: d };
}
function sp(n, e, t, r, s, o, i, a, c, l, u) {
  let d, h, f, m;
  if (n === "valid" && (n = 0), typeof n == "number") {
    d = {
      top: n,
      bottom: n,
      left: n,
      right: n,
      front: n,
      back: n,
      type: n === 0 ? "VALID" : "NUMBER"
    };
    const w = np([e, t, r, 1], [a, c, l], 1, [s, o, i], n, u);
    h = w[0], f = w[1], m = w[2];
  } else if (n === "same") {
    h = Math.ceil(e / s), f = Math.ceil(t / o), m = Math.ceil(r / i);
    const C = (h - 1) * s + a - e, w = (f - 1) * o + c - t, x = (m - 1) * i + l - r, y = Math.floor(C / 2), v = C - y, I = Math.floor(w / 2), T = w - I, A = Math.floor(x / 2), F = x - A;
    d = { top: I, bottom: T, left: A, right: F, front: y, back: v, type: "SAME" };
  } else
    throw Error(`Unknown padding parameter: ${n}`);
  return { padInfo: d, outDepth: h, outHeight: f, outWidth: m };
}
function Hn(n, e) {
  if (!e)
    return Math.trunc(n);
  switch (e) {
    case "round":
      return Math.round(n);
    case "ceil":
      return Math.ceil(n);
    case "floor":
      return Math.floor(n);
    default:
      throw new Error(`Unknown roundingMode ${e}`);
  }
}
function $s(n) {
  const [e, t, r] = zn(n);
  return e === 1 && t === 1 && r === 1;
}
function Sn(n, e) {
  return $s(n) || $s(e);
}
function op(n) {
  return zn(n).every((e) => e > 0);
}
function En(n) {
  if (n === "NHWC")
    return "channelsLast";
  if (n === "NCHW")
    return "channelsFirst";
  throw new Error(`Unknown dataFormat ${n}`);
}
function ip(n, e, t) {
  if (t != null) {
    if (typeof e == "string")
      throw Error(`Error in ${n}: pad must be an integer when using dimRoundingMode ${t} but got pad ${e}.`);
    if (typeof e == "number")
      O(Cr(e), () => `Error in ${n}: pad must be an integer when using dimRoundingMode ${t} but got pad ${e}.`);
    else if (typeof e == "object")
      e.forEach((r) => {
        r.forEach((s) => {
          O(Cr(s), () => `Error in ${n}: pad must be an integer when using dimRoundingMode ${t} but got pad ${s}.`);
        });
      });
    else
      throw Error(`Error in ${n}: Unknown padding parameter: ${e}`);
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function ap(n, e) {
  const r = { x: X(n, "x", "reshape", "string_or_numeric") }, s = { shape: e };
  return M.runKernel(zi, r, s);
}
const zs = /* @__PURE__ */ te({ reshape_: ap });
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function cp(n) {
  const t = { x: X(n, "x", "sigmoid", "float32") };
  return M.runKernel(Xi, t);
}
const lp = /* @__PURE__ */ te({ sigmoid_: cp });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function up(n, e) {
  let t = X(n, "broadcastTo", "x");
  const r = t.shape;
  if (Qn(e), e.length < t.rank)
    throw new Error(`broadcastTo(): shape.length=${e.length} < input.rank=${t.rank}.`);
  if (e.length > t.rank) {
    const l = t.shape.slice();
    for (; l.length < e.length; )
      l.unshift(1);
    t = zs(t, l);
  }
  const s = t.shape, o = Array.from(e);
  for (let l = e.length - 1; l >= 0; l--)
    if (s[l] === e[l])
      o[l] = 1;
    else if (t.shape[l] !== 1)
      throw new Error(`broadcastTo(): [${r}] cannot be broadcast to [${e}].`);
  if (o.map((l, u) => l > 1 ? u : -1).filter((l) => l >= 0).length === 0)
    return Ea(t);
  const a = { x: t }, c = { reps: o };
  return M.runKernel(Yi, a, c);
}
const dp = /* @__PURE__ */ te({ broadcastTo_: up });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function hp(n, e, t) {
  Qn(n), t = t || Yn(e);
  const r = { shape: n, value: e, dtype: t };
  return M.runKernel(_i, {}, r);
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Er(n, e) {
  const t = n.length, r = [];
  for (let s = 0; s < t; s++) {
    const o = t - 1 - s, i = n[o] || 1;
    (e[e.length - 1 - s] || 1) > 1 && i === 1 && r.unshift(o);
  }
  return r;
}
function Ta(n, e) {
  const t = [];
  for (let r = 0; r < e.length; r++) {
    const s = n[n.length - r - 1], o = e.length - r - 1, i = e[o];
    (s == null || s === 1 && i > 1) && t.unshift(o);
  }
  return t;
}
function ve(n, e) {
  const t = Math.max(n.length, e.length), r = new Array(t);
  for (let s = 0; s < t; s++) {
    let o = n[n.length - s - 1];
    o == null && (o = 1);
    let i = e[e.length - s - 1];
    if (i == null && (i = 1), o === 1)
      r[t - s - 1] = i;
    else if (i === 1)
      r[t - s - 1] = o;
    else if (o !== i) {
      const a = `Operands could not be broadcast together with shapes ${n} and ${e}.`;
      throw Error(a);
    } else
      r[t - s - 1] = o;
  }
  return r;
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function fp(n) {
  const t = { x: X(n, "x", "zerosLike") };
  return M.runKernel(Qi, t);
}
const ut = /* @__PURE__ */ te({ zerosLike_: fp });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function pp(n) {
  const t = { x: X(n, "x", "elu", "float32") };
  return M.runKernel(Pi, t);
}
const mp = /* @__PURE__ */ te({ elu_: pp });
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Hs(n, e) {
  for (let t = 0; t < n.length; ++t)
    if (n[n.length - t - 1] !== e - 1 - t)
      return !1;
  return !0;
}
function Na(n, e, t) {
  const r = n.length + e.length, s = [];
  let o = 0, i = 0;
  for (let a = 0; a < r; a++)
    t.indexOf(a) === -1 ? s.push(n[o++]) : s.push(e[i++]);
  return s;
}
function ht(n, e) {
  const t = [], r = n.length;
  for (let o = 0; o < r; o++)
    e.indexOf(o) === -1 && t.push(n[o]);
  const s = e.map((o) => n[o]);
  return [t, s];
}
function gt(n, e) {
  const t = e.map((r) => 1);
  return Na(n, t, e);
}
function tt(n, e, t) {
  O(Hs(e, t), () => `${n} supports only inner-most axes for now. Got axes ${e} and rank-${t} input.`);
}
function He(n, e) {
  if (Hs(n, e))
    return null;
  const t = [];
  for (let r = 0; r < e; ++r)
    n.indexOf(r) === -1 && t.push(r);
  return n.forEach((r) => t.push(r)), t;
}
function Xs(n) {
  return n.map((e, t) => [t, e]).sort((e, t) => e[1] - t[1]).map((e) => e[0]);
}
function Xe(n, e) {
  const t = [];
  for (let r = e - n; r < e; ++r)
    t.push(r);
  return t;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function gp(n, e) {
  let t = X(n, "base", "pow"), r = X(e, "exp", "pow");
  [t, r] = Kt(t, r);
  const s = { a: t, b: r };
  return M.runKernel(Vi, s);
}
const Bo = /* @__PURE__ */ te({ pow_: gp });
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Tt(n, e) {
  if ((ze(n) && e !== "string" || Array.isArray(n)) && e !== "complex64")
    throw new Error("Error creating a new Scalar: value must be a primitive (number|boolean|string)");
  if (e === "string" && ze(n) && !(n instanceof Uint8Array))
    throw new Error("When making a scalar from encoded string, the value must be `Uint8Array`.");
  return yf(n, [], [], e);
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function xp(n) {
  const t = { x: X(n, "x", "sqrt", "float32") };
  return M.runKernel(ji, t);
}
const Cn = /* @__PURE__ */ te({ sqrt_: xp });
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function wp(n) {
  const e = X(n, "x", "square"), t = {};
  return M.runKernel("Square", { x: e }, t);
}
const Mt = /* @__PURE__ */ te({ square_: wp });
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Cp(n, e = null, t = !1) {
  let r = X(n, "x", "sum");
  r.dtype === "bool" && (r = Sr(r, "int32"));
  const s = { x: r }, o = { axis: e, keepDims: t };
  return M.runKernel(qi, s, o);
}
const bp = /* @__PURE__ */ te({ sum_: Cp });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function yp(n, e = 0.2) {
  const r = { x: X(n, "x", "leakyRelu") }, s = { alpha: e };
  return M.runKernel(Li, r, s);
}
const $p = /* @__PURE__ */ te({ leakyRelu_: yp });
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function vp(n, e) {
  O(as(n), () => "The f passed in variableGrads(f) must be a function"), O(e == null || Array.isArray(e) && e.every((l) => l instanceof Ir), () => "The varList passed in variableGrads(f, varList) must be an array of variables");
  const t = e != null;
  if (!t) {
    e = [];
    for (const l in M.registeredVariables)
      e.push(M.registeredVariables[l]);
  }
  const r = t ? e.filter((l) => !l.trainable) : null, s = e.length;
  e = e.filter((l) => l.trainable), O(e.length > 0, () => `variableGrads() expects at least one of the input variables to be trainable, but none of the ${s} variables is trainable.`);
  const o = !0, { value: i, grads: a } = M.gradients(n, e, null, o);
  O(a.some((l) => l != null), () => "Cannot find a connection between any variable and the result of the loss function y=f(x). Please make sure the operations that use variables are inside the function f passed to minimize()."), O(i.rank === 0, () => `The f passed in variableGrads(f) must return a scalar, but it returned a rank-${i.rank} tensor`);
  const c = {};
  return e.forEach((l, u) => {
    a[u] != null && (c[l.name] = a[u]);
  }), r?.forEach((l) => c[l.name] = null), { value: i, grads: c };
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ip(n, e) {
  let t = X(n, "a", "sub"), r = X(e, "b", "sub");
  [t, r] = Kt(t, r);
  const s = { a: t, b: r };
  return M.runKernel(Ki, s);
}
const mn = /* @__PURE__ */ te({ sub_: Ip });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Sp(n, e) {
  let t = X(n, "a", "maximum"), r = X(e, "b", "maximum");
  [t, r] = Kt(t, r), t.dtype === "bool" && (t = Sr(t, "int32"), r = Sr(r, "int32")), ve(t.shape, r.shape);
  const s = { a: t, b: r };
  return M.runKernel(Mi, s);
}
const Ep = /* @__PURE__ */ te({ maximum_: Sp });
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function vs(n, e = "float32") {
  if (Qn(n), e === "complex64") {
    const r = vs(n, "float32"), s = vs(n, "float32");
    return bf(r, s);
  }
  const t = Rt(_(n), e);
  return M.makeTensor(t, n, e);
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Rp(n, e) {
  const t = X(n, "x", "prelu"), r = X(e, "alpha", "prelu"), s = { x: t, alpha: r };
  return M.runKernel(Wi, s);
}
const Tp = /* @__PURE__ */ te({ prelu_: Rp });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Np(n) {
  const t = { x: X(n, "x", "relu") };
  return M.runKernel(Gi, t);
}
const kp = /* @__PURE__ */ te({ relu_: Np });
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ap(n) {
  const t = { x: X(n, "x", "relu6") };
  return M.runKernel(Hi, t);
}
const Fp = /* @__PURE__ */ te({ relu6_: Ap });
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Dp(n, e = 0) {
  const r = { x: X(n, "x", "step") }, s = { alpha: e };
  return M.runKernel(Zi, r, s);
}
const Op = /* @__PURE__ */ te({ step_: Dp });
function ka(n, e, t) {
  const r = e.rank > 1 ? e.shape[e.rank - 1] : 1, s = e.rank > 1 ? e.rank - 1 : 1, o = `Must have updates.shape = indices.shape[:batchDim] + shape[sliceDim:], got updates.shape: ${t.shape}, indices.shape: ${e.shape}, shape: ${n}, sliceDim: ${r}, and batchDim: ${s}.`;
  if (t.rank < s)
    throw new Error(o + ` update.rank < ${s}. `);
  if (n.length < r + (t.rank - s))
    throw new Error(o + ` Output shape length < ${r + (t.rank - s)}`);
  if (t.rank !== s + n.length - r)
    throw new Error(o + ` update.rank != ${s + n.length - r}`);
  for (let i = 0; i < s; ++i)
    if (t.shape[i] !== e.shape[i])
      throw new Error(o + ` updates.shape[${i}] (${t.shape[i]}) != indices.shape[${i}] (${e.shape[i]}).`);
  for (let i = 0; i < t.rank - s; ++i)
    if (t.shape[i + s] !== n[i + r])
      throw new Error(o + ` updates.shape[${i + s}] (${t.shape[i + s]}) != shape[${i + s}] (${n[i + s]})`);
}
function Pp(n, e, t) {
  if (e.rank < 1)
    throw new Error(`tf.scatterND() expects the indices to be rank 1 or higher, but the rank was ${e.rank}.`);
  if (n.rank < 1)
    throw new Error(`tf.scatterND() expects the updates to be rank 1 or higher, but the rank was ${n.rank}.`);
  if (e.dtype !== "int32")
    throw new Error(`The dtype of 'indices' should be int32, but got dtype: ${e.dtype}`);
  if (t.length < 1)
    throw new Error(`Output rank must be greater or equal to 1, but got shape: ${t}`);
  if (t.length === 0) {
    if (e.size === 0)
      throw new Error(`Indices specified for empty output. indices shape: ${e.shape}`);
    if (n.size === 0)
      throw new Error(`Updates specified for empty output. updates shape: ${n.shape}`);
  }
  ka(t, e, n);
}
function Lr(n, e, t) {
  const r = e.shape.length, s = r > 1 ? e.shape[r - 1] : 1, o = t.length;
  let i = 1;
  for (let d = s; d < o; ++d)
    i *= t[d];
  const a = s < 1 ? 1 : s, c = _(e.shape) / a, l = [...me(t.slice(0, s)), 1], u = _(t);
  return { sliceRank: s, numUpdates: c, sliceSize: i, strides: l, outputSize: u };
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function _p(n, e) {
  const t = [];
  for (let o = 0; o < e.length; o++)
    e[o] && t.push(o);
  const r = xe(n, "int32"), s = xe([t.length, n.length], "int32");
  for (let o = 0; o < t.length; o++) {
    const i = r.indexToLoc(t[o]), a = o * n.length;
    s.values.set(i, a);
  }
  return s.toTensor();
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Bp(n, e, t) {
  if (t == null || t === "linear")
    return n;
  if (t === "relu")
    return z(n, Op(e));
  throw new Error(`Cannot compute gradient for fused activation ${t}.`);
}
function Lp(n, e) {
  let t = e;
  const r = Ta(n.shape, e.shape);
  return r.length > 0 && (t = bp(t, r)), zs(t, n.shape);
}
function Mp(n, e, t, r) {
  if (e === "linear")
    return n;
  if (e === "relu")
    return kp(n);
  if (e === "elu")
    return mp(n);
  if (e === "relu6")
    return Fp(n);
  if (e === "prelu")
    return Tp(n, t);
  if (e === "leakyrelu")
    return $p(n, r);
  if (e === "sigmoid")
    return lp(n);
  throw new Error(`Unknown fused activation ${e}.`);
}
const Up = (n, e) => !(n > 0) || e === "linear";
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Vp(n, e, t) {
  const r = Wp(n, e, t), s = r < 0 ? -(r + 1) : r;
  n.splice(s, 0, e);
}
function Wp(n, e, t) {
  return zp(n, e, t || Gp);
}
function Gp(n, e) {
  return n > e ? 1 : n < e ? -1 : 0;
}
function zp(n, e, t) {
  let r = 0, s = n.length, o = 0, i = !1;
  for (; r < s; ) {
    o = r + (s - r >>> 1);
    const a = t(e, n[o]);
    a > 0 ? r = o + 1 : (s = o, i = !a);
  }
  return i ? r : -r - 1;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Hp(n, e, t, r, s) {
  return js(
    n,
    e,
    t,
    r,
    s,
    0
    /* softNmsSigma */
  );
}
function Xp(n, e, t, r, s, o) {
  return js(
    n,
    e,
    t,
    r,
    s,
    0,
    !1,
    o,
    !0
    /* returnValidOutputs */
  );
}
function jp(n, e, t, r, s, o) {
  return js(
    n,
    e,
    t,
    r,
    s,
    o,
    !0
    /* returnScoresTensor */
  );
}
function js(n, e, t, r, s, o, i = !1, a = !1, c = !1) {
  const l = [];
  for (let w = 0; w < e.length; w++)
    e[w] > s && l.push({ score: e[w], boxIndex: w, suppressBeginIndex: 0 });
  l.sort(Lo);
  const u = o > 0 ? -0.5 / o : 0, d = [], h = [];
  for (; d.length < t && l.length > 0; ) {
    const w = l.pop(), { score: x, boxIndex: y, suppressBeginIndex: v } = w;
    if (x < s)
      break;
    let I = !1;
    for (let T = d.length - 1; T >= v; --T) {
      const A = qp(n, y, d[T]);
      if (A >= r) {
        I = !0;
        break;
      }
      if (w.score = w.score * Kp(r, u, A), w.score <= s)
        break;
    }
    w.suppressBeginIndex = d.length, I || (w.score === x ? (d.push(y), h.push(w.score)) : w.score > s && Vp(l, w, Lo));
  }
  const f = d.length, m = t - f;
  a && m > 0 && (d.push(...new Array(m).fill(0)), h.push(...new Array(m).fill(0)));
  const C = { selectedIndices: d };
  return i && (C.selectedScores = h), c && (C.validOutputs = f), C;
}
function qp(n, e, t) {
  const r = n.subarray(e * 4, e * 4 + 4), s = n.subarray(t * 4, t * 4 + 4), o = Math.min(r[0], r[2]), i = Math.min(r[1], r[3]), a = Math.max(r[0], r[2]), c = Math.max(r[1], r[3]), l = Math.min(s[0], s[2]), u = Math.min(s[1], s[3]), d = Math.max(s[0], s[2]), h = Math.max(s[1], s[3]), f = (a - o) * (c - i), m = (d - l) * (h - u);
  if (f <= 0 || m <= 0)
    return 0;
  const C = Math.max(o, l), w = Math.max(i, u), x = Math.min(a, d), y = Math.min(c, h), v = Math.max(x - C, 0) * Math.max(y - w, 0);
  return v / (f + m - v);
}
function Kp(n, e, t) {
  const r = Math.exp(e * t * t);
  return t <= n ? r : 0;
}
function Lo(n, e) {
  return n.score - e.score || n.score === e.score && e.boxIndex - n.boxIndex;
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Yp = /* @__PURE__ */ new Map(), Qp = /* @__PURE__ */ new Map();
class Zp {
  /**
   * Return the class name for this class to use in serialization contexts.
   *
   * Generally speaking this will be the same thing that constructor.name
   * would have returned.  However, the class name needs to be robust
   * against minification for serialization/deserialization to work properly.
   *
   * There's also places such as initializers.VarianceScaling, where
   * implementation details between different languages led to different
   * class hierarchies and a non-leaf node is used for serialization purposes.
   */
  getClassName() {
    return this.constructor.className;
  }
  /**
   * Creates an instance of T from a ConfigDict.
   *
   * This works for most descendants of serializable.  A few need to
   * provide special handling.
   * @param cls A Constructor for the class to instantiate.
   * @param config The Configuration for the object.
   */
  /** @nocollapse */
  static fromConfig(e, t) {
    return new e(t);
  }
}
class Dt {
  constructor() {
    this.classNameMap = {};
  }
  /**
   * Returns the singleton instance of the map.
   */
  static getMap() {
    return Dt.instance == null && (Dt.instance = new Dt()), Dt.instance;
  }
  /**
   * Registers the class as serializable.
   */
  static register(e) {
    Dt.getMap().classNameMap[e.className] = [e, e.fromConfig];
  }
}
function Jp(n, e, t) {
  O(n.className != null, () => "Class being registered does not have the static className property defined."), O(typeof n.className == "string", () => "className is required to be a string, but got type " + typeof n.className), O(n.className.length > 0, () => "Class being registered has an empty-string as its className, which is disallowed."), typeof e > "u" && (e = "Custom"), typeof t > "u" && (t = n.className);
  const r = t, s = e + ">" + r;
  return Dt.register(n), Yp.set(s, n), Qp.set(n, s), n;
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Qt extends Zp {
  /**
   * Executes `f()` and minimizes the scalar output of `f()` by computing
   * gradients of y with respect to the list of trainable variables provided by
   * `varList`. If no list is provided, it defaults to all trainable variables.
   *
   * @param f The function to execute and whose output to minimize.
   * @param returnCost Whether to return the scalar cost value produced by
   * executing `f()`.
   * @param varList An optional list of variables to update. If specified, only
   * the trainable variables in varList will be updated by minimize. Defaults to
   * all trainable variables.
   *
   * @doc {heading: 'Training', subheading: 'Optimizers'}
   */
  minimize(e, t = !1, r) {
    const { value: s, grads: o } = this.computeGradients(e, r);
    if (r != null) {
      const i = r.map((a) => ({ name: a.name, tensor: o[a.name] }));
      this.applyGradients(i);
    } else
      this.applyGradients(o);
    return _e(o), t ? s : (s.dispose(), null);
  }
  /**
   * The number of iterations that this optimizer instance has been invoked for.
   */
  get iterations() {
    return this.iterations_ == null && (this.iterations_ = 0), this.iterations_;
  }
  incrementIterations() {
    this.iterations_ = this.iterations + 1;
  }
  /**
   * Executes f() and computes the gradient of the scalar output of f() with
   * respect to the list of trainable variables provided by `varList`. If no
   * list is provided, it defaults to all trainable variables.
   *
   * @param f The function to execute and whose output to use for computing
   * gradients with respect to variables.
   * @param varList An optional list of variables to compute gradients with
   * respect to. If specified, only the trainable variables in varList will have
   * gradients computed with respect to. Defaults to all trainable variables.
   *
   * @doc {heading: 'Training', subheading: 'Optimizers'}
   */
  computeGradients(e, t) {
    return vp(e, t);
  }
  /**
   * Dispose the variables (if any) owned by this optimizer instance.
   */
  dispose() {
    this.iterations_ != null && _e(this.iterations_);
  }
  async saveIterations() {
    return this.iterations_ == null && (this.iterations_ = 0), {
      name: "iter",
      // TODO(cais): Use 'int64' type when available.
      tensor: Tt(this.iterations_, "int32")
    };
  }
  async getWeights() {
    throw new Error("getWeights() is not implemented for this optimizer yet.");
  }
  async setWeights(e) {
    throw new Error(`setWeights() is not implemented for this optimizer class ${this.getClassName()}`);
  }
  /**
   * Extract the first element of the weight values and set it
   * as the iterations counter variable of this instance of optimizer.
   *
   * @param weightValues
   * @returns Weight values with the first element consumed and excluded.
   */
  async extractIterations(e) {
    return this.iterations_ = (await e[0].tensor.data())[0], e.slice(1);
  }
}
Object.defineProperty(Qt, Symbol.hasInstance, {
  value: (n) => n.minimize != null && n.computeGradients != null && n.applyGradients != null
});
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class em extends Qt {
  /** @nocollapse */
  static get className() {
    return "Adadelta";
  }
  constructor(e, t, r = null) {
    super(), this.learningRate = e, this.rho = t, this.epsilon = r, this.accumulatedGrads = [], this.accumulatedUpdates = [], r == null && (this.epsilon = M.backend.epsilon());
  }
  applyGradients(e) {
    (Array.isArray(e) ? e.map((r) => r.name) : Object.keys(e)).forEach((r, s) => {
      const o = M.registeredVariables[r], i = !1;
      this.accumulatedGrads[s] == null && (this.accumulatedGrads[s] = {
        originalName: `${r}/accum_grad`,
        variable: se(() => ut(o).variable(i))
      }), this.accumulatedUpdates[s] == null && (this.accumulatedUpdates[s] = {
        originalName: `${r}/accum_var`,
        variable: se(() => ut(o).variable(i))
      });
      const a = Array.isArray(e) ? e[s].tensor : e[r];
      if (a == null)
        return;
      const c = this.accumulatedGrads[s].variable, l = this.accumulatedUpdates[s].variable;
      se(() => {
        const u = q(z(c, this.rho), z(Mt(a), 1 - this.rho)), d = z(lt(Cn(q(l, this.epsilon)), Cn(q(c, this.epsilon))), a), h = q(z(l, this.rho), z(Mt(d), 1 - this.rho));
        c.assign(u), l.assign(h);
        const f = q(z(d, -this.learningRate), o);
        o.assign(f);
      });
    }), this.incrementIterations();
  }
  dispose() {
    this.accumulatedUpdates != null && (_e(this.accumulatedGrads.map((e) => e.variable)), _e(this.accumulatedUpdates.map((e) => e.variable)));
  }
  async getWeights() {
    const e = [...this.accumulatedGrads, ...this.accumulatedUpdates];
    return [await this.saveIterations()].concat(e.map((t) => ({ name: t.originalName, tensor: t.variable })));
  }
  async setWeights(e) {
    e = await this.extractIterations(e);
    const t = e.length / 2, r = !1;
    this.accumulatedGrads = e.slice(0, t).map((s) => ({
      originalName: s.name,
      variable: s.tensor.variable(r)
    })), this.accumulatedUpdates = e.slice(t, t * 2).map((s) => ({
      originalName: s.name,
      variable: s.tensor.variable(r)
    }));
  }
  getConfig() {
    return {
      learningRate: this.learningRate,
      rho: this.rho,
      epsilon: this.epsilon
    };
  }
  /** @nocollapse */
  static fromConfig(e, t) {
    return new e(t.learningRate, t.rho, t.epsilon);
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class tm extends Qt {
  /** @nocollapse */
  static get className() {
    return "Adagrad";
  }
  constructor(e, t = 0.1) {
    super(), this.learningRate = e, this.initialAccumulatorValue = t, this.accumulatedGrads = [];
  }
  applyGradients(e) {
    (Array.isArray(e) ? e.map((r) => r.name) : Object.keys(e)).forEach((r, s) => {
      const o = M.registeredVariables[r];
      this.accumulatedGrads[s] == null && (this.accumulatedGrads[s] = {
        originalName: `${r}/accumulator`,
        variable: se(() => hp(o.shape, this.initialAccumulatorValue).variable(!1))
      });
      const i = Array.isArray(e) ? e[s].tensor : e[r];
      if (i == null)
        return;
      const a = this.accumulatedGrads[s].variable;
      se(() => {
        const c = q(a, Mt(i));
        a.assign(c);
        const l = q(z(lt(i, Cn(q(c, M.backend.epsilon()))), -this.learningRate), o);
        o.assign(l);
      });
    }), this.incrementIterations();
  }
  dispose() {
    this.accumulatedGrads != null && _e(this.accumulatedGrads.map((e) => e.variable));
  }
  async getWeights() {
    return [await this.saveIterations()].concat(this.accumulatedGrads.map((e) => ({ name: e.originalName, tensor: e.variable })));
  }
  async setWeights(e) {
    e = await this.extractIterations(e);
    const t = !1;
    this.accumulatedGrads = e.map((r) => ({ originalName: r.name, variable: r.tensor.variable(t) }));
  }
  getConfig() {
    return {
      learningRate: this.learningRate,
      initialAccumulatorValue: this.initialAccumulatorValue
    };
  }
  /** @nocollapse */
  static fromConfig(e, t) {
    return new e(t.learningRate, t.initialAccumulatorValue);
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class nm extends Qt {
  /** @nocollapse */
  static get className() {
    return "Adam";
  }
  constructor(e, t, r, s = null) {
    super(), this.learningRate = e, this.beta1 = t, this.beta2 = r, this.epsilon = s, this.accumulatedFirstMoment = [], this.accumulatedSecondMoment = [], se(() => {
      this.accBeta1 = Tt(t).variable(), this.accBeta2 = Tt(r).variable();
    }), s == null && (this.epsilon = M.backend.epsilon());
  }
  applyGradients(e) {
    const t = Array.isArray(e) ? e.map((r) => r.name) : Object.keys(e);
    se(() => {
      const r = mn(1, this.accBeta1), s = mn(1, this.accBeta2);
      t.forEach((o, i) => {
        const a = M.registeredVariables[o], c = !1;
        this.accumulatedFirstMoment[i] == null && (this.accumulatedFirstMoment[i] = {
          originalName: `${o}/m`,
          variable: se(() => ut(a).variable(c))
        }), this.accumulatedSecondMoment[i] == null && (this.accumulatedSecondMoment[i] = {
          originalName: `${o}/v`,
          variable: se(() => ut(a).variable(c))
        });
        const l = Array.isArray(e) ? e[i].tensor : e[o];
        if (l == null)
          return;
        const u = this.accumulatedFirstMoment[i].variable, d = this.accumulatedSecondMoment[i].variable, h = q(z(u, this.beta1), z(l, 1 - this.beta1)), f = q(z(d, this.beta2), z(Mt(l), 1 - this.beta2)), m = lt(h, r), C = lt(f, s);
        u.assign(h), d.assign(f);
        const w = q(z(lt(m, q(Cn(C), this.epsilon)), -this.learningRate), a);
        a.assign(w);
      }), this.accBeta1.assign(z(this.accBeta1, this.beta1)), this.accBeta2.assign(z(this.accBeta2, this.beta2));
    }), this.incrementIterations();
  }
  dispose() {
    this.accBeta1.dispose(), this.accBeta2.dispose(), this.accumulatedFirstMoment != null && _e(this.accumulatedFirstMoment.map((e) => e.variable)), this.accumulatedSecondMoment != null && _e(this.accumulatedSecondMoment.map((e) => e.variable));
  }
  async getWeights() {
    const e = [...this.accumulatedFirstMoment, ...this.accumulatedSecondMoment];
    return [await this.saveIterations()].concat(e.map((t) => ({ name: t.originalName, tensor: t.variable })));
  }
  async setWeights(e) {
    e = await this.extractIterations(e), se(() => {
      this.accBeta1.assign(Bo(this.beta1, this.iterations_ + 1)), this.accBeta2.assign(Bo(this.beta2, this.iterations_ + 1));
    });
    const t = e.length / 2, r = !1;
    this.accumulatedFirstMoment = e.slice(0, t).map((s) => ({
      originalName: s.name,
      variable: s.tensor.variable(r)
    })), this.accumulatedSecondMoment = e.slice(t, t * 2).map((s) => ({
      originalName: s.name,
      variable: s.tensor.variable(r)
    }));
  }
  getConfig() {
    return {
      learningRate: this.learningRate,
      beta1: this.beta1,
      beta2: this.beta2,
      epsilon: this.epsilon
    };
  }
  /** @nocollapse */
  static fromConfig(e, t) {
    return new e(t.learningRate, t.beta1, t.beta2, t.epsilon);
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class rm extends Qt {
  /** @nocollapse */
  static get className() {
    return "Adamax";
  }
  constructor(e, t, r, s = null, o = 0) {
    super(), this.learningRate = e, this.beta1 = t, this.beta2 = r, this.epsilon = s, this.decay = o, this.accumulatedFirstMoment = [], this.accumulatedWeightedInfNorm = [], se(() => {
      this.iteration = Tt(0).variable(), this.accBeta1 = Tt(t).variable();
    }), s == null && (this.epsilon = M.backend.epsilon());
  }
  applyGradients(e) {
    const t = Array.isArray(e) ? e.map((r) => r.name) : Object.keys(e);
    se(() => {
      const r = mn(1, this.accBeta1), s = lt(-this.learningRate, q(z(this.iteration, this.decay), 1));
      t.forEach((o, i) => {
        const a = M.registeredVariables[o], c = !1;
        this.accumulatedFirstMoment[i] == null && (this.accumulatedFirstMoment[i] = {
          originalName: `${o}/m`,
          variable: ut(a).variable(c)
        }), this.accumulatedWeightedInfNorm[i] == null && (this.accumulatedWeightedInfNorm[i] = {
          originalName: `${o}/v`,
          variable: ut(a).variable(c)
        });
        const l = Array.isArray(e) ? e[i].tensor : e[o];
        if (l == null)
          return;
        const u = this.accumulatedFirstMoment[i].variable, d = this.accumulatedWeightedInfNorm[i].variable, h = q(z(u, this.beta1), z(l, 1 - this.beta1)), f = z(d, this.beta2), m = ep(l), C = Ep(f, m);
        u.assign(h), d.assign(C);
        const w = q(z(lt(s, r), lt(h, q(C, this.epsilon))), a);
        a.assign(w);
      }), this.iteration.assign(q(this.iteration, 1)), this.accBeta1.assign(z(this.accBeta1, this.beta1));
    }), this.incrementIterations();
  }
  dispose() {
    this.accBeta1.dispose(), this.iteration.dispose(), this.accumulatedFirstMoment != null && _e(this.accumulatedFirstMoment.map((e) => e.variable)), this.accumulatedWeightedInfNorm != null && _e(this.accumulatedWeightedInfNorm.map((e) => e.variable));
  }
  async getWeights() {
    throw new Error("getWeights() is not implemented for Adamax yet.");
  }
  async setWeights(e) {
    throw new Error("setWeights() is not implemented for Adamax yet.");
  }
  getConfig() {
    return {
      learningRate: this.learningRate,
      beta1: this.beta1,
      beta2: this.beta2,
      epsilon: this.epsilon,
      decay: this.decay
    };
  }
  /** @nocollapse */
  static fromConfig(e, t) {
    return new e(t.learningRate, t.beta1, t.beta2, t.epsilon, t.decay);
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Aa extends Qt {
  /** @nocollapse */
  static get className() {
    return "SGD";
  }
  constructor(e) {
    super(), this.learningRate = e, this.setLearningRate(e);
  }
  applyGradients(e) {
    (Array.isArray(e) ? e.map((r) => r.name) : Object.keys(e)).forEach((r, s) => {
      const o = Array.isArray(e) ? e[s].tensor : e[r];
      if (o == null)
        return;
      const i = M.registeredVariables[r];
      se(() => {
        const a = q(z(this.c, o), i);
        i.assign(a);
      });
    }), this.incrementIterations();
  }
  /**
   * Sets the learning rate of the optimizer.
   */
  setLearningRate(e) {
    this.learningRate = e, this.c != null && this.c.dispose(), this.c = Xf(Tt(-e));
  }
  dispose() {
    this.c.dispose();
  }
  async getWeights() {
    return [await this.saveIterations()];
  }
  async setWeights(e) {
    if (e = await this.extractIterations(e), e.length !== 0)
      throw new Error("SGD optimizer does not have settable weights.");
  }
  getConfig() {
    return { learningRate: this.learningRate };
  }
  /** @nocollapse */
  static fromConfig(e, t) {
    return new e(t.learningRate);
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class sm extends Aa {
  /** @nocollapse */
  // Name matters for Python compatibility.
  static get className() {
    return "Momentum";
  }
  constructor(e, t, r = !1) {
    super(e), this.learningRate = e, this.momentum = t, this.useNesterov = r, this.accumulations = [], this.m = Tt(this.momentum);
  }
  applyGradients(e) {
    (Array.isArray(e) ? e.map((r) => r.name) : Object.keys(e)).forEach((r, s) => {
      const o = M.registeredVariables[r];
      this.accumulations[s] == null && (this.accumulations[s] = {
        originalName: `${r}/momentum`,
        variable: se(() => ut(o).variable(!1))
      });
      const i = this.accumulations[s].variable, a = Array.isArray(e) ? e[s].tensor : e[r];
      a != null && se(() => {
        let c;
        const l = q(z(this.m, i), a);
        this.useNesterov ? c = q(z(this.c, q(a, z(l, this.m))), o) : c = q(z(this.c, l), o), i.assign(l), o.assign(c);
      });
    }), this.incrementIterations();
  }
  dispose() {
    this.m.dispose(), this.accumulations != null && _e(this.accumulations.map((e) => e.variable));
  }
  /**
   * Sets the momentum of the optimizer.
   *
   * @param momentum
   */
  setMomentum(e) {
    this.momentum = e;
  }
  async getWeights() {
    return [await this.saveIterations()].concat(this.accumulations.map((e) => ({ name: e.originalName, tensor: e.variable })));
  }
  async setWeights(e) {
    e = await this.extractIterations(e);
    const t = !1;
    this.accumulations = e.map((r) => ({ originalName: r.name, variable: r.tensor.variable(t) }));
  }
  getConfig() {
    return {
      learningRate: this.learningRate,
      momentum: this.momentum,
      useNesterov: this.useNesterov
    };
  }
  /** @nocollapse */
  static fromConfig(e, t) {
    return new e(t.learningRate, t.momentum, t.useNesterov);
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class om extends Qt {
  /** @nocollapse */
  static get className() {
    return "RMSProp";
  }
  constructor(e, t = 0.9, r = 0, s = null, o = !1) {
    if (super(), this.learningRate = e, this.decay = t, this.momentum = r, this.epsilon = s, this.accumulatedMeanSquares = [], this.accumulatedMoments = [], this.accumulatedMeanGrads = [], this.centered = o, s == null && (this.epsilon = M.backend.epsilon()), e == null)
      throw new Error("learningRate for RMSPropOptimizer must be defined.");
  }
  applyGradients(e) {
    (Array.isArray(e) ? e.map((r) => r.name) : Object.keys(e)).forEach((r, s) => {
      const o = M.registeredVariables[r], i = !1;
      this.accumulatedMeanSquares[s] == null && (this.accumulatedMeanSquares[s] = {
        originalName: `${r}/rms`,
        variable: se(() => ut(o).variable(i))
      }), this.accumulatedMoments[s] == null && (this.accumulatedMoments[s] = {
        originalName: `${r}/momentum`,
        variable: se(() => ut(o).variable(i))
      }), this.accumulatedMeanGrads[s] == null && this.centered && (this.accumulatedMeanGrads[s] = {
        originalName: `${r}/mg`,
        variable: se(() => ut(o).variable(i))
      });
      const a = Array.isArray(e) ? e[s].tensor : e[r];
      if (a == null)
        return;
      const c = this.accumulatedMeanSquares[s].variable, l = this.accumulatedMoments[s].variable;
      se(() => {
        const u = q(z(c, this.decay), z(Mt(a), 1 - this.decay));
        if (this.centered) {
          const d = this.accumulatedMeanGrads[s].variable, h = q(z(d, this.decay), z(a, 1 - this.decay)), f = lt(z(a, this.learningRate), Cn(mn(u, q(Mt(h), this.epsilon)))), m = q(z(l, this.momentum), f);
          c.assign(u), d.assign(h), l.assign(m);
          const C = mn(o, m);
          o.assign(C);
        } else {
          const d = q(z(c, this.decay), z(Mt(a), 1 - this.decay)), h = q(z(l, this.momentum), lt(z(a, this.learningRate), Cn(q(d, this.epsilon))));
          c.assign(d), l.assign(h);
          const f = mn(o, h);
          o.assign(f);
        }
      });
    }), this.incrementIterations();
  }
  dispose() {
    this.accumulatedMeanSquares != null && _e(this.accumulatedMeanSquares.map((e) => e.variable)), this.accumulatedMeanGrads != null && this.centered && _e(this.accumulatedMeanGrads.map((e) => e.variable)), this.accumulatedMoments != null && _e(this.accumulatedMoments.map((e) => e.variable));
  }
  async getWeights() {
    const e = [...this.accumulatedMeanSquares, ...this.accumulatedMoments];
    return this.centered && e.push(...this.accumulatedMeanGrads), [await this.saveIterations()].concat(e.map((t) => ({ name: t.originalName, tensor: t.variable })));
  }
  async setWeights(e) {
    e = await this.extractIterations(e);
    const t = this.centered ? e.length / 3 : e.length / 2, r = !1;
    this.accumulatedMeanSquares = e.slice(0, t).map((s) => ({
      originalName: s.name,
      variable: s.tensor.variable(r)
    })), this.accumulatedMoments = e.slice(t, t * 2).map((s) => ({
      originalName: s.name,
      variable: s.tensor.variable(r)
    })), this.centered && (this.accumulatedMeanGrads = e.slice(t * 2, t * 3).map((s) => ({
      originalName: s.name,
      variable: s.tensor.variable(r)
    })));
  }
  getConfig() {
    return {
      learningRate: this.learningRate,
      decay: this.decay,
      momentum: this.momentum,
      epsilon: this.epsilon,
      centered: this.centered
    };
  }
  /** @nocollapse */
  static fromConfig(e, t) {
    return new e(t.learningRate, t.decay, t.momentum, t.epsilon, t.centered);
  }
}
/**
 * @license
 * Copyright 2022 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const im = [
  em,
  tm,
  nm,
  rm,
  sm,
  om,
  Aa
];
function am() {
  for (const n of im)
    Jp(n);
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const cm = "model", lm = ".json", um = ".weights.bin";
function Mo(n) {
  return new Promise((e) => setTimeout(e)).then(n);
}
class zt {
  constructor(e) {
    if (!E().getBool("IS_BROWSER"))
      throw new Error("browserDownloads() cannot proceed because the current environment is not a browser.");
    e.startsWith(zt.URL_SCHEME) && (e = e.slice(zt.URL_SCHEME.length)), (e == null || e.length === 0) && (e = cm), this.modelJsonFileName = e + lm, this.weightDataFileName = e + um;
  }
  async save(e) {
    if (typeof document > "u")
      throw new Error("Browser downloads are not supported in this environment since `document` is not present");
    const t = Yt.join(e.weightData), r = window.URL.createObjectURL(new Blob([t], { type: "application/octet-stream" }));
    if (e.modelTopology instanceof ArrayBuffer)
      throw new Error("BrowserDownloads.save() does not support saving model topology in binary formats yet.");
    {
      const s = [{
        paths: ["./" + this.weightDataFileName],
        weights: e.weightSpecs
      }], o = Ca(e, s), i = window.URL.createObjectURL(new Blob([JSON.stringify(o)], { type: "application/json" })), a = this.modelJsonAnchor == null ? document.createElement("a") : this.modelJsonAnchor;
      if (a.download = this.modelJsonFileName, a.href = i, await Mo(() => a.dispatchEvent(new MouseEvent("click"))), e.weightData != null) {
        const c = this.weightDataAnchor == null ? document.createElement("a") : this.weightDataAnchor;
        c.download = this.weightDataFileName, c.href = r, await Mo(() => c.dispatchEvent(new MouseEvent("click")));
      }
      return { modelArtifactsInfo: Br(e) };
    }
  }
}
zt.URL_SCHEME = "downloads://";
const dm = (n) => E().getBool("IS_BROWSER") && !Array.isArray(n) && n.startsWith(zt.URL_SCHEME) ? hm(n.slice(zt.URL_SCHEME.length)) : null;
fe.registerSaveRouter(dm);
function hm(n = "model") {
  return new zt(n);
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Uo(n, e, t, r) {
  i(n), t = t ?? 0, r = r ?? 1, a(t, r);
  let s = 0;
  const o = (c) => (c.then((l) => {
    const u = t + ++s / n.length * (r - t);
    return e(u), l;
  }), c);
  function i(c) {
    O(c != null && Array.isArray(c) && c.length > 0, () => "promises must be a none empty array");
  }
  function a(c, l) {
    O(c >= 0 && c <= 1, () => `Progress fraction must be in range [0, 1], but got startFraction ${c}`), O(l >= 0 && l <= 1, () => `Progress fraction must be in range [0, 1], but got endFraction ${l}`), O(l >= c, () => `startFraction must be no more than endFraction, but got startFraction ${c} and endFraction ${l}`);
  }
  return Promise.all(n.map(o));
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
async function fm(n, e) {
  e == null && (e = {});
  const t = e.fetchFunc == null ? E().platform.fetch : e.fetchFunc, r = n.map((d) => t(d, e.requestInit, { isBinary: !0 })), a = (e.onProgress == null ? await Promise.all(r) : await Uo(r, e.onProgress, 0, 0.5)).map((d) => d.arrayBuffer());
  return e.onProgress == null ? await Promise.all(a) : await Uo(a, e.onProgress, 0.5, 1);
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const pm = "application/octet-stream", mm = "application/json";
class qs {
  constructor(e, t) {
    if (this.DEFAULT_METHOD = "POST", t == null && (t = {}), this.weightPathPrefix = t.weightPathPrefix, this.onProgress = t.onProgress, this.weightUrlConverter = t.weightUrlConverter, t.fetchFunc != null ? (O(typeof t.fetchFunc == "function", () => "Must pass a function that matches the signature of `fetch` (see https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API)"), this.fetch = t.fetchFunc) : this.fetch = E().platform.fetch, O(e != null && e.length > 0, () => "URL path for http must not be null, undefined or empty."), Array.isArray(e) && O(e.length === 2, () => `URL paths for http must have a length of 2, (actual length is ${e.length}).`), this.path = e, t.requestInit != null && t.requestInit.body != null)
      throw new Error("requestInit is expected to have no pre-existing body, but has one.");
    this.requestInit = t.requestInit || {};
  }
  async save(e) {
    if (e.modelTopology instanceof ArrayBuffer)
      throw new Error("BrowserHTTPRequest.save() does not support saving model topology in binary formats yet.");
    const t = Object.assign({ method: this.DEFAULT_METHOD }, this.requestInit);
    t.body = new FormData();
    const r = [{
      paths: ["./model.weights.bin"],
      weights: e.weightSpecs
    }], s = Ca(e, r);
    if (t.body.append("model.json", new Blob([JSON.stringify(s)], { type: mm }), "model.json"), e.weightData != null) {
      const i = Yt.join(e.weightData);
      t.body.append("model.weights.bin", new Blob([i], { type: pm }), "model.weights.bin");
    }
    const o = await this.fetch(this.path, t);
    if (o.ok)
      return {
        modelArtifactsInfo: Br(e),
        responses: [o]
      };
    throw new Error(`BrowserHTTPRequest.save() failed due to HTTP response status ${o.status}.`);
  }
  /**
   * Load model artifacts via HTTP request(s).
   *
   * See the documentation to `tf.io.http` for details on the saved
   * artifacts.
   *
   * @returns The loaded model artifacts (if loading succeeds).
   */
  async load() {
    const e = await this.fetch(this.path, this.requestInit);
    if (!e.ok)
      throw new Error(`Request to ${this.path} failed with status code ${e.status}. Please verify this URL points to the model JSON of the model to load.`);
    let t;
    try {
      t = await e.json();
    } catch {
      let i = `Failed to parse model JSON of response from ${this.path}.`;
      throw this.path.endsWith(".pb") ? i += " Your path contains a .pb file extension. Support for .pb models have been removed in TensorFlow.js 1.0 in favor of .json models. You can re-convert your Python TensorFlow model using the TensorFlow.js 1.0 conversion scripts or you can convert your.pb models with the 'pb2json'NPM script in the tensorflow/tfjs-converter repository." : i += " Please make sure the server is serving valid JSON for this request.", new Error(i);
    }
    const r = t.modelTopology, s = t.weightsManifest;
    if (r == null && s == null)
      throw new Error(`The JSON from HTTP path ${this.path} contains neither model topology or manifest for weights.`);
    return Ef(t, (o) => this.loadWeights(o));
  }
  async loadWeights(e) {
    const t = Array.isArray(this.path) ? this.path[1] : this.path, [r, s] = gm(t), o = this.weightPathPrefix || r, i = Rf(e), a = [], c = [];
    for (const u of e)
      for (const d of u.paths)
        this.weightUrlConverter != null ? c.push(this.weightUrlConverter(d)) : a.push(o + d + s);
    this.weightUrlConverter && a.push(...await Promise.all(c));
    const l = await fm(a, {
      requestInit: this.requestInit,
      fetchFunc: this.fetch,
      onProgress: this.onProgress
    });
    return [i, l];
  }
}
qs.URL_SCHEME_REGEX = /^https?:\/\//;
function gm(n) {
  const e = n.lastIndexOf("/"), t = n.lastIndexOf("?"), r = n.substring(0, e), s = t > e ? n.substring(t) : "";
  return [r + "/", s];
}
function Vo(n) {
  return n.match(qs.URL_SCHEME_REGEX) != null;
}
const Fa = (n, e) => {
  if (typeof fetch > "u" && (e == null || e.fetchFunc == null))
    return null;
  {
    let t = !0;
    if (Array.isArray(n) ? t = n.every((r) => Vo(r)) : t = Vo(n), t)
      return xm(n, e);
  }
  return null;
};
fe.registerSaveRouter(Fa);
fe.registerLoadRouter(Fa);
function xm(n, e) {
  return new qs(n, e);
}
function Da(n, e) {
  const t = n.shape.length, r = e.shape.length;
  if (t < 1)
    throw new Error(`tf.gatherND() expects the input to be rank 1 or higher, but the rank was ${t}.`);
  if (r < 1)
    throw new Error(`tf.gatherND() expects the indices to be rank 1 or higher, but the rank was ${r}.`);
  if (e.dtype !== "int32")
    throw new Error(`tf.gatherND() expects the indices to be int32 type, but the dtype was ${e.dtype}.`);
  if (e.shape[r - 1] > t)
    throw new Error(`index innermost dimension length must be <= tensor rank; saw: ${e.shape[r - 1]} vs. ${t}`);
  if (_(n.shape) === 0)
    throw new Error(`Requested more than 0 entries, but input is empty. Input shape: ${n.shape}.`);
  const s = e.shape, o = s[s.length - 1];
  let i = 1;
  for (let d = 0; d < s.length - 1; ++d)
    i *= s[d];
  const a = n.shape, c = s.slice();
  c.pop();
  let l = 1;
  for (let d = o; d < t; ++d)
    l *= a[d], c.push(a[d]);
  const u = [
    ...me(n.shape).map((d) => d / l),
    1
  ].slice(0, o);
  return [c, i, l, u];
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Is = -2, wm = -1;
function Oa(n, e, t) {
  const r = n.shape.length;
  O(r === e.length, () => `Error in slice${r}D: Length of begin ${e} must match the rank of the array (${r}).`), O(r === t.length, () => `Error in slice${r}D: Length of size ${t} must match the rank of the array (${r}).`);
  for (let s = 0; s < r; ++s)
    O(e[s] + t[s] <= n.shape[s], () => `Error in slice${r}D: begin[${s}] + size[${s}] (${e[s] + t[s]}) would overflow input.shape[${s}] (${n.shape[s]})`);
}
function Cm(n) {
  const e = [];
  let t = 0;
  for (; n > 0; )
    n & 1 && e.push(t), n /= 2, t++;
  return e;
}
function Pa(n, e, t) {
  const r = [];
  for (let s = 0; s < n.length; s++)
    r[s] = Math.ceil((e[s] - n[s]) / t[s]);
  return r;
}
function _a(n, e, t, r) {
  const s = [...n];
  for (let o = s.length; o < r.length; o++)
    s.push(1);
  for (let o = 0; o < t; o++)
    o === 0 ? s[e] = 1 : (s.splice(
      e,
      0,
      1
      /* element to add */
    ), s.pop());
  return s;
}
function Ba(n, e, t) {
  return t <= n ? t : t - (e - 1);
}
function La(n, e) {
  const t = [];
  for (let r = 0; r < n; r++)
    t.push(e + r);
  return t;
}
function bm(n, e, t, r, s, o, i, a, c) {
  const l = n.length;
  let u = new Array(l), d = new Array(l), h = new Array(l);
  if (e.length && t > 0) {
    const f = e[0], m = t + 1;
    u = Ma(i, f, m, r, n), d = Ua(a, f, m, s, n), h = _a(o, f, m, n);
  } else
    for (let f = 0; f < l; f++)
      u[f] = Wa(i, r, o, n, f, c), d[f] = Ga(a, s, o, n, f, c), h[f] = Va(o, f, c);
  return {
    begin: u,
    end: d,
    strides: h
  };
}
function Ma(n, e, t, r, s) {
  const o = [...s], i = La(t, e);
  for (let a = 0; a < o.length; a++)
    if (i.indexOf(a) > -1)
      o[a] = 0;
    else {
      const c = Ba(e, t, a);
      let l = r[c];
      n & 1 << c && (l = 0), o[a] = l;
    }
  return o;
}
function Ua(n, e, t, r, s) {
  const o = [...s], i = La(t, e);
  for (let a = 0; a < o.length; a++)
    if (i.indexOf(a) > -1)
      o[a] = Number.MAX_SAFE_INTEGER;
    else {
      const c = Ba(e, t, a);
      let l = r[c];
      n & 1 << c && (l = Number.MAX_SAFE_INTEGER), o[a] = l;
    }
  for (let a = 0; a < o.length; a++) {
    const c = s[a];
    o[a] < 0 && (o[a] += c), o[a] = wr(0, o[a], s[a]);
  }
  return o;
}
function Va(n, e, t) {
  let r = n[e];
  return (t & 1 << e || r == null) && (r = 1), r;
}
function Wa(n, e, t, r, s, o) {
  let i = e[s];
  const a = t[s] || 1;
  (n & 1 << s || o & 1 << s || i == null) && (a > 0 ? i = Number.MIN_SAFE_INTEGER : i = Number.MAX_SAFE_INTEGER);
  const c = r[s];
  return i < 0 && (i += c), i = wr(0, i, c - 1), i;
}
function Ga(n, e, t, r, s, o) {
  let i = e[s];
  const a = t[s] || 1;
  (n & 1 << s || o & 1 << s || i == null) && (a > 0 ? i = Number.MAX_SAFE_INTEGER : i = Number.MIN_SAFE_INTEGER);
  const c = r[s];
  return i < 0 && (i += c), a > 0 ? i = wr(0, i, c) : i = wr(-1, i, c - 1), i;
}
function Ks(n, e, t) {
  let r = t.length;
  for (let s = 0; s < t.length; s++)
    if (t[s] > 1) {
      r = s;
      break;
    }
  for (let s = r + 1; s < t.length; s++)
    if (e[s] > 0 || t[s] !== n[s])
      return !1;
  return !0;
}
function Ys(n, e) {
  let t = n.length > 0 ? n[n.length - 1] : 1;
  for (let r = 0; r < n.length - 1; r++)
    t += n[r] * e[r];
  return t;
}
function za(n, e, t) {
  let r;
  const s = n.shape.length;
  typeof e == "number" ? r = [e, ...new Array(s - 1).fill(0)] : e.length < s ? r = e.concat(new Array(s - e.length).fill(0)) : r = e.slice(), r.forEach((i) => {
    O(i !== -1, () => "slice() does not support negative begin indexing.");
  });
  let o;
  return t == null ? o = new Array(s).fill(-1) : typeof t == "number" ? o = [t, ...new Array(s - 1).fill(-1)] : t.length < s ? o = t.concat(new Array(s - t.length).fill(-1)) : o = t, o = o.map((i, a) => i >= 0 ? i : (O(i === -1, () => `Negative size values should be exactly -1 but got ${i} for the slice() size at index ${a}.`), n.shape[a] - r[a])), [r, o];
}
function Ha(n, e, t, r, s, o, i, a, c) {
  let l;
  if (r == null ? (l = new Array(e.length), l.fill(1)) : l = r, i != null && i & i - 1)
    throw new Error("Multiple ellipses in slice is not allowed.");
  let u = !1;
  const d = {
    dims: l.length,
    numAddAxisAfterEllipsis: 0,
    begin: e.slice(),
    end: t.slice(),
    strides: l.slice(),
    beginMask: s,
    endMask: o,
    ellipsisMask: i,
    newAxisMask: a,
    shrinkAxisMask: c
  };
  for (let v = 0; v < d.dims; v++)
    u && 1 << v & a && d.numAddAxisAfterEllipsis++, 1 << v & i && (u = !0);
  u || (d.ellipsisMask |= 1 << d.dims, d.dims++);
  const h = {
    dims: n.length,
    beginMask: 0,
    endMask: 0,
    beginValid: !1,
    endValid: !1
  };
  ym(d, h);
  let f = !0, m = !0, C = !0;
  const w = [], x = [];
  for (let v = 0; v < n.length; ++v) {
    if (h.strides[v] === 0)
      throw Error(`strides[${v}] must be non-zero`);
    const I = !!(h.shrinkAxisMask & 1 << v), T = n[v];
    if (T === -1) {
      w.push(I ? 1 : -1);
      continue;
    }
    const A = [h.beginMask & 1 << v, h.endMask & 1 << v], F = [
      h.strides[v] > 0 ? 0 : -1,
      h.strides[v] > 0 ? T : T - 1
    ];
    if (I && h.strides[v] <= 0)
      throw Error("only stride 1 allowed on non-range indexing.");
    C = C && h.strides[v] === 1;
    const k = !!(h.beginMask & 1 << v && h.endMask & 1 << v);
    if (h.beginValid && h.endValid) {
      if (I) {
        const j = h.begin[v] < 0 ? T + h.begin[v] : h.begin[v];
        if (h.begin[v] = j, h.end[v] = h.begin[v] + 1, j < 0 || j >= T)
          throw Error(`slice index ${h.begin[v]} of dimension ${v} out of bounds.`);
      } else
        h.begin[v] = Wo(h.begin[v], 0, h.strides[v], T, A, F), h.end[v] = Wo(h.end[v], 1, h.strides[v], T, A, F);
      const G = h.strides[v] === 1 && h.begin[v] === 0 && h.end[v] === T;
      f = f && G, m = m && (v === 0 && h.strides[v] === 1 || G);
    } else
      f = f && h.strides[v] === 1 && k, m = m && (v === 0 && h.strides[v] === 1 || k);
    let U, V = !1;
    if (h.beginValid && h.endValid ? (U = h.end[v] - h.begin[v], V = !0) : I ? (U = 1, V = !0) : k && T >= 0 && (h.strides[v] < 0 ? U = -T : U = T, V = !0), V) {
      let G;
      U === 0 || U < 0 != h.strides[v] < 0 ? G = 0 : G = Math.trunc(U / h.strides[v]) + (U % h.strides[v] !== 0 ? 1 : 0), w.push(G);
    } else
      w.push(-1);
  }
  for (let v = 0; v < h.finalShapeGatherIndices.length; ++v) {
    const I = h.finalShapeGatherIndices[v];
    I >= 0 ? x.push(w[I]) : I === Is && x.push(1);
  }
  return {
    finalShapeSparse: x.filter((v, I) => h.finalShapeGatherIndices[I] !== Is),
    finalShape: x,
    isIdentity: f,
    sliceDim0: m,
    isSimpleSlice: C,
    begin: h.begin,
    end: h.end,
    strides: h.strides
  };
}
function ym(n, e) {
  e.beginMask = 0, e.endMask = 0, e.shrinkAxisMask = 0;
  let t = 0;
  e.beginValid = n.begin != null, e.endValid = n.end != null, e.begin = new Array(e.dims), e.end = new Array(e.dims), e.strides = new Array(e.dims), e.finalShapeGatherIndices = [], e.finalShapeGatherIndicesSparse = [], e.inputShapeGatherIndicesSparse = new Array(e.dims);
  for (let r = 0; r < n.dims; r++)
    if (1 << r & n.ellipsisMask) {
      const s = Math.min(e.dims - (n.dims - r) + 1 + n.numAddAxisAfterEllipsis, e.dims);
      for (; t < s; t++)
        e.begin[t] = 0, e.end[t] = 0, e.strides[t] = 1, e.beginMask |= 1 << t, e.endMask |= 1 << t, e.finalShapeGatherIndices.push(t), e.finalShapeGatherIndicesSparse.push(-1), e.inputShapeGatherIndicesSparse[t] = r;
    } else if (1 << r & n.newAxisMask)
      e.finalShapeGatherIndices.push(Is), e.finalShapeGatherIndicesSparse.push(-1);
    else {
      if (t === e.begin.length)
        throw Error(`Index out of range using input dim ${t}; input has only ${e.dims} dims, ${e.begin.length}.`);
      n.begin != null && (e.begin[t] = n.begin[r]), n.end != null && (e.end[t] = n.end[r]), e.strides[t] = n.strides[r], n.beginMask & 1 << r && (e.beginMask |= 1 << t), n.endMask & 1 << r && (e.endMask |= 1 << t), n.shrinkAxisMask & 1 << r ? (e.finalShapeGatherIndices.push(wm), e.finalShapeGatherIndicesSparse.push(-1), e.shrinkAxisMask |= 1 << t) : (e.finalShapeGatherIndices.push(t), e.finalShapeGatherIndicesSparse.push(r)), e.inputShapeGatherIndicesSparse[t] = r, t++;
    }
}
function Wo(n, e, t, r, s, o) {
  if (s[e])
    return t > 0 ? o[e] : o[e + 1 & 1];
  {
    const i = n < 0 ? r + n : n;
    return i < o[0] ? o[0] : i > o[1] ? o[1] : i;
  }
}
const $m = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  assertParamsValid: Oa,
  computeFlatOffset: Ys,
  computeOutShape: Pa,
  getNormalizedAxes: bm,
  isSliceContinous: Ks,
  maskToAxes: Cm,
  parseSliceParams: za,
  sliceInfo: Ha,
  startForAxis: Wa,
  startIndicesWithElidedDims: Ma,
  stopForAxis: Ga,
  stopIndicesWithElidedDims: Ua,
  stridesForAxis: Va,
  stridesWithElidedDims: _a
}, Symbol.toStringTag, { value: "Module" }));
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const vm = typeof requestAnimationFrame < "u" ? requestAnimationFrame : typeof setImmediate < "u" ? setImmediate : (n) => n();
function Im() {
  return new Promise((n) => vm(() => n()));
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Xa(n, e) {
  const t = n[0].length;
  n.forEach((s, o) => {
    O(s.length === t, () => `Error in concat${t}D: rank of tensors[${o}] must be the same as the rank of the rest (${t})`);
  }), O(e >= 0 && e < t, () => `Error in concat${t}D: axis must be between 0 and ${t - 1}.`);
  const r = n[0];
  n.forEach((s, o) => {
    for (let i = 0; i < t; i++)
      O(i === e || s[i] === r[i], () => `Error in concat${t}D: Shape of tensors[${o}] (${s}) does not match the shape of the rest (${r}) along the non-concatenated axis ${o}.`);
  });
}
function Ht(n, e) {
  const t = n[0].slice();
  for (let r = 1; r < n.length; r++)
    t[e] += n[r][e];
  return t;
}
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
var Ye;
(function(n) {
  n[n.FIRST_DIM_SIZE = 0] = "FIRST_DIM_SIZE", n[n.VALUE_ROWIDS = 1] = "VALUE_ROWIDS", n[n.ROW_LENGTHS = 2] = "ROW_LENGTHS", n[n.ROW_SPLITS = 3] = "ROW_SPLITS", n[n.ROW_LIMITS = 4] = "ROW_LIMITS", n[n.ROW_STARTS = 5] = "ROW_STARTS";
})(Ye || (Ye = {}));
function ja(n, e, t) {
  let r = new Array();
  if (t == null && e == null)
    return r;
  if (e == null)
    for (; r.length < n + t.length; )
      r.push(-1);
  else
    r = e.slice();
  if (t == null)
    return r;
  if (n + t.length !== r.length)
    throw new Error(`rt input.shape and shape=${e} are incompatible: rt input.rank = ${n + t.length}, but shape.rank = ${r.length}`);
  for (let s = 1; s < t.length; ++s) {
    const o = t[s], i = r[r.length - t.length + s], a = r[i];
    if (o >= 0)
      if (a >= 0) {
        if (a !== o)
          throw new Error(`rt input.shape and shape=${e} are incompatible: rt input.shape[${s + n}] = ${o} but shape[${s + n}] = ${a}`);
      } else
        r[i] = o;
  }
  return r;
}
function qa(n) {
  const e = {
    FIRST_DIM_SIZE: Ye.FIRST_DIM_SIZE,
    VALUE_ROWIDS: Ye.VALUE_ROWIDS,
    ROW_LENGTHS: Ye.ROW_LENGTHS,
    ROW_SPLITS: Ye.ROW_SPLITS,
    ROW_LIMITS: Ye.ROW_LIMITS,
    ROW_STARTS: Ye.ROW_STARTS
  }, t = [];
  for (const r of n)
    if (r in e)
      t.push(e[r]);
    else
      break;
  return t;
}
function Ka(n) {
  return n.length === 0 ? 0 : n[0] === Ye.FIRST_DIM_SIZE ? n.length - 1 : n.length;
}
function Ya(n, e) {
  if (n == null || e == null)
    return;
  const t = n.length, r = e.length;
  if (t >= r)
    throw new Error(`defaultValue.shape=${n} and ragged tensor flatValues.shape=${e}, are incompatible: defaultValue.rank = ${t} must be less than ragged tensor input flatValues.rank = ${r})`);
  for (let s = 0; s < Math.min(t, r - 1); ++s) {
    const o = n[s], i = e[s + 1];
    if (o >= 0 && i >= 0 && o !== 1 && o !== i)
      throw new Error(`defaultValue.shape=${n}, and ragged tensor input flatValues.shape=${e} are incompatible: defaultValue.shape[${s - n.length}] = ${o} but ragged tensor input.flatValues.shape[${s - n.length}] = ${i}`);
  }
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Qs = 30;
function Mr(n) {
  return n <= Qs ? n : cs(n, Math.floor(Math.sqrt(n)));
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Qa(n, e, t) {
  const r = t * (typeof n == "number" ? n : n[0]), s = e * (typeof n == "number" ? n : n[1]);
  return [r, s];
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Zs(n, e, t, r = !0) {
  let s = [];
  if (r)
    s = s.concat(e.slice(0)), s.push(n[0] / t), s = s.concat(n.slice(1));
  else {
    s = s.concat(n[0]);
    const o = e.length;
    for (let i = 0; i < o; ++i)
      s = s.concat([n[i + 1] / e[i], e[i]]);
    s = s.concat(n.slice(o + 1));
  }
  return s;
}
function Js(n, e, t = !0) {
  const r = [];
  if (t) {
    r.push(e);
    for (let s = e + 1; s < n; ++s)
      s <= 2 * e ? (r.push(s), r.push(s - (e + 1))) : r.push(s);
  } else {
    const s = [], o = [];
    for (let i = 1; i < n; ++i)
      i >= e * 2 + 1 || i % 2 === 1 ? o.push(i) : s.push(i);
    r.push(...s), r.push(0), r.push(...o);
  }
  return r;
}
function eo(n, e, t, r = !0) {
  const s = [];
  r ? s.push(n[0] / t) : s.push(n[0] * t);
  for (let o = 1; o < n.length; ++o)
    o <= e.length ? r ? s.push(e[o - 1] * n[o]) : s.push(n[o] / e[o - 1]) : s.push(n[o]);
  return s;
}
function Za(n, e) {
  const t = [0];
  for (let r = 0; r < e; ++r)
    t.push(n[r][0]);
  return t;
}
function Ja(n, e, t) {
  const r = n.slice(0, 1);
  for (let s = 0; s < t; ++s)
    r.push(n[s + 1] - e[s][0] - e[s][1]);
  return r;
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ec = 1.7580993408473768, tc = 1.0507009873554805;
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const nc = 0.3275911, rc = 0.254829592, sc = -0.284496736, oc = 1.421413741, ic = -1.453152027, ac = 1.061405429;
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ss(n, e) {
  if (n.length !== e.length)
    throw new Error(`Cannot merge real and imag arrays of different lengths. real:${n.length}, imag: ${e.length}.`);
  const t = new Float32Array(n.length * 2);
  for (let r = 0; r < t.length; r += 2)
    t[r] = n[r / 2], t[r + 1] = e[r / 2];
  return t;
}
function Sm(n) {
  const e = new Float32Array(n.length / 2), t = new Float32Array(n.length / 2);
  for (let r = 0; r < n.length; r += 2)
    e[r / 2] = n[r], t[r / 2] = n[r + 1];
  return { real: e, imag: t };
}
function Em(n) {
  const e = Math.ceil(n.length / 4), t = new Float32Array(e), r = new Float32Array(e);
  for (let s = 0; s < n.length; s += 4)
    t[Math.floor(s / 4)] = n[s], r[Math.floor(s / 4)] = n[s + 1];
  return { real: t, imag: r };
}
function Rm(n) {
  const e = Math.floor(n.length / 4), t = new Float32Array(e), r = new Float32Array(e);
  for (let s = 2; s < n.length; s += 4)
    t[Math.floor(s / 4)] = n[s], r[Math.floor(s / 4)] = n[s + 1];
  return { real: t, imag: r };
}
function Tm(n, e) {
  const t = n[e * 2], r = n[e * 2 + 1];
  return { real: t, imag: r };
}
function Nm(n, e, t, r) {
  n[r * 2] = e, n[r * 2 + 1] = t;
}
function km(n, e) {
  const t = new Float32Array(n / 2), r = new Float32Array(n / 2);
  for (let s = 0; s < Math.ceil(n / 2); s++) {
    const o = (e ? 2 : -2) * Math.PI * (s / n);
    t[s] = Math.cos(o), r[s] = Math.sin(o);
  }
  return { real: t, imag: r };
}
function Am(n, e, t) {
  const r = (t ? 2 : -2) * Math.PI * (n / e), s = Math.cos(r), o = Math.sin(r);
  return { real: s, imag: o };
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Jr = "->", Fm = /->/g, Go = ",", zo = "...";
function cc(n, e) {
  n = n.replace(/\s/g, "");
  const t = (n.length - n.replace(Fm, "").length) / Jr.length;
  if (t < 1)
    throw new Error("Equations without an arrow are not supported.");
  if (t > 1)
    throw new Error(`Equation must contain exactly one arrow ("${Jr}").`);
  const [r, s] = n.split(Jr);
  O(r.indexOf(zo) === -1, () => `The ellipsis notation ("${zo}") is not supported yet.`);
  const o = r.split(Go), i = o.length;
  if (e !== i)
    throw new Error(`Expected ${i} input tensors, received ${e}`);
  if (i > 2)
    throw new Error("Support for more than 2 input tensors is not implemented yet.");
  const a = [];
  for (let h = 0; h < s.length; ++h) {
    const f = s[h];
    if (!o.some((m) => m.indexOf(f) !== -1))
      throw new Error(`Output subscripts contain the label ${f} not present in the input subscripts.`);
    a.indexOf(f) === -1 && a.push(f);
  }
  for (let h = 0; h < r.length; ++h) {
    const f = r[h];
    a.indexOf(f) === -1 && f !== Go && a.push(f);
  }
  const c = new Array(o.length);
  for (let h = 0; h < i; ++h) {
    if (new Set(o[h].split("")).size !== o[h].length)
      throw new Error(`Found duplicate axes in input component ${o[h]}. Support for duplicate axes in input is not implemented yet.`);
    c[h] = [];
    for (let f = 0; f < o[h].length; ++f)
      c[h].push(a.indexOf(o[h][f]));
  }
  const l = a.length, u = s.length, d = [];
  for (let h = u; h < l; ++h)
    d.push(h);
  return { allDims: a, summedDims: d, idDims: c };
}
function lc(n, e) {
  let t = new Array(n);
  t.fill(-1);
  for (let s = 0; s < e.length; ++s)
    t[e[s]] = s;
  const r = [];
  for (let s = 0; s < n; ++s)
    t[s] === -1 && r.push(s);
  return t = t.filter((s) => s !== -1), { permutationIndices: t, expandDims: r };
}
function uc(n, e, t) {
  const r = new Array(n);
  for (let s = 0; s < t.length; ++s) {
    const o = t[s].shape;
    for (let i = 0; i < e[s].length; ++i)
      r[e[s][i]] === void 0 ? r[e[s][i]] = o[i] : O(r[e[s][i]] === o[i], () => `Expected dimension ${r[e[s][i]]} at axis ${i} of input shaped ${JSON.stringify(o)}, but got dimension ${o[i]}`);
  }
}
function dc(n, e) {
  const t = n, r = [];
  let s = 0;
  n.length === 0 && t.push(-1), s = n.length + 1;
  for (let i = 0; i < s; ++i)
    r.push([]);
  const o = [];
  for (let i = 0; i < t.length; ++i) {
    const a = t[i], c = Dm(e, a);
    for (const l of c)
      o.indexOf(l) === -1 && (r[i].push(l), o.push(l));
  }
  return { path: t, steps: r };
}
function hc(n) {
  return n.every((e, t) => e === t);
}
function Dm(n, e) {
  const t = [];
  for (let r = 0; r < n.length; ++r)
    (n[r].length === 0 || n[r].indexOf(e) !== -1 || e === -1) && t.push(r);
  return t;
}
function fc(n, e, t = 0) {
  let r = [];
  if (typeof e == "number")
    O(n.shape[t] % e === 0, () => "Number of splits must evenly divide the axis."), r = new Array(e).fill(n.shape[t] / e);
  else {
    const s = e.reduce((i, a) => (a === -1 && (i += 1), i), 0);
    O(s <= 1, () => "There should be only one negative value in split array.");
    const o = e.indexOf(-1);
    if (o !== -1) {
      const i = e.reduce((a, c) => c > 0 ? a + c : a);
      e[o] = n.shape[t] - i;
    }
    O(n.shape[t] === e.reduce((i, a) => i + a), () => "The sum of sizes must match the size of the axis dimension."), r = e;
  }
  return r;
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function pc(n) {
  return `Received SparseTensor with denseShape[0] = 0 but
  indices.shape[0] = ${n}`;
}
function mc(n, e) {
  return `indices(${n}, 0) is invalid: ${e} < 0`;
}
function gc(n, e, t) {
  return `indices(${n}, 0) is invalid: ${e} >= ${t}`;
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function xc(n, e) {
  return `only one output dimension may be -1, not both ${n} and ${e}`;
}
function wc(n, e) {
  return `size ${n} must be non-negative, not ${e}`;
}
function Cc() {
  return "reshape cannot infer the missing input size for an empty tensor unless all specified input sizes are non-zero";
}
function bc(n, e) {
  const t = _(n), r = _(e);
  return `Input to reshape is a SparseTensor with ${t}
  dense values, but the requested shape requires a multiple of ${r}. inputShape=${n} outputShape= ${e}`;
}
function yc(n, e) {
  const t = _(n), r = _(e);
  return `Input to reshape is a tensor with ${t} dense values, but the requested shape has ${r}. inputShape=${n} outputShape=${e}`;
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Es() {
  return "segment ids must be >= 0";
}
function $c() {
  return "segment ids are not increasing";
}
function vc(n, e) {
  return `Segment id ${n} out of range [0, ${e}), possibly because segmentIds input is not sorted.`;
}
function Ic(n, e, t) {
  return `Bad: indices[${n}] == ${e} out of range [0, ${t})`;
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Sc(n, e) {
  let t = !1, r;
  for (n <= Qs ? (r = n, t = !0) : r = cs(n, Math.floor(Math.sqrt(n))); !t; )
    r > e || r === n ? t = !0 : r = cs(n, r + 1);
  return r;
}
function Ec(n, e, t) {
  const r = [], s = n.length;
  for (let o = 0; o < s; o++)
    o !== e ? r.push(n[o]) : r.push(t);
  return r;
}
function Rc(n, e, t, r) {
  const s = e.shape.length, o = n.shape.length;
  if (r !== 0 && (r < -s || r > s))
    throw new Error(`Expect batchDims in the range of [-${s}, ${s}], but got ${r}`);
  if (r < 0 && (r += s), r > o)
    throw new Error(`batchDims (${r}) must be less than rank(x) (
    ${o}).`);
  if (t < r)
    throw new Error(`batchDims (${r}) must be less than or equal to axis (${t}).`);
  for (let d = 0; d < r; ++d)
    if (n.shape[d] !== e.shape[d])
      throw new Error(`x.shape[${d}]: ${n.shape[d]} should be equal to indices.shape[${d}]: ${e.shape[d]}.`);
  const i = n.shape[t], a = [];
  let c = 1, l = 1, u = 1;
  for (let d = 0; d < r; ++d)
    a.push(n.shape[d]), c *= n.shape[d];
  for (let d = r; d < t; d++)
    a.push(n.shape[d]), l *= n.shape[d];
  for (let d = r; d < s; d++)
    a.push(e.shape[d]);
  for (let d = t + 1; d < o; d++)
    a.push(n.shape[d]), u *= n.shape[d];
  return { batchSize: c, sliceSize: u, outerSize: l, dimSize: i, outputShape: a };
}
const Om = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  collectGatherOpShapeInfo: Rc,
  computeOutShape: Ec,
  segOpComputeOptimalWindowSize: Sc
}, Symbol.toStringTag, { value: "Module" }));
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function bn(n) {
  try {
    return n.map((e) => xn(e));
  } catch (e) {
    throw new Error(`Failed to decode encoded string bytes into utf-8, error: ${e}`);
  }
}
function Tc(n) {
  return n.map((e) => Lt(e));
}
const Pm = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  ERF_A1: rc,
  ERF_A2: sc,
  ERF_A3: oc,
  ERF_A4: ic,
  ERF_A5: ac,
  ERF_P: nc,
  PARALLELIZE_THRESHOLD: Qs,
  get RowPartitionType() {
    return Ye;
  },
  SELU_SCALE: tc,
  SELU_SCALEALPHA: ec,
  applyActivation: Mp,
  assertAndGetBroadcastShape: ve,
  assertAxesAreInnerMostDims: tt,
  assertParamsConsistent: Xa,
  assignToTypedArray: Nm,
  axesAreInnerMostDims: Hs,
  calculateShapes: Lr,
  checkEinsumDimSizes: uc,
  checkPadOnDimRoundingMode: ip,
  combineLocations: Na,
  combineRaggedTensorToTensorShapes: ja,
  complexWithEvenIndex: Em,
  complexWithOddIndex: Rm,
  computeConv2DInfo: et,
  computeConv3DInfo: Jn,
  computeDefaultPad: Gs,
  computeDilation2DInfo: Ra,
  computeOptimalWindowSize: Mr,
  computeOutAndReduceShapes: ht,
  computeOutShape: Ht,
  computePool2DInfo: In,
  computePool3DInfo: Zn,
  convertConv2DDataFormat: En,
  decodeEinsumEquation: cc,
  eitherStridesOrDilationsAreOne: Sn,
  expandShapeToKeepDim: gt,
  exponent: Am,
  exponents: km,
  fromStringArrayToUint8: Tc,
  fromUint8ToStringArray: bn,
  getAxesPermutation: He,
  getBroadcastDims: Er,
  getComplexWithIndex: Tm,
  getEinsumComputePath: dc,
  getEinsumPermutation: lc,
  getFusedBiasGradient: Lp,
  getFusedDyActivation: Bp,
  getImageCenter: Qa,
  getInnerMostAxes: Xe,
  getPermuted: Js,
  getRaggedRank: Ka,
  getReductionAxes: Ta,
  getReshaped: Zs,
  getReshapedPermuted: eo,
  getRowPartitionTypesHelper: qa,
  getSliceBeginCoords: Za,
  getSliceSize: Ja,
  getSparseFillEmptyRowsIndicesDenseShapeMismatch: pc,
  getSparseFillEmptyRowsNegativeIndexErrorMessage: mc,
  getSparseFillEmptyRowsOutOfRangeIndexErrorMessage: gc,
  getSparseReshapeEmptyTensorZeroOutputDimErrorMessage: Cc,
  getSparseReshapeInputOutputMismatchErrorMessage: yc,
  getSparseReshapeInputOutputMultipleErrorMessage: bc,
  getSparseReshapeMultipleNegativeOneOutputDimErrorMessage: xc,
  getSparseReshapeNegativeOutputDimErrorMessage: wc,
  getSparseSegmentReductionIndicesOutOfRangeErrorMessage: Ic,
  getSparseSegmentReductionNegativeSegmentIdsErrorMessage: Es,
  getSparseSegmentReductionNonIncreasingSegmentIdsErrorMessage: $c,
  getSparseSegmentReductionSegmentIdOutOfRangeErrorMessage: vc,
  getUndoAxesPermutation: Xs,
  isIdentityPermutation: hc,
  log: Ph,
  mergeRealAndImagArrays: Ss,
  prepareAndValidate: Da,
  prepareSplitSize: fc,
  segment_util: Om,
  shouldFuse: Up,
  slice_util: $m,
  splitRealAndImagArrays: Sm,
  stridesOrDilationsArePositive: op,
  tupleValuesAreOne: $s,
  upcastType: dt,
  validateDefaultValueShape: Ya,
  validateInput: Pp,
  validateUpdateShape: ka,
  warn: Qe
}, Symbol.toStringTag, { value: "Module" }));
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
am();
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Ot = {}, ar = {
  alpha: !1,
  antialias: !1,
  premultipliedAlpha: !1,
  preserveDrawingBuffer: !1,
  depth: !1,
  stencil: !1,
  failIfMajorPerformanceCaveat: !0
};
function _m(n, e) {
  Ot[n] = e;
}
function Ze(n, e) {
  if (!(n in Ot) || e != null) {
    const r = Lm(n, e);
    if (r !== null)
      Ot[n] = r;
    else
      return console.log("Could not get context for WebGL version", n), null;
  }
  const t = Ot[n];
  return t == null || t.isContextLost() ? (delete Ot[n], Ze(n)) : (t.disable(t.DEPTH_TEST), t.disable(t.STENCIL_TEST), t.disable(t.BLEND), t.disable(t.DITHER), t.disable(t.POLYGON_OFFSET_FILL), t.disable(t.SAMPLE_COVERAGE), t.enable(t.SCISSOR_TEST), t.enable(t.CULL_FACE), t.cullFace(t.BACK), Ot[n]);
}
function Bm(n) {
  if (!E().getBool("IS_SAFARI") && typeof OffscreenCanvas < "u" && n === 2)
    return new OffscreenCanvas(300, 150);
  if (typeof document < "u")
    return document.createElement("canvas");
  throw new Error("Cannot create a canvas in this context");
}
function Lm(n, e) {
  if (n !== 1 && n !== 2)
    throw new Error("Cannot get WebGL rendering context, WebGL is disabled.");
  const t = e ?? Bm(n);
  return t.addEventListener("webglcontextlost", (r) => {
    r.preventDefault(), delete Ot[n];
  }, !1), E().getBool("SOFTWARE_WEBGL_ENABLED") && (ar.failIfMajorPerformanceCaveat = !1), n === 1 ? t.getContext("webgl", ar) || t.getContext("experimental-webgl", ar) : t.getContext("webgl2", ar);
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
var Xn;
(function(n) {
  n[n.DENSE = 0] = "DENSE", n[n.SHARED_BATCH = 1] = "SHARED_BATCH";
})(Xn || (Xn = {}));
var Pe;
(function(n) {
  n[n.RENDER = 0] = "RENDER", n[n.UPLOAD = 1] = "UPLOAD", n[n.PIXELS = 2] = "PIXELS", n[n.DOWNLOAD = 3] = "DOWNLOAD";
})(Pe || (Pe = {}));
var pe;
(function(n) {
  n[n.UNPACKED_FLOAT16 = 0] = "UNPACKED_FLOAT16", n[n.UNPACKED_FLOAT32 = 1] = "UNPACKED_FLOAT32", n[n.PACKED_4X1_UNSIGNED_BYTE = 2] = "PACKED_4X1_UNSIGNED_BYTE", n[n.PACKED_2X2_FLOAT32 = 3] = "PACKED_2X2_FLOAT32", n[n.PACKED_2X2_FLOAT16 = 4] = "PACKED_2X2_FLOAT16";
})(pe || (pe = {}));
function er(n, e) {
  return [e, n];
}
function Mm(n, e) {
  return n * e;
}
function cr(n) {
  const e = _(n), t = Math.ceil(e / 4);
  return is(t);
}
function Rn(n, e) {
  return [
    Math.max(1, Math.ceil(e / 2)),
    Math.max(1, Math.ceil(n / 2))
  ];
}
function Um(n, e) {
  const [t, r] = Rn(n, e);
  return t * r * 4;
}
function to(n, e) {
  const t = n;
  let r, s, o, i, a, c, l, u, d, h;
  return E().getNumber("WEBGL_VERSION") === 2 ? (r = t.R32F, s = t.R16F, o = t.RGBA16F, i = t.RGBA32F, a = t.RED, l = 4, u = 1, d = t.HALF_FLOAT, h = t.FLOAT, c = t.RGBA8) : (r = n.RGBA, s = n.RGBA, o = n.RGBA, i = t.RGBA, a = n.RGBA, l = 4, u = 4, d = e != null ? e.HALF_FLOAT_OES : null, h = n.FLOAT, c = n.RGBA), {
    internalFormatFloat: r,
    internalFormatHalfFloat: s,
    internalFormatPackedHalfFloat: o,
    internalFormatPackedFloat: i,
    textureFormatFloat: a,
    downloadTextureFormat: c,
    downloadUnpackNumChannels: l,
    defaultNumChannels: u,
    textureTypeHalfFloat: d,
    textureTypeFloat: h
  };
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function B(n, e) {
  const t = e();
  return E().getBool("DEBUG") && Vm(n), t;
}
function Vm(n) {
  const e = n.getError();
  if (e !== n.NO_ERROR)
    throw new Error("WebGL Error: " + Hm(n, e));
}
const Wm = 596e-10, Gm = 65504;
function zm(n) {
  return !!(E().getBool("WEBGL_RENDER_FLOAT32_ENABLED") || n === 0 || Wm < Math.abs(n) && Math.abs(n) < Gm);
}
function Hm(n, e) {
  switch (e) {
    case n.NO_ERROR:
      return "NO_ERROR";
    case n.INVALID_ENUM:
      return "INVALID_ENUM";
    case n.INVALID_VALUE:
      return "INVALID_VALUE";
    case n.INVALID_OPERATION:
      return "INVALID_OPERATION";
    case n.INVALID_FRAMEBUFFER_OPERATION:
      return "INVALID_FRAMEBUFFER_OPERATION";
    case n.OUT_OF_MEMORY:
      return "OUT_OF_MEMORY";
    case n.CONTEXT_LOST_WEBGL:
      return "CONTEXT_LOST_WEBGL";
    default:
      return `Unknown error code ${e}`;
  }
}
function lr(n, e) {
  return xt(n, () => n.getExtension(e), 'Extension "' + e + '" not supported on this browser.');
}
function Xm(n, e) {
  const t = xt(n, () => n.createShader(n.VERTEX_SHADER), "Unable to create vertex WebGLShader.");
  if (B(n, () => n.shaderSource(t, e)), B(n, () => n.compileShader(t)), n.getShaderParameter(t, n.COMPILE_STATUS) === !1)
    throw console.log(n.getShaderInfoLog(t)), new Error("Failed to compile vertex shader.");
  return t;
}
function jm(n, e) {
  const t = xt(n, () => n.createShader(n.FRAGMENT_SHADER), "Unable to create fragment WebGLShader.");
  if (B(n, () => n.shaderSource(t, e)), B(n, () => n.compileShader(t)), E().get("ENGINE_COMPILE_ONLY"))
    return t;
  if (n.getShaderParameter(t, n.COMPILE_STATUS) === !1)
    throw Nc(e, n.getShaderInfoLog(t)), new Error("Failed to compile fragment shader.");
  return t;
}
const qm = /ERROR: [0-9]+:([0-9]+):/g;
function Nc(n, e) {
  const t = qm.exec(e);
  if (t == null) {
    console.log(`Couldn't parse line number in error: ${e}`), console.log(n);
    return;
  }
  const r = +t[1], s = n.split(`
`), o = s.length.toString().length + 2, i = s.map((d, h) => dn((h + 1).toString(), o) + d);
  let a = 0;
  for (let d = 0; d < i.length; d++)
    a = Math.max(i[d].length, a);
  const c = i.slice(0, r - 1), l = i.slice(r - 1, r), u = i.slice(r);
  console.log(c.join(`
`)), console.log(e.split(`
`)[0]), console.log(`%c ${dn(l[0], a)}`, "border:1px solid red; background-color:#e3d2d2; color:#a61717"), console.log(u.join(`
`));
}
function Km(n) {
  return xt(n, () => n.createProgram(), "Unable to create WebGLProgram.");
}
function Ym(n, e) {
  if (B(n, () => n.linkProgram(e)), !E().get("ENGINE_COMPILE_ONLY") && n.getProgramParameter(e, n.LINK_STATUS) === !1)
    throw console.log(n.getProgramInfoLog(e)), new Error("Failed to link vertex and fragment shaders.");
}
function es(n, e) {
  if (B(n, () => n.validateProgram(e)), n.getProgramParameter(e, n.VALIDATE_STATUS) === !1)
    throw console.log(n.getProgramInfoLog(e)), new Error("Shader program validation failed.");
}
function Qm(n, e) {
  const t = xt(n, () => n.createBuffer(), "Unable to create WebGLBuffer");
  return B(n, () => n.bindBuffer(n.ARRAY_BUFFER, t)), B(n, () => n.bufferData(n.ARRAY_BUFFER, e, n.STATIC_DRAW)), t;
}
function Zm(n, e) {
  const t = xt(n, () => n.createBuffer(), "Unable to create WebGLBuffer");
  return B(n, () => n.bindBuffer(n.ELEMENT_ARRAY_BUFFER, t)), B(n, () => n.bufferData(n.ELEMENT_ARRAY_BUFFER, e, n.STATIC_DRAW)), t;
}
function Jm(n) {
  return xt(n, () => n.createTexture(), "Unable to create WebGLTexture.");
}
function eg(n, e) {
  const t = E().getNumber("WEBGL_MAX_TEXTURE_SIZE");
  if (n <= 0 || e <= 0) {
    const r = `[${n}x${e}]`;
    throw new Error("Requested texture size " + r + " is invalid.");
  }
  if (n > t || e > t) {
    const r = `[${n}x${e}]`, s = `[${t}x${t}]`;
    throw new Error("Requested texture size " + r + " greater than WebGL maximum on this browser / GPU " + s + ".");
  }
}
function tg(n) {
  return xt(n, () => n.createFramebuffer(), "Unable to create WebGLFramebuffer.");
}
function Ho(n, e, t, r, s, o, i) {
  const a = n.getAttribLocation(e, t);
  return a === -1 ? !1 : (B(n, () => n.bindBuffer(n.ARRAY_BUFFER, r)), B(n, () => n.vertexAttribPointer(a, s, n.FLOAT, !1, o, i)), B(n, () => n.enableVertexAttribArray(a)), !0);
}
function ng(n, e, t) {
  ag(n, t), B(n, () => n.activeTexture(n.TEXTURE0 + t)), B(n, () => n.bindTexture(n.TEXTURE_2D, e));
}
function rg(n, e, t) {
  return xt(n, () => n.getUniformLocation(e, t), 'uniform "' + t + '" not present in program.');
}
function sg(n, e, t) {
  return n.getUniformLocation(e, t);
}
function og(n, e, t, r) {
  B(n, () => ng(n, e, r)), B(n, () => n.uniform1i(t, r));
}
function ts(n, e, t) {
  B(n, () => n.bindFramebuffer(n.FRAMEBUFFER, t)), B(n, () => n.framebufferTexture2D(n.FRAMEBUFFER, n.COLOR_ATTACHMENT0, n.TEXTURE_2D, e, 0));
}
function Xo(n, e) {
  B(n, () => n.bindFramebuffer(n.FRAMEBUFFER, e)), B(n, () => n.framebufferTexture2D(n.FRAMEBUFFER, n.COLOR_ATTACHMENT0, n.TEXTURE_2D, null, 0));
}
function ur(n) {
  const e = n.checkFramebufferStatus(n.FRAMEBUFFER);
  if (e !== n.FRAMEBUFFER_COMPLETE)
    throw new Error("Error binding framebuffer: " + ig(n, e));
}
function ig(n, e) {
  switch (e) {
    case n.FRAMEBUFFER_INCOMPLETE_ATTACHMENT:
      return "FRAMEBUFFER_INCOMPLETE_ATTACHMENT";
    case n.FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT:
      return "FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT";
    case n.FRAMEBUFFER_INCOMPLETE_DIMENSIONS:
      return "FRAMEBUFFER_INCOMPLETE_DIMENSIONS";
    case n.FRAMEBUFFER_UNSUPPORTED:
      return "FRAMEBUFFER_UNSUPPORTED";
    default:
      return `unknown error ${e}`;
  }
}
function xt(n, e, t) {
  const r = B(n, () => e());
  if (r == null)
    throw new Error(t);
  return r;
}
function ag(n, e) {
  const t = n.MAX_COMBINED_TEXTURE_IMAGE_UNITS - 1, r = e + n.TEXTURE0;
  if (r < n.TEXTURE0 || r > t) {
    const s = `[gl.TEXTURE0, gl.TEXTURE${t}]`;
    throw new Error(`textureUnit must be in ${s}.`);
  }
}
function yn(n, e = 2) {
  return _(n.slice(0, n.length - e));
}
function $n(n) {
  if (n.length === 0)
    throw Error("Cannot get rows and columns of an empty shape array.");
  return [
    n.length > 1 ? n[n.length - 2] : 1,
    n[n.length - 1]
  ];
}
function dr(n) {
  let e = [1, 1, 1];
  return n.length === 0 || n.length === 1 && n[0] === 1 || (e = [yn(n), ...$n(n)]), e;
}
function cg(n, e = !1) {
  let t = E().getNumber("WEBGL_MAX_TEXTURE_SIZE"), r = E().getNumber("WEBGL_MAX_SIZE_FOR_NARROW_TEXTURE");
  r === 1 / 0 && E().getBool("WEBGL_AUTO_SQUARIFY_NARROW_TEXTURE_SHAPE") && (r = t / 2), e && (t = t * 2, r = r * 2, n = n.map((a, c) => c >= n.length - 2 ? As(n[c]) : n[c]), n.length === 1 && (n = [2, n[0]])), n.length !== 2 && (n = jt(n).newShape);
  let s = _(n), o = null;
  n.length <= 1 && s <= t ? o = [1, s] : n.length === 2 && n[0] <= t && n[1] <= t ? o = n : n.length === 3 && n[0] * n[1] <= t && n[2] <= t ? o = [n[0] * n[1], n[2]] : n.length === 3 && n[0] <= t && n[1] * n[2] <= t ? o = [n[0], n[1] * n[2]] : n.length === 4 && n[0] * n[1] * n[2] <= t && n[3] <= t ? o = [n[0] * n[1] * n[2], n[3]] : n.length === 4 && n[0] <= t && n[1] * n[2] * n[3] <= t && (o = [n[0], n[1] * n[2] * n[3]]);
  const i = o != null && Math.max(...o) > r && Math.min(...o) <= (e ? 2 : 1) && Math.min(...o) > 0;
  if (o == null || i)
    if (e) {
      const a = yn(n);
      let c = 2, l = 2;
      n.length && ([c, l] = $n(n)), s = a * (c / 2) * (l / 2), o = is(s).map((u) => u * 2);
    } else
      o = is(s);
  return o;
}
function hr(n) {
  return n % 2 === 0;
}
function Rr(n, e) {
  if (n = n.slice(-2), e = e.slice(-2), ge(n, e) || !n.length || !e.length || n[0] === 0 || n[1] === 0 || e[0] === 0 || e[1] === 0)
    return !0;
  if (n.length !== e.length) {
    const t = n[n.length - 1], r = e[e.length - 1];
    if (t === r || hr(t) && hr(r) && (n[0] === 1 || e[0] === 1))
      return !0;
  }
  return n[1] === e[1] && hr(n[0]) && hr(e[0]);
}
let ns, rs;
function lg(n) {
  if (ns == null) {
    const e = Ze(n);
    ns = e.getParameter(e.MAX_TEXTURE_SIZE);
  }
  return ns;
}
function ug(n) {
  if (rs == null) {
    const e = Ze(n);
    rs = e.getParameter(e.MAX_TEXTURE_IMAGE_UNITS);
  }
  return Math.min(16, rs);
}
function dg(n) {
  if (n === 0)
    return 0;
  let e;
  const t = Ze(n);
  return Ge(t, "EXT_disjoint_timer_query_webgl2") && n === 2 ? e = 2 : Ge(t, "EXT_disjoint_timer_query") ? e = 1 : e = 0, e;
}
function Ge(n, e) {
  return n.getExtension(e) != null;
}
function jo(n) {
  try {
    if (Ze(n) != null)
      return !0;
  } catch (e) {
    return console.log("Error when getting WebGL context: ", e), !1;
  }
  return !1;
}
function hg(n) {
  if (n === 0)
    return !1;
  const e = Ze(n);
  if (n === 1) {
    if (!Ge(e, "OES_texture_float"))
      return !1;
  } else if (!Ge(e, "EXT_color_buffer_float"))
    return !1;
  return Rs(e);
}
function fg(n) {
  if (n === 0)
    return !1;
  const e = Ze(n);
  if (n === 1) {
    if (!Ge(e, "OES_texture_float") || !Ge(e, "WEBGL_color_buffer_float"))
      return !1;
  } else {
    if (Ge(e, "EXT_color_buffer_float"))
      return Rs(e);
    const r = "EXT_color_buffer_half_float";
    if (Ge(e, r)) {
      const s = e.getExtension(r);
      return pg(e, s);
    }
    return !1;
  }
  return Rs(e);
}
function Rs(n) {
  const e = to(n), t = n.createTexture();
  n.bindTexture(n.TEXTURE_2D, t), n.texImage2D(n.TEXTURE_2D, 0, e.internalFormatFloat, 1, 1, 0, e.textureFormatFloat, e.textureTypeFloat, null);
  const o = n.createFramebuffer();
  n.bindFramebuffer(n.FRAMEBUFFER, o), n.framebufferTexture2D(n.FRAMEBUFFER, n.COLOR_ATTACHMENT0, n.TEXTURE_2D, t, 0);
  const i = n.checkFramebufferStatus(n.FRAMEBUFFER) === n.FRAMEBUFFER_COMPLETE;
  return n.bindTexture(n.TEXTURE_2D, null), n.bindFramebuffer(n.FRAMEBUFFER, null), n.deleteTexture(t), n.deleteFramebuffer(o), i;
}
function pg(n, e) {
  const t = to(n, e), r = n.createTexture();
  n.bindTexture(n.TEXTURE_2D, r), n.texImage2D(n.TEXTURE_2D, 0, t.internalFormatHalfFloat, 1, 1, 0, t.textureFormatFloat, t.textureTypeHalfFloat, null);
  const i = n.createFramebuffer();
  n.bindFramebuffer(n.FRAMEBUFFER, i), n.framebufferTexture2D(n.FRAMEBUFFER, n.COLOR_ATTACHMENT0, n.TEXTURE_2D, r, 0);
  const a = n.checkFramebufferStatus(n.FRAMEBUFFER) === n.FRAMEBUFFER_COMPLETE;
  return n.bindTexture(n.TEXTURE_2D, null), n.bindFramebuffer(n.FRAMEBUFFER, null), n.deleteTexture(r), n.deleteFramebuffer(i), a;
}
function mg(n) {
  return n !== 2 ? !1 : Ze(n).fenceSync != null;
}
function tr(n, e) {
  Array.isArray(n) || (n = [n]), n.forEach((t) => {
    t != null && O(t.dtype !== "complex64", () => `${e} does not support complex64 tensors in the WebGL backend.`);
  });
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const L = E();
L.registerFlag("HAS_WEBGL", () => L.getNumber("WEBGL_VERSION") > 0);
L.registerFlag("WEBGL_VERSION", () => jo(2) ? 2 : jo(1) ? 1 : 0);
L.registerFlag("WEBGL_CHECK_NUMERICAL_PROBLEMS", () => !1);
L.registerFlag("WEBGL_BUFFER_SUPPORTED", () => L.get("WEBGL_VERSION") === 2);
L.registerFlag("WEBGL_CPU_FORWARD", () => !0);
L.registerFlag("WEBGL_FORCE_F16_TEXTURES", () => !1);
L.registerFlag("WEBGL_PACK", () => L.getBool("HAS_WEBGL"));
L.registerFlag("WEBGL_PACK_NORMALIZATION", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_PACK_CLIP", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_PACK_DEPTHWISECONV", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_PACK_BINARY_OPERATIONS", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_PACK_UNARY_OPERATIONS", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_PACK_ARRAY_OPERATIONS", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_PACK_IMAGE_OPERATIONS", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_PACK_REDUCE", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_LAZILY_UNPACK", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_CONV_IM2COL", () => L.getBool("WEBGL_PACK"));
L.registerFlag("WEBGL_MAX_TEXTURE_SIZE", () => lg(L.getNumber("WEBGL_VERSION")));
L.registerFlag("WEBGL_MAX_TEXTURES_IN_SHADER", () => ug(L.getNumber("WEBGL_VERSION")));
L.registerFlag("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_VERSION", () => {
  const n = L.getNumber("WEBGL_VERSION");
  return n === 0 ? 0 : dg(n);
});
L.registerFlag("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_RELIABLE", () => L.getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_VERSION") > 0 && !ma());
L.registerFlag("WEBGL_RENDER_FLOAT32_CAPABLE", () => hg(L.getNumber("WEBGL_VERSION")));
L.registerFlag("WEBGL_RENDER_FLOAT32_ENABLED", () => L.getBool("WEBGL_FORCE_F16_TEXTURES") ? !1 : L.getBool("WEBGL_RENDER_FLOAT32_CAPABLE"));
L.registerFlag("WEBGL_DOWNLOAD_FLOAT_ENABLED", () => fg(L.getNumber("WEBGL_VERSION")));
L.registerFlag("WEBGL_FENCE_API_ENABLED", () => mg(L.getNumber("WEBGL_VERSION")));
L.registerFlag("WEBGL_SIZE_UPLOAD_UNIFORM", () => L.getBool("WEBGL_RENDER_FLOAT32_ENABLED") ? 4 : 0);
L.registerFlag("WEBGL_DELETE_TEXTURE_THRESHOLD", () => -1, (n) => {
  if (n < 0 && n !== -1)
    throw new Error(`WEBGL_DELETE_TEXTURE_THRESHOLD must be -1 (indicating never delete) or at least 0, but got ${n}.`);
});
L.registerFlag("WEBGL_FLUSH_THRESHOLD", () => ma() ? 1 : -1, (n) => {
  if (n < 0 && n !== -1)
    throw new Error(`WEBGL_FLUSH_THRESHOLD must be -1 (indicating never manual flush) or at least 0, but got ${n}.`);
});
L.registerFlag("CPU_HANDOFF_SIZE_THRESHOLD", () => 128);
L.registerFlag("WEBGL_USE_SHAPES_UNIFORMS", () => !1);
L.registerFlag("TOPK_LAST_DIM_CPU_HANDOFF_SIZE_THRESHOLD", () => 1e5);
L.registerFlag("TOPK_K_CPU_HANDOFF_THRESHOLD", () => 128);
L.registerFlag("WEBGL_EXP_CONV", () => !1);
L.registerFlag("SOFTWARE_WEBGL_ENABLED", () => L.getBool("IS_TEST"));
L.registerFlag("WEBGL_MAX_SIZE_FOR_NARROW_TEXTURE", () => 1 / 0);
L.registerFlag("WEBGL_AUTO_SQUARIFY_NARROW_TEXTURE_SHAPE", () => !1);
L.registerFlag("WEBGL2_ISNAN_CUSTOM", () => !1);
L.registerFlag("ENGINE_COMPILE_ONLY", () => !1);
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Se() {
  let n, e, t, r, s, o, i, a, c, l;
  return E().getNumber("WEBGL_VERSION") === 2 ? (n = "#version 300 es", e = "in", t = "out", r = "in", s = "texture", o = "outputColor", i = "out vec4 outputColor;", a = E().getBool("WEBGL2_ISNAN_CUSTOM") ? `
      bool isnan_custom(float val) {
        uint floatToUint = floatBitsToUint(val);
        return (floatToUint & 0x7fffffffu) > 0x7f800000u;
      }

      bvec4 isnan_custom(vec4 val) {
        return bvec4(isnan_custom(val.x),
          isnan_custom(val.y), isnan_custom(val.z), isnan_custom(val.w));
      }

      #define isnan(value) isnan_custom(value)
    ` : "", c = "", l = `
      #define round(value) newRound(value)
      int newRound(float value) {
        return int(floor(value + 0.5));
      }

      ivec4 newRound(vec4 value) {
        return ivec4(floor(value + vec4(0.5)));
      }
    `) : (n = "", e = "attribute", t = "varying", r = "varying", s = "texture2D", o = "gl_FragColor", i = "", a = `
      #define isnan(value) isnan_custom(value)
      bool isnan_custom(float val) {
        return (val > 0. || val < 1. || val == 0.) ? false : true;
      }
      bvec4 isnan_custom(vec4 val) {
        return bvec4(isnan(val.x), isnan(val.y), isnan(val.z), isnan(val.w));
      }
    `, c = `
      uniform float INFINITY;

      bool isinf(float val) {
        return abs(val) == INFINITY;
      }
      bvec4 isinf(vec4 val) {
        return equal(abs(val), vec4(INFINITY));
      }
    `, l = `
      int round(float value) {
        return int(floor(value + 0.5));
      }

      ivec4 round(vec4 value) {
        return ivec4(floor(value + vec4(0.5)));
      }
    `), {
    version: n,
    attribute: e,
    varyingVs: t,
    varyingFs: r,
    texture2D: s,
    output: o,
    defineOutput: i,
    defineSpecialNaN: a,
    defineSpecialInf: c,
    defineRound: l
  };
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Zt(n, e, t = "index") {
  const r = me(e);
  return r.map((s, o) => {
    const i = `int ${n[o]} = ${t} / ${s}`, a = o === r.length - 1 ? `int ${n[o + 1]} = ${t} - ${n[o]} * ${s}` : `index -= ${n[o]} * ${s}`;
    return `${i}; ${a};`;
  }).join("");
}
function Ur(n, e, t = "index") {
  const r = me(e);
  return r.map((s, o) => {
    const i = `int ${n[o]} = ${t} / outShapeStrides[${o}]`, a = o === r.length - 1 ? `int ${n[o + 1]} = ${t} - ${n[o]} * outShapeStrides[${o}]` : `index -= ${n[o]} * outShapeStrides[${o}]`;
    return `${i}; ${a};`;
  }).join("");
}
function gg(n, e) {
  const t = n.length, r = n.map((o) => `${e}[${o}]`), s = new Array(t - 1);
  s[t - 2] = r[t - 1];
  for (let o = t - 3; o >= 0; --o)
    s[o] = `(${s[o + 1]} * ${r[o + 1]})`;
  return s;
}
function xg(n, e, t = "index") {
  const r = n.map((o, i) => i), s = gg(r, e);
  return s.map((o, i) => {
    const a = `int ${n[i]} = ${t} / ${s[i]}`, c = i === s.length - 1 ? `int ${n[i + 1]} = ${t} - ${n[i]} * ${s[i]}` : `index -= ${n[i]} * ${s[i]}`;
    return `${a}; ${c};`;
  }).join("");
}
function no(n) {
  const e = me(n).map((t) => t.toString());
  return `
  int getFlatIndex(ivec3 coords) {
    return coords.x * ${e[0]} + coords.y * ${e[1]} + coords.z;
  }
`;
}
function ro() {
  return `
  int getFlatIndex(ivec3 coords) {
    return coords.x * outShapeStrides[0] + coords.y * outShapeStrides[1] + coords.z;
  }
`;
}
const kc = `
  const float FLOAT_MAX = 1.70141184e38;
  const float FLOAT_MIN = 1.17549435e-38;

  lowp vec4 encode_float(highp float v) {
    if (isnan(v)) {
      return vec4(255, 255, 255, 255);
    }

    highp float av = abs(v);

    if(av < FLOAT_MIN) {
      return vec4(0.0, 0.0, 0.0, 0.0);
    } else if(v > FLOAT_MAX) {
      return vec4(0.0, 0.0, 128.0, 127.0) / 255.0;
    } else if(v < -FLOAT_MAX) {
      return vec4(0.0, 0.0,  128.0, 255.0) / 255.0;
    }

    highp vec4 c = vec4(0,0,0,0);

    highp float e = floor(log2(av));
    highp float m = exp2(fract(log2(av))) - 1.0;

    c[2] = floor(128.0 * m);
    m -= c[2] / 128.0;
    c[1] = floor(32768.0 * m);
    m -= c[1] / 32768.0;
    c[0] = floor(8388608.0 * m);

    highp float ebias = e + 127.0;
    c[3] = floor(ebias / 2.0);
    ebias -= c[3] * 2.0;
    c[2] += floor(ebias) * 128.0;

    c[3] += 128.0 * step(0.0, -v);

    return c / 255.0;
  }
`;
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const { getBroadcastDims: Ac } = Pm;
function wg(n, e, t) {
  const r = [];
  if (n.forEach((f) => {
    const m = _(f.shapeInfo.logicalShape);
    if (f.shapeInfo.isUniform ? r.push(`uniform float ${f.name}${m > 1 ? `[${m}]` : ""};`) : (r.push(`uniform sampler2D ${f.name};`), r.push(`uniform int offset${f.name};`)), t.enableShapeUniforms) {
      const { uniformShape: C } = so(t.packedInputs, f.shapeInfo.logicalShape, f.shapeInfo.texShape);
      switch (C.length) {
        case 1:
          r.push(`uniform int ${f.name}Shape;`);
          break;
        case 2:
          r.push(`uniform ivec2 ${f.name}Shape;`);
          break;
        case 3:
          r.push(`uniform ivec3 ${f.name}Shape;`);
          break;
        case 4:
          r.push(`uniform ivec4 ${f.name}Shape;`);
          break;
      }
      r.push(`uniform ivec2 ${f.name}TexShape;`);
    }
  }), t.enableShapeUniforms) {
    switch (e.logicalShape.length) {
      case 1:
        r.push("uniform int outShape;");
        break;
      case 2:
        r.push("uniform ivec2 outShape;"), r.push("uniform int outShapeStrides;");
        break;
      case 3:
        r.push("uniform ivec3 outShape;"), r.push("uniform ivec2 outShapeStrides;");
        break;
      case 4:
        r.push("uniform ivec4 outShape;"), r.push("uniform ivec3 outShapeStrides;");
        break;
    }
    r.push("uniform ivec2 outTexShape;");
  }
  t.customUniforms && t.customUniforms.forEach((f) => {
    r.push(`uniform ${f.type} ${f.name}${f.arrayIndex ? `[${f.arrayIndex}]` : ""};`);
  });
  const s = r.join(`
`), o = n.map((f) => Cg(f, e, t.packedInputs, t.enableShapeUniforms)).join(`
`), i = e.texShape, a = Se(), c = $g(a);
  let l, u, d = Sg(a);
  return e.isPacked ? (l = bg(e.logicalShape, i, t.enableShapeUniforms), u = Ig(a)) : (l = yg(e.logicalShape, i, t.enableShapeUniforms), u = vg(a)), t.packedInputs && (d += Ng), [
    d,
    c,
    u,
    s,
    l,
    o,
    t.userCode
  ].join(`
`);
}
function Tn(n, e = !1) {
  const t = n.shapeInfo.logicalShape;
  switch (t.length) {
    case 0:
      return Vg(n, e);
    case 1:
      return Gg(n, e);
    case 2:
      return Hg(n, e);
    case 3:
      return jg(n, e);
    case 4:
      return Kg(n, e);
    case 5:
      return Yg(n);
    case 6:
      return Qg(n);
    default:
      throw new Error(`${t.length}-D input sampling is not yet supported`);
  }
}
function Fc(n, e) {
  switch (n.shapeInfo.logicalShape.length) {
    case 0:
      return Ug(n);
    case 1:
      return Wg(n, e);
    case 2:
      return zg(n, e);
    case 3:
      return Xg(n, e);
    default:
      return qg(n, e);
  }
}
function Cg(n, e, t = !1, r) {
  let s = "";
  t ? s += Fc(n, r) : s += Tn(n, r);
  const o = n.shapeInfo.logicalShape, i = e.logicalShape;
  return o.length <= i.length && (t ? s += Zg(n, e) : s += Jg(n, e)), s;
}
function bg(n, e, t) {
  switch (n.length) {
    case 0:
      return Dc();
    case 1:
      return kg(n, e, t);
    case 2:
      return Lg(n, e, t);
    case 3:
      return Fg(n, e, t);
    default:
      return Og(n, e, t);
  }
}
function yg(n, e, t) {
  switch (n.length) {
    case 0:
      return Dc();
    case 1:
      return Ag(n, e, t);
    case 2:
      return Mg(n, e, t);
    case 3:
      return Dg(n, e, t);
    case 4:
      return Pg(n, e, t);
    case 5:
      return _g(n, e);
    case 6:
      return Bg(n, e);
    default:
      throw new Error(`${n.length}-D output sampling is not yet supported`);
  }
}
function $g(n) {
  return `
    float sampleTexture(sampler2D textureSampler, vec2 uv) {
      return ${n.texture2D}(textureSampler, uv).r;
    }
  `;
}
function vg(n) {
  return `
    void setOutput(float val) {
      ${n.output} = vec4(val, 0, 0, 0);
    }
  `;
}
function Ig(n) {
  return `
    void setOutput(vec4 val) {
      ${n.output} = val;
    }
  `;
}
function Sg(n) {
  return `${n.version}
    precision highp float;
    precision highp int;
    precision highp sampler2D;
    ${n.varyingFs} vec2 resultUV;
    ${n.defineOutput}
    const vec2 halfCR = vec2(0.5, 0.5);

    struct ivec5
    {
      int x;
      int y;
      int z;
      int w;
      int u;
    };

    struct ivec6
    {
      int x;
      int y;
      int z;
      int w;
      int u;
      int v;
    };

    uniform float NAN;
    ${n.defineSpecialNaN}
    ${n.defineSpecialInf}
    ${n.defineRound}

    int imod(int x, int y) {
      return x - y * (x / y);
    }

    int idiv(int a, int b, float sign) {
      int res = a / b;
      int mod = imod(a, b);
      if (sign < 0. && mod != 0) {
        res -= 1;
      }
      return res;
    }

    //Based on the work of Dave Hoskins
    //https://www.shadertoy.com/view/4djSRW
    #define HASHSCALE1 443.8975
    float random(float seed){
      vec2 p = resultUV * seed;
      vec3 p3  = fract(vec3(p.xyx) * HASHSCALE1);
      p3 += dot(p3, p3.yzx + 19.19);
      return fract((p3.x + p3.y) * p3.z);
    }

    ${Eg}
    ${Rg}
    ${Tg}
  `;
}
const Eg = `
vec2 uvFromFlat(int texNumR, int texNumC, int index) {
  int texR = index / texNumC;
  int texC = index - texR * texNumC;
  return (vec2(texC, texR) + halfCR) / vec2(texNumC, texNumR);
}
vec2 packedUVfrom1D(int texNumR, int texNumC, int index) {
  int texelIndex = index / 2;
  int texR = texelIndex / texNumC;
  int texC = texelIndex - texR * texNumC;
  return (vec2(texC, texR) + halfCR) / vec2(texNumC, texNumR);
}
`, Rg = `
vec2 packedUVfrom2D(int texelsInLogicalRow, int texNumR,
  int texNumC, int row, int col) {
  int texelIndex = (row / 2) * texelsInLogicalRow + (col / 2);
  int texR = texelIndex / texNumC;
  int texC = texelIndex - texR * texNumC;
  return (vec2(texC, texR) + halfCR) / vec2(texNumC, texNumR);
}
`, Tg = `
vec2 packedUVfrom3D(int texNumR, int texNumC,
    int texelsInBatch, int texelsInLogicalRow, int b,
    int row, int col) {
  int index = b * texelsInBatch + (row / 2) * texelsInLogicalRow + (col / 2);
  int texR = index / texNumC;
  int texC = index - texR * texNumC;
  return (vec2(texC, texR) + halfCR) / vec2(texNumC, texNumR);
}
`, Ng = `
  float getChannel(vec4 frag, vec2 innerDims) {
    vec2 modCoord = mod(innerDims, 2.);
    return modCoord.x == 0. ?
      (modCoord.y == 0. ? frag.r : frag.g) :
      (modCoord.y == 0. ? frag.b : frag.a);
  }
  float getChannel(vec4 frag, int dim) {
    float modCoord = mod(float(dim), 2.);
    return modCoord == 0. ? frag.r : frag.g;
  }
`;
function Dc() {
  return `
    int getOutputCoords() {
      return 0;
    }
  `;
}
function kg(n, e, t) {
  const r = [Math.ceil(e[0] / 2), Math.ceil(e[1] / 2)];
  return r[0] === 1 ? t ? `
      int getOutputCoords() {
        return 2 * int(resultUV.x * ceil(float(outTexShape[1]) / 2.0));
      }
    ` : `
      int getOutputCoords() {
        return 2 * int(resultUV.x * ${r[1]}.0);
      }
    ` : r[1] === 1 ? t ? `
      int getOutputCoords() {
        return 2 * int(resultUV.y * ceil(float(outTexShape[0]) / 2.0));
      }
    ` : `
      int getOutputCoords() {
        return 2 * int(resultUV.y * ${r[0]}.0);
      }
    ` : t ? `
    int getOutputCoords() {
      ivec2 packedTexShape = ivec2(ceil(float(outTexShape[0]) / 2.0), ceil(float(outTexShape[1]) / 2.0));
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(packedTexShape[0], packedTexShape[1]));
      return 2 * (resTexRC.x * packedTexShape[1] + resTexRC.y);
    }
  ` : `
    int getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(${r[0]}, ${r[1]}));
      return 2 * (resTexRC.x * ${r[1]} + resTexRC.y);
    }
  `;
}
function Ag(n, e, t) {
  return e[0] === 1 ? t ? `
      int getOutputCoords() {
        return int(resultUV.x * float(outTexShape[1]));
      }
    ` : `
      int getOutputCoords() {
        return int(resultUV.x * ${e[1]}.0);
      }
    ` : e[1] === 1 ? t ? `
      int getOutputCoords() {
        return int(resultUV.y * float(outTexShape[0]));
      }
    ` : `
      int getOutputCoords() {
        return int(resultUV.y * ${e[0]}.0);
      }
    ` : t ? `
    int getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(outTexShape[0], outTexShape[1]));
      return resTexRC.x * outTexShape[1] + resTexRC.y;
    }
  ` : `
    int getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(${e[0]}, ${e[1]}));
      return resTexRC.x * ${e[1]} + resTexRC.y;
    }
  `;
}
function Fg(n, e, t) {
  if (t)
    return `
    ivec3 getOutputCoords() {
      ivec2 packedTexShape = ivec2(ceil(float(outTexShape[0]) / 2.0), ceil(float(outTexShape[1]) / 2.0));
      int texelsInLogicalRow = int(ceil(float(outShape[2]) / 2.0));
      int texelsInBatch = texelsInLogicalRow * int(ceil(float(outShape[1]) / 2.0));
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(packedTexShape[0], packedTexShape[1]));
      int index = resTexRC.x * packedTexShape[1] + resTexRC.y;

      int b = index / texelsInBatch;
      index -= b * texelsInBatch;

      int r = 2 * (index / texelsInLogicalRow);
      int c = imod(index, texelsInLogicalRow) * 2;

      return ivec3(b, r, c);
    }
  `;
  const r = [Math.ceil(e[0] / 2), Math.ceil(e[1] / 2)], s = Math.ceil(n[2] / 2), o = s * Math.ceil(n[1] / 2);
  return `
    ivec3 getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(${r[0]}, ${r[1]}));
      int index = resTexRC.x * ${r[1]} + resTexRC.y;

      int b = index / ${o};
      index -= b * ${o};

      int r = 2 * (index / ${s});
      int c = imod(index, ${s}) * 2;

      return ivec3(b, r, c);
    }
  `;
}
function Dg(n, e, t) {
  if (t)
    return `
  ivec3 getOutputCoords() {
    ivec2 resTexRC = ivec2(resultUV.yx *
                           vec2(outTexShape[0], outTexShape[1]));
    int index = resTexRC.x * outTexShape[1] + resTexRC.y;
    ${Ur(["r", "c", "d"], n)}
    return ivec3(r, c, d);
  }
`;
  const r = Zt(["r", "c", "d"], n);
  return `
    ivec3 getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(${e[0]}, ${e[1]}));
      int index = resTexRC.x * ${e[1]} + resTexRC.y;
      ${r}
      return ivec3(r, c, d);
    }
  `;
}
function Og(n, e, t) {
  if (t)
    return `
    ivec4 getOutputCoords() {
      ivec2 packedTexShape = ivec2(ceil(float(outTexShape[0]) / 2.0), ceil(float(outTexShape[1]) / 2.0));
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(packedTexShape[0], packedTexShape[1]));
      int index = resTexRC.x * packedTexShape[1] + resTexRC.y;

      int texelsInLogicalRow = int(ceil(float(outShape[3]) / 2.0));
      int texelsInBatch = texelsInLogicalRow * int(ceil(float(outShape[2]) / 2.0));
      int texelsInBatchN = texelsInBatch * outShape[1];

      int b2 = index / texelsInBatchN;
      index -= b2 * texelsInBatchN;

      int b = index / texelsInBatch;
      index -= b * texelsInBatch;

      int r = 2 * (index / texelsInLogicalRow);
      int c = imod(index, texelsInLogicalRow) * 2;

      return ivec4(b2, b, r, c);
    }
  `;
  const r = [Math.ceil(e[0] / 2), Math.ceil(e[1] / 2)], s = Math.ceil(n[n.length - 1] / 2), o = s * Math.ceil(n[n.length - 2] / 2);
  let i = o, a = "", c = "b, r, c";
  for (let l = 2; l < n.length - 1; l++)
    i *= n[n.length - l - 1], a = `
      int b${l} = index / ${i};
      index -= b${l} * ${i};
    ` + a, c = `b${l}, ` + c;
  return `
    ivec${n.length} getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(${r[0]}, ${r[1]}));
      int index = resTexRC.x * ${r[1]} + resTexRC.y;

      ${a}

      int b = index / ${o};
      index -= b * ${o};

      int r = 2 * (index / ${s});
      int c = imod(index, ${s}) * 2;

      return ivec${n.length}(${c});
    }
  `;
}
function Pg(n, e, t) {
  if (t)
    return `
    ivec4 getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
        vec2(outTexShape[0], outTexShape[1]));
      int index = resTexRC.x * outTexShape[1] + resTexRC.y;
      ${Ur(["r", "c", "d", "d2"], n)}
      return ivec4(r, c, d, d2);
    }
  `;
  const r = Zt(["r", "c", "d", "d2"], n);
  return `
    ivec4 getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
        vec2(${e[0]}, ${e[1]}));
      int index = resTexRC.x * ${e[1]} + resTexRC.y;
      ${r}
      return ivec4(r, c, d, d2);
    }
  `;
}
function _g(n, e) {
  const t = Zt(["r", "c", "d", "d2", "d3"], n);
  return `
    ivec5 getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx * vec2(${e[0]},
                             ${e[1]}));

      int index = resTexRC.x * ${e[1]} + resTexRC.y;

      ${t}

      ivec5 outShape = ivec5(r, c, d, d2, d3);
      return outShape;
    }
  `;
}
function Bg(n, e) {
  const t = Zt(["r", "c", "d", "d2", "d3", "d4"], n);
  return `
    ivec6 getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
        vec2(${e[0]}, ${e[1]}));
      int index = resTexRC.x * ${e[1]} + resTexRC.y;

      ${t}

      ivec6 result = ivec6(r, c, d, d2, d3, d4);
      return result;
    }
  `;
}
function Lg(n, e, t) {
  const r = [Math.ceil(e[0] / 2), Math.ceil(e[1] / 2)];
  if (ge(n, e))
    return t ? `
      ivec2 getOutputCoords() {
        ivec2 packedTexShape = ivec2(ceil(float(outTexShape[0]) / 2.0), ceil(float(outTexShape[1]) / 2.0));
        return 2 * ivec2(resultUV.yx * vec2(packedTexShape[0], packedTexShape[1]));
      }
    ` : `
      ivec2 getOutputCoords() {
        return 2 * ivec2(resultUV.yx * vec2(${r[0]}, ${r[1]}));
      }
    `;
  const s = Math.ceil(n[1] / 2);
  return t ? `
    ivec2 getOutputCoords() {
      ivec2 packedTexShape = ivec2(ceil(float(outTexShape[0]) / 2.0), ceil(float(outTexShape[1]) / 2.0));
      int texelsInLogicalRow = int(ceil(float(outShape[1]) / 2.0));
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(packedTexShape[0], packedTexShape[1]));

      int index = resTexRC.x * packedTexShape[1] + resTexRC.y;
      int r = 2 * (index / texelsInLogicalRow);
      int c = imod(index, texelsInLogicalRow) * 2;

      return ivec2(r, c);
    }
  ` : `
    ivec2 getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(${r[0]}, ${r[1]}));

      int index = resTexRC.x * ${r[1]} + resTexRC.y;
      int r = 2 * (index / ${s});
      int c = imod(index, ${s}) * 2;

      return ivec2(r, c);
    }
  `;
}
function Mg(n, e, t) {
  return ge(n, e) ? t ? `
      ivec2 getOutputCoords() {
        return ivec2(resultUV.yx * vec2(outTexShape[0], outTexShape[1]));
      }
    ` : `
      ivec2 getOutputCoords() {
        return ivec2(resultUV.yx * vec2(${e[0]}, ${e[1]}));
      }
    ` : n[1] === 1 ? t ? `
      ivec2 getOutputCoords() {
        ivec2 resTexRC = ivec2(resultUV.yx *
                               vec2(outTexShape[0], outTexShape[1]));
        int index = resTexRC.x * outTexShape[1] + resTexRC.y;
        return ivec2(index, 0);
      }
    ` : `
      ivec2 getOutputCoords() {
        ivec2 resTexRC = ivec2(resultUV.yx *
                               vec2(${e[0]}, ${e[1]}));
        int index = resTexRC.x * ${e[1]} + resTexRC.y;
        return ivec2(index, 0);
      }
    ` : n[0] === 1 ? t ? `
      ivec2 getOutputCoords() {
        ivec2 resTexRC = ivec2(resultUV.yx *
                               vec2(outTexShape[0], outTexShape[1]));
        int index = resTexRC.x * outTexShape[1] + resTexRC.y;
        return ivec2(0, index);
      }
    ` : `
      ivec2 getOutputCoords() {
        ivec2 resTexRC = ivec2(resultUV.yx *
                               vec2(${e[0]}, ${e[1]}));
        int index = resTexRC.x * ${e[1]} + resTexRC.y;
        return ivec2(0, index);
      }
    ` : t ? `
    ivec2 getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(outTexShape[0], outTexShape[1]));
      int index = resTexRC.x * outTexShape[1] + resTexRC.y;
      int r = index / outShape[1];
      int c = index - r * outShape[1];
      return ivec2(r, c);
    }
  ` : `
    ivec2 getOutputCoords() {
      ivec2 resTexRC = ivec2(resultUV.yx *
                             vec2(${e[0]}, ${e[1]}));
      int index = resTexRC.x * ${e[1]} + resTexRC.y;
      int r = index / ${n[1]};
      int c = index - r * ${n[1]};
      return ivec2(r, c);
    }
  `;
}
function Jt(n) {
  return `offset${n}`;
}
function Ug(n) {
  const e = n.name, t = "get" + e.charAt(0).toUpperCase() + e.slice(1), r = Se();
  return `
    vec4 ${t}() {
      return ${r.texture2D}(${e}, halfCR);
    }
  `;
}
function Vg(n, e) {
  const t = n.name, r = "get" + t.charAt(0).toUpperCase() + t.slice(1);
  if (n.shapeInfo.isUniform)
    return `float ${r}() {return ${t};}`;
  const [s, o] = n.shapeInfo.texShape;
  if (s === 1 && o === 1)
    return `
      float ${r}() {
        return sampleTexture(${t}, halfCR);
      }
    `;
  const i = Jt(t);
  if (e)
    return `
    float ${r}() {
      vec2 uv = uvFromFlat(${t}TexShape[0], ${t}TexShape[1], ${i});
      return sampleTexture(${t}, uv);
    }
  `;
  const [a, c] = n.shapeInfo.texShape;
  return `
    float ${r}() {
      vec2 uv = uvFromFlat(${a}, ${c}, ${i});
      return sampleTexture(${t}, uv);
    }
  `;
}
function Wg(n, e) {
  const t = n.name, r = "get" + t.charAt(0).toUpperCase() + t.slice(1), s = n.shapeInfo.texShape, o = Se();
  if (e)
    return `
    vec4 ${r}(int index) {
      ivec2 packedTexShape = ivec2(ceil(float(${t}TexShape[0]) / 2.0), ceil(float(${t}TexShape[1]) / 2.0));
      vec2 uv = packedUVfrom1D(
        packedTexShape[0], packedTexShape[1], index);
      return ${o.texture2D}(${t}, uv);
    }
  `;
  const i = [Math.ceil(s[0] / 2), Math.ceil(s[1] / 2)];
  return `
    vec4 ${r}(int index) {
      vec2 uv = packedUVfrom1D(
        ${i[0]}, ${i[1]}, index);
      return ${o.texture2D}(${t}, uv);
    }
  `;
}
function Gg(n, e) {
  const t = n.name, r = "get" + t.charAt(0).toUpperCase() + t.slice(1);
  if (n.shapeInfo.isUniform)
    return `
      float ${r}(int index) {
        ${Nn(n)}
      }
    `;
  const s = n.shapeInfo.texShape, o = s[0], i = s[1];
  if (i === 1 && o === 1)
    return `
      float ${r}(int index) {
        return sampleTexture(${t}, halfCR);
      }
    `;
  const a = Jt(t);
  return i === 1 ? e ? `
      float ${r}(int index) {
        vec2 uv = vec2(0.5, (float(index + ${a}) + 0.5) / float(${t}TexShape[0]));
        return sampleTexture(${t}, uv);
      }
    ` : `
      float ${r}(int index) {
        vec2 uv = vec2(0.5, (float(index + ${a}) + 0.5) / ${o}.0);
        return sampleTexture(${t}, uv);
      }
    ` : o === 1 ? e ? `
      float ${r}(int index) {
        vec2 uv = vec2((float(index + ${a}) + 0.5) / float(${t}TexShape[1]), 0.5);
        return sampleTexture(${t}, uv);
      }
    ` : `
      float ${r}(int index) {
        vec2 uv = vec2((float(index + ${a}) + 0.5) / ${i}.0, 0.5);
        return sampleTexture(${t}, uv);
      }
    ` : e ? `
    float ${r}(int index) {
      vec2 uv = uvFromFlat(${t}TexShape[0], ${t}TexShape[1], index + ${a});
      return sampleTexture(${t}, uv);
    }
  ` : `
    float ${r}(int index) {
      vec2 uv = uvFromFlat(${o}, ${i}, index + ${a});
      return sampleTexture(${t}, uv);
    }
  `;
}
function zg(n, e) {
  const t = n.shapeInfo.logicalShape, r = n.name, s = "get" + r.charAt(0).toUpperCase() + r.slice(1), o = n.shapeInfo.texShape, i = o[0], a = o[1], c = Se();
  if (o != null && ge(t, o))
    return e ? `
      vec4 ${s}(int row, int col) {
        vec2 uv = (vec2(col, row) + halfCR) / vec2(${r}TexShape[1], ${r}TexShape[0]);

        return ${c.texture2D}(${r}, uv);
      }
    ` : `
      vec4 ${s}(int row, int col) {
        vec2 uv = (vec2(col, row) + halfCR) / vec2(${a}.0, ${i}.0);

        return ${c.texture2D}(${r}, uv);
      }
    `;
  if (e)
    return `
    vec4 ${s}(int row, int col) {
      ivec2 packedTexShape = ivec2(ceil(float(${r}TexShape[0]) / 2.0), ceil(float(${r}TexShape[1]) / 2.0));
      int valuesPerRow = int(ceil(float(${r}Shape[1]) / 2.0));
      vec2 uv = packedUVfrom2D(valuesPerRow, packedTexShape[0], packedTexShape[1], row, col);
      return ${c.texture2D}(${r}, uv);
    }
  `;
  const l = [Math.ceil(o[0] / 2), Math.ceil(o[1] / 2)], u = Math.ceil(t[1] / 2);
  return `
    vec4 ${s}(int row, int col) {
      vec2 uv = packedUVfrom2D(${u}, ${l[0]}, ${l[1]}, row, col);
      return ${c.texture2D}(${r}, uv);
    }
  `;
}
function Hg(n, e) {
  const t = n.shapeInfo.logicalShape, r = n.name, s = "get" + r.charAt(0).toUpperCase() + r.slice(1), o = n.shapeInfo.texShape;
  if (o != null && ge(t, o)) {
    if (e)
      return `
      float ${s}(int row, int col) {
        vec2 uv = (vec2(col, row) + halfCR) / vec2(${r}TexShape[1], ${r}TexShape[0]);
        return sampleTexture(${r}, uv);
      }
    `;
    const h = o[0], f = o[1];
    return `
    float ${s}(int row, int col) {
      vec2 uv = (vec2(col, row) + halfCR) / vec2(${f}.0, ${h}.0);
      return sampleTexture(${r}, uv);
    }
  `;
  }
  const { newShape: i, keptDims: a } = jt(t), c = i;
  if (c.length < t.length) {
    const h = kn(n, c), f = ["row", "col"];
    return `
      ${Tn(h, e)}
      float ${s}(int row, int col) {
        return ${s}(${An(f, a)});
      }
    `;
  }
  if (n.shapeInfo.isUniform)
    return `
      float ${s}(int row, int col) {
        int index = round(dot(vec2(row, col), vec2(${t[1]}, 1)));
        ${Nn(n)}
      }
    `;
  const l = o[0], u = o[1], d = Jt(r);
  return u === 1 ? e ? `
      float ${s}(int row, int col) {
        float index = dot(vec3(row, col, ${d}), vec3(${r}Shape[1], 1, 1));
        vec2 uv = vec2(0.5, (index + 0.5) / float(${r}TexShape[0]));
        return sampleTexture(${r}, uv);
      }
    ` : `
    float ${s}(int row, int col) {
      float index = dot(vec3(row, col, ${d}), vec3(${t[1]}, 1, 1));
      vec2 uv = vec2(0.5, (index + 0.5) / ${l}.0);
      return sampleTexture(${r}, uv);
    }
  ` : l === 1 ? e ? `
      float ${s}(int row, int col) {
        float index = dot(vec3(row, col, ${d}), vec3(${r}Shape[1], 1, 1));
        vec2 uv = vec2((index + 0.5) / float(${r}TexShape[1]), 0.5);
        return sampleTexture(${r}, uv);
      }
    ` : `
    float ${s}(int row, int col) {
      float index = dot(vec3(row, col, ${d}), vec3(${t[1]}, 1, 1));
      vec2 uv = vec2((index + 0.5) / ${u}.0, 0.5);
      return sampleTexture(${r}, uv);
    }
  ` : e ? `
      float ${s}(int row, int col) {
        // Explicitly use integer operations as dot() only works on floats.
        int index = row * ${r}Shape[1] + col + ${d};
        vec2 uv = uvFromFlat(${r}TexShape[0], ${r}TexShape[1], index);
        return sampleTexture(${r}, uv);
      }
    ` : `
  float ${s}(int row, int col) {
    // Explicitly use integer operations as dot() only works on floats.
    int index = row * ${t[1]} + col + ${d};
    vec2 uv = uvFromFlat(${l}, ${u}, index);
    return sampleTexture(${r}, uv);
  }
`;
}
function Xg(n, e) {
  const t = n.shapeInfo.logicalShape, r = n.name, s = "get" + r.charAt(0).toUpperCase() + r.slice(1), o = n.shapeInfo.texShape, i = [Math.ceil(o[0] / 2), Math.ceil(o[1] / 2)];
  if (t[0] === 1) {
    const h = t.slice(1), f = [1, 2], m = kn(n, h), C = ["b", "row", "col"];
    return `
        ${Fc(m, e)}
        vec4 ${s}(int b, int row, int col) {
          return ${s}(${An(C, f)});
        }
      `;
  }
  const a = Se();
  if (e)
    return `
    vec4 ${s}(int b, int row, int col) {
      ivec2 packedTexShape = ivec2(ceil(float(${r}TexShape[0]) / 2.0), ceil(float(${r}TexShape[1]) / 2.0));
      int valuesPerRow = int(ceil(float(${r}Shape[2]) / 2.0));
      int texelsInBatch = valuesPerRow * int(ceil(float(${r}Shape[1]) / 2.0));
      vec2 uv = packedUVfrom3D(
        packedTexShape[0], packedTexShape[1], texelsInBatch, valuesPerRow, b, row, col);
      return ${a.texture2D}(${r}, uv);
    }
  `;
  const c = i[0], l = i[1], u = Math.ceil(t[2] / 2), d = u * Math.ceil(t[1] / 2);
  return `
    vec4 ${s}(int b, int row, int col) {
      vec2 uv = packedUVfrom3D(
        ${c}, ${l}, ${d}, ${u}, b, row, col);
      return ${a.texture2D}(${r}, uv);
    }
  `;
}
function jg(n, e) {
  const t = n.shapeInfo.logicalShape, r = n.name, s = "get" + r.charAt(0).toUpperCase() + r.slice(1), o = t[1] * t[2], i = t[2], { newShape: a, keptDims: c } = jt(t), l = a;
  if (l.length < t.length) {
    const C = kn(n, l), w = ["row", "col", "depth"];
    return `
        ${Tn(C, e)}
        float ${s}(int row, int col, int depth) {
          return ${s}(${An(w, c)});
        }
      `;
  }
  if (n.shapeInfo.isUniform)
    return `
      float ${s}(int row, int col, int depth) {
        int index = round(dot(vec3(row, col, depth),
                          vec3(${o}, ${i}, 1)));
        ${Nn(n)}
      }
    `;
  const u = n.shapeInfo.texShape, d = u[0], h = u[1], f = n.shapeInfo.flatOffset;
  if (h === o && f == null)
    return e ? `
      float ${s}(int row, int col, int depth) {
        int stride1 = ${r}Shape[2];
        float texR = float(row);
        float texC = dot(vec2(col, depth), vec2(stride1, 1));
        vec2 uv = (vec2(texC, texR) + halfCR) /
                   vec2(${r}TexShape[1], ${r}TexShape[0]);
        return sampleTexture(${r}, uv);
      }
    ` : `
        float ${s}(int row, int col, int depth) {
          float texR = float(row);
          float texC = dot(vec2(col, depth), vec2(${i}, 1));
          vec2 uv = (vec2(texC, texR) + halfCR) /
                     vec2(${h}.0, ${d}.0);
          return sampleTexture(${r}, uv);
        }
      `;
  if (h === i && f == null)
    return e ? `
      float ${s}(int row, int col, int depth) {
        float texR = dot(vec2(row, col), vec2(${r}Shape[1], 1));
        float texC = float(depth);
        vec2 uv = (vec2(texC, texR) + halfCR) / vec2(${r}TexShape[1], ${r}TexShape[0]);
        return sampleTexture(${r}, uv);
      }
    ` : `
    float ${s}(int row, int col, int depth) {
      float texR = dot(vec2(row, col), vec2(${t[1]}, 1));
      float texC = float(depth);
      vec2 uv = (vec2(texC, texR) + halfCR) / vec2(${h}.0, ${d}.0);
      return sampleTexture(${r}, uv);
    }
  `;
  const m = Jt(r);
  return e ? `
    float ${s}(int row, int col, int depth) {
      // Explicitly use integer operations as dot() only works on floats.
      int stride0 = ${r}Shape[1] * ${r}Shape[2];
      int stride1 = ${r}Shape[2];
      int index = row * stride0 + col * stride1 + depth + ${m};
      vec2 uv = uvFromFlat(${r}TexShape[0], ${r}TexShape[1], index);
      return sampleTexture(${r}, uv);
    }
    ` : `
      float ${s}(int row, int col, int depth) {
        // Explicitly use integer operations as dot() only works on floats.
        int index = row * ${o} + col * ${i} + depth + ${m};
        vec2 uv = uvFromFlat(${d}, ${h}, index);
        return sampleTexture(${r}, uv);
      }
  `;
}
function qg(n, e) {
  const t = n.name, r = "get" + t.charAt(0).toUpperCase() + t.slice(1), s = Se();
  if (e)
    return `
    vec4 ${r}(int b2, int b, int row, int col) {
      int valuesPerRow = int(ceil(float(${t}Shape[3]) / 2.0));
      int texelsInBatch = valuesPerRow * int(ceil(float(${t}Shape[2]) / 2.0));
      int index = b * texelsInBatch + (row / 2) * valuesPerRow + (col / 2);
      texelsInBatch *= ${t}Shape[1];
      index = b2 * texelsInBatch + index;
      ivec2 packedTexShape = ivec2(ceil(float(${t}TexShape[0]) / 2.0), ceil(float(${t}TexShape[1]) / 2.0));
      int texR = index / packedTexShape[1];
      int texC = index - texR * packedTexShape[1];
      vec2 uv = (vec2(texC, texR) + halfCR) / vec2(packedTexShape[1], packedTexShape[0]); return ${s.texture2D}(${t}, uv);
    }
  `;
  const o = n.shapeInfo.logicalShape, i = o.length, a = n.shapeInfo.texShape, c = [Math.ceil(a[0] / 2), Math.ceil(a[1] / 2)], l = c[0], u = c[1], d = Math.ceil(o[i - 1] / 2);
  let h = d * Math.ceil(o[i - 2] / 2), f = "int b, int row, int col", m = `b * ${h} + (row / 2) * ${d} + (col / 2)`;
  for (let C = 2; C < i - 1; C++)
    f = `int b${C}, ` + f, h *= o[i - C - 1], m = `b${C} * ${h} + ` + m;
  return `
    vec4 ${r}(${f}) {
      int index = ${m};
      int texR = index / ${u};
      int texC = index - texR * ${u};
      vec2 uv = (vec2(texC, texR) + halfCR) / vec2(${u}, ${l});
      return ${s.texture2D}(${t}, uv);
    }
  `;
}
function Kg(n, e) {
  const t = n.shapeInfo.logicalShape, r = n.name, s = "get" + r.charAt(0).toUpperCase() + r.slice(1), o = t[3], i = t[2] * o, a = t[1] * i, { newShape: c, keptDims: l } = jt(t);
  if (c.length < t.length) {
    const y = kn(n, c), v = ["row", "col", "depth", "depth2"];
    return `
      ${Tn(y, e)}
      float ${s}(int row, int col, int depth, int depth2) {
        return ${s}(${An(v, l)});
      }
    `;
  }
  if (n.shapeInfo.isUniform)
    return `
      float ${s}(int row, int col, int depth, int depth2) {
        int index = round(dot(vec4(row, col, depth, depth2),
                          vec4(${a}, ${i}, ${o}, 1)));
        ${Nn(n)}
      }
    `;
  const u = n.shapeInfo.flatOffset, d = n.shapeInfo.texShape, h = d[0], f = d[1], m = `int stride2 = ${r}Shape[3];`, C = `int stride1 = ${r}Shape[2] * stride2;`, w = `int stride0 = ${r}Shape[1] * stride1;`;
  if (f === a && u == null)
    return e ? `
      float ${s}(int row, int col, int depth, int depth2) {
        ${m}
        ${C}
        float texR = float(row);
        float texC =
            dot(vec3(col, depth, depth2),
                vec3(stride1, stride2, 1));
        vec2 uv = (vec2(texC, texR) + halfCR) /
                   vec2(${r}TexShape[1], ${r}TexShape[0]);
        return sampleTexture(${r}, uv);
      }
    ` : `
      float ${s}(int row, int col, int depth, int depth2) {
        float texR = float(row);
        float texC =
            dot(vec3(col, depth, depth2),
                vec3(${i}, ${o}, 1));
        vec2 uv = (vec2(texC, texR) + halfCR) /
                   vec2(${f}.0, ${h}.0);
        return sampleTexture(${r}, uv);
      }
    `;
  if (f === o && u == null)
    return e ? `
      float ${s}(int row, int col, int depth, int depth2) {
        float texR = dot(vec3(row, col, depth),
                         vec3(${r}Shape[1] * ${r}Shape[2], ${r}Shape[2], 1));
        float texC = float(depth2);
        vec2 uv = (vec2(texC, texR) + halfCR) /
                  vec2(${r}TexShape[1], ${r}TexShape[0]);
        return sampleTexture(${r}, uv);
      }
    ` : `
      float ${s}(int row, int col, int depth, int depth2) {
        float texR = dot(vec3(row, col, depth),
                         vec3(${t[1] * t[2]}, ${t[2]}, 1));
        float texC = float(depth2);
        vec2 uv = (vec2(texC, texR) + halfCR) /
                  vec2(${f}.0, ${h}.0);
        return sampleTexture(${r}, uv);
      }
    `;
  const x = Jt(r);
  return e ? `
    float ${s}(int row, int col, int depth, int depth2) {
      // Explicitly use integer operations as dot() only works on floats.
      ${m}
      ${C}
      ${w}
      int index = row * stride0 + col * stride1 +
          depth * stride2 + depth2;
      vec2 uv = uvFromFlat(${r}TexShape[0], ${r}TexShape[1], index + ${x});
      return sampleTexture(${r}, uv);
    }
  ` : `
    float ${s}(int row, int col, int depth, int depth2) {
      // Explicitly use integer operations as dot() only works on floats.
      int index = row * ${a} + col * ${i} +
          depth * ${o} + depth2;
      vec2 uv = uvFromFlat(${h}, ${f}, index + ${x});
      return sampleTexture(${r}, uv);
    }
  `;
}
function Yg(n) {
  const e = n.shapeInfo.logicalShape, t = n.name, r = "get" + t.charAt(0).toUpperCase() + t.slice(1), s = e[4], o = e[3] * s, i = e[2] * o, a = e[1] * i, { newShape: c, keptDims: l } = jt(e);
  if (c.length < e.length) {
    const C = kn(n, c), w = ["row", "col", "depth", "depth2", "depth3"];
    return `
      ${Tn(C)}
      float ${r}(int row, int col, int depth, int depth2, int depth3) {
        return ${r}(${An(w, l)});
      }
    `;
  }
  if (n.shapeInfo.isUniform)
    return `
      float ${r}(int row, int col, int depth, int depth2, int depth3) {
        float index = dot(
          vec4(row, col, depth, depth2),
          vec4(${a}, ${i}, ${o}, ${s})) +
          depth3;
        ${Nn(n)}
      }
    `;
  const u = n.shapeInfo.flatOffset, d = n.shapeInfo.texShape, h = d[0], f = d[1];
  if (f === a && u == null)
    return `
      float ${r}(int row, int col, int depth, int depth2, int depth3) {
        int texR = row;
        float texC = dot(vec4(col, depth, depth2, depth3),
                         vec4(${i}, ${o}, ${s}, 1));
        vec2 uv = (vec2(texC, texR) + halfCR) /
                   vec2(${f}.0, ${h}.0);
        return sampleTexture(${t}, uv);
      }
    `;
  if (f === s && u == null)
    return `
      float ${r}(int row, int col, int depth, int depth2, int depth3) {
        float texR = dot(
          vec4(row, col, depth, depth2),
          vec4(${e[1] * e[2] * e[3]},
               ${e[2] * e[3]}, ${e[3]}, 1));
        int texC = depth3;
        vec2 uv = (vec2(texC, texR) + halfCR) /
                  vec2(${f}.0, ${h}.0);
        return sampleTexture(${t}, uv);
      }
    `;
  const m = Jt(t);
  return `
    float ${r}(int row, int col, int depth, int depth2, int depth3) {
      // Explicitly use integer operations as dot() only works on floats.
      int index = row * ${a} + col * ${i} + depth * ${o} +
          depth2 * ${s} + depth3 + ${m};
      vec2 uv = uvFromFlat(${h}, ${f}, index);
      return sampleTexture(${t}, uv);
    }
  `;
}
function Qg(n) {
  const e = n.shapeInfo.logicalShape, t = n.name, r = "get" + t.charAt(0).toUpperCase() + t.slice(1), { newShape: s, keptDims: o } = jt(e);
  if (s.length < e.length) {
    const w = kn(n, s), x = ["row", "col", "depth", "depth2", "depth3", "depth4"];
    return `
      ${Tn(w)}
      float ${r}(int row, int col, int depth,
                    int depth2, int depth3, int depth4) {
        return ${r}(${An(x, o)});
      }
    `;
  }
  const i = e[5], a = e[4] * i, c = e[3] * a, l = e[2] * c, u = e[1] * l;
  if (n.shapeInfo.isUniform)
    return `
      float ${r}(int row, int col, int depth,
                  int depth2, int depth3, int depth4) {
        int index = round(dot(
          vec4(row, col, depth, depth2),
          vec4(${u}, ${l}, ${c}, ${a})) +
          dot(
            vec2(depth3, depth4),
            vec2(${i}, 1)));
        ${Nn(n)}
      }
    `;
  const d = n.shapeInfo.flatOffset, h = n.shapeInfo.texShape, f = h[0], m = h[1];
  if (m === u && d == null)
    return `
      float ${r}(int row, int col, int depth,
                    int depth2, int depth3, int depth4) {
        int texR = row;
        float texC = dot(vec4(col, depth, depth2, depth3),
          vec4(${l}, ${c}, ${a}, ${i})) +
               float(depth4);
        vec2 uv = (vec2(texC, texR) + halfCR) /
                   vec2(${m}.0, ${f}.0);
        return sampleTexture(${t}, uv);
      }
    `;
  if (m === i && d == null)
    return `
      float ${r}(int row, int col, int depth,
                    int depth2, int depth3, int depth4) {
        float texR = dot(vec4(row, col, depth, depth2),
          vec4(${e[1] * e[2] * e[3] * e[4]},
               ${e[2] * e[3] * e[4]},
               ${e[3] * e[4]},
               ${e[4]})) + float(depth3);
        int texC = depth4;
        vec2 uv = (vec2(texC, texR) + halfCR) /
                  vec2(${m}.0, ${f}.0);
        return sampleTexture(${t}, uv);
      }
    `;
  const C = Jt(t);
  return `
    float ${r}(int row, int col, int depth,
                  int depth2, int depth3, int depth4) {
      // Explicitly use integer operations as dot() only works on floats.
      int index = row * ${u} + col * ${l} + depth * ${c} +
          depth2 * ${a} + depth3 * ${i} + depth4 + ${C};
      vec2 uv = uvFromFlat(${f}, ${m}, index);
      return sampleTexture(${t}, uv);
    }
  `;
}
function Nn(n) {
  const e = n.name, t = _(n.shapeInfo.logicalShape);
  return t < 2 ? `return ${e};` : `
    for (int i = 0; i < ${t}; i++) {
      if (i == index) {
        return ${e}[i];
      }
    }
  `;
}
function Zg(n, e) {
  const t = n.name, r = t.charAt(0).toUpperCase() + t.slice(1), s = "get" + r + "AtOutCoords", o = n.shapeInfo.logicalShape.length, i = e.logicalShape.length, a = Ac(n.shapeInfo.logicalShape, e.logicalShape), c = K(i), l = i - o;
  let u;
  const d = ["x", "y", "z", "w", "u", "v"];
  o === 0 ? u = "" : i < 2 && a.length >= 1 ? u = "coords = 0;" : u = a.map((y) => `coords.${d[y + l]} = 0;`).join(`
`);
  let h = "";
  i < 2 && o > 0 ? h = "coords" : h = n.shapeInfo.logicalShape.map((y, v) => `coords.${d[v + l]}`).join(", ");
  let f = "return outputValue;";
  const C = _(n.shapeInfo.logicalShape) === 1, x = _(e.logicalShape) === 1;
  if (o === 1 && !C && !x)
    f = `
      return vec4(outputValue.xy, outputValue.xy);
    `;
  else if (C && !x)
    i === 1 ? f = `
        return vec4(outputValue.x, outputValue.x, 0., 0.);
      ` : f = `
        return vec4(outputValue.x);
      `;
  else if (a.length) {
    const y = o - 2, v = o - 1;
    a.indexOf(y) > -1 && a.indexOf(v) > -1 ? f = "return vec4(outputValue.x);" : a.indexOf(y) > -1 ? f = "return vec4(outputValue.x, outputValue.y, outputValue.x, outputValue.y);" : a.indexOf(v) > -1 && (f = "return vec4(outputValue.xx, outputValue.zz);");
  }
  return `
    vec4 ${s}() {
      ${c} coords = getOutputCoords();
      ${u}
      vec4 outputValue = get${r}(${h});
      ${f}
    }
  `;
}
function Jg(n, e) {
  const t = n.name, r = t.charAt(0).toUpperCase() + t.slice(1), s = "get" + r + "AtOutCoords", o = e.texShape, i = n.shapeInfo.texShape, a = n.shapeInfo.logicalShape.length, c = e.logicalShape.length;
  if (!n.shapeInfo.isUniform && a === c && n.shapeInfo.flatOffset == null && ge(i, o))
    return `
      float ${s}() {
        return sampleTexture(${t}, resultUV);
      }
    `;
  const l = K(c), u = Ac(n.shapeInfo.logicalShape, e.logicalShape), d = c - a;
  let h;
  const f = ["x", "y", "z", "w", "u", "v"];
  a === 0 ? h = "" : c < 2 && u.length >= 1 ? h = "coords = 0;" : h = u.map((C) => `coords.${f[C + d]} = 0;`).join(`
`);
  let m = "";
  return c < 2 && a > 0 ? m = "coords" : m = n.shapeInfo.logicalShape.map((C, w) => `coords.${f[w + d]}`).join(", "), `
    float ${s}() {
      ${l} coords = getOutputCoords();
      ${h}
      return get${r}(${m});
    }
  `;
}
function K(n) {
  if (n <= 1)
    return "int";
  if (n === 2)
    return "ivec2";
  if (n === 3)
    return "ivec3";
  if (n === 4)
    return "ivec4";
  if (n === 5)
    return "ivec5";
  if (n === 6)
    return "ivec6";
  throw Error(`GPU for rank ${n} is not yet supported`);
}
function so(n, e, t) {
  const { newShape: r, keptDims: s } = jt(e), o = e.length, i = n && o === 3 && e[0] === 1, a = i ? e.slice(1) : r, c = !n && o > 1 && !ge(e, t) && r.length < o || i;
  return { useSqueezeShape: c, uniformShape: c ? a : e, keptDims: s };
}
function kn(n, e) {
  const t = JSON.parse(JSON.stringify(n));
  return t.shapeInfo.logicalShape = e, t;
}
function An(n, e) {
  return e.map((t) => n[t]).join(", ");
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function ex(n, e, t, r) {
  const s = t.map((u, d) => {
    const h = {
      logicalShape: u.shape,
      texShape: u.isUniform ? null : u.texData.texShape,
      isUniform: u.isUniform,
      isPacked: u.isUniform ? !1 : u.texData.isPacked,
      flatOffset: null
    };
    return u.texData != null && u.texData.slice != null && u.texData.slice.flatOffset > 0 && (h.flatOffset = u.texData.slice.flatOffset), { name: e.variableNames[d], shapeInfo: h };
  }), o = s.map((u) => u.shapeInfo), i = {
    logicalShape: r.shape,
    texShape: r.texData.texShape,
    isUniform: !1,
    isPacked: r.texData.isPacked,
    flatOffset: null
  }, a = wg(s, i, e), c = jm(n.gl, a), l = n.createProgram(c);
  return E().get("ENGINE_COMPILE_ONLY") ? {
    program: e,
    fragmentShader: c,
    source: a,
    webGLProgram: l,
    inShapeInfos: o,
    outShapeInfo: i,
    variablesLocations: null,
    customUniformLocations: null,
    infLoc: null,
    nanLoc: null,
    outShapeLocation: null,
    outShapeStridesLocation: null,
    outTexShapeLocation: null
  } : (n.buildVao(l), Object.assign({
    program: e,
    fragmentShader: c,
    source: a,
    webGLProgram: l,
    inShapeInfos: o,
    outShapeInfo: i
  }, Oc(n, e, l)));
}
function Oc(n, e, t) {
  const r = [], s = [];
  let o, i, a, c = null, l = null;
  l = n.getUniformLocation(t, "NAN", !1), E().getNumber("WEBGL_VERSION") === 1 && (c = n.getUniformLocation(t, "INFINITY", !1));
  const u = !1;
  for (const d of e.variableNames) {
    const h = {
      name: d,
      uniform: n.getUniformLocation(t, d, u),
      offset: n.getUniformLocation(t, `offset${d}`, u)
    };
    e.enableShapeUniforms && (h.shape = n.getUniformLocation(t, `${d}Shape`, u), h.texShape = n.getUniformLocation(t, `${d}TexShape`, u)), r.push(h);
  }
  if (e.enableShapeUniforms && (o = n.getUniformLocation(t, "outShape", u), a = n.getUniformLocation(t, "outShapeStrides", u), i = n.getUniformLocation(t, "outTexShape", u)), e.customUniforms)
    for (const d of e.customUniforms)
      s.push(n.getUniformLocation(t, d.name, u));
  return {
    variablesLocations: r,
    customUniformLocations: s,
    infLoc: c,
    nanLoc: l,
    outShapeLocation: o,
    outShapeStridesLocation: a,
    outTexShapeLocation: i
  };
}
function qo(n, e) {
  if (n.length !== e.length)
    throw Error(`Binary was compiled with ${n.length} inputs, but was executed with ${e.length} inputs`);
  n.forEach((t, r) => {
    const s = t.logicalShape, o = e[r], i = o.shape;
    if (!ge(s, i))
      throw Error(`Binary was compiled with different shapes than the current args. Shapes ${s} and ${i} must match`);
    if (t.isUniform && o.isUniform)
      return;
    const a = t.texShape, c = o.isUniform ? null : o.texData.texShape;
    if (!ge(a, c))
      throw Error(`Binary was compiled with different texture shapes than the current args. Shape ${a} and ${c} must match`);
  });
}
function tx(n, e, t, r, s) {
  e.program.enableShapeUniforms || (qo(e.inShapeInfos, t), qo([e.outShapeInfo], [r]));
  const o = r.texData.texture, i = r.texData.texShape;
  r.texData.isPacked ? n.setOutputPackedMatrixTexture(o.texture, i[0], i[1]) : n.setOutputMatrixTexture(o.texture, i[0], i[1]), n.setProgram(e.webGLProgram), n.bindVertexArray(e.webGLProgram.vao), E().getNumber("WEBGL_VERSION") === 1 && e.infLoc !== null && n.gl.uniform1f(e.infLoc, 1 / 0), e.nanLoc !== null && n.gl.uniform1f(e.nanLoc, NaN);
  for (let c = 0; c < t.length; ++c) {
    const l = t[c], { uniform: u, offset: d, shape: h, texShape: f } = e.variablesLocations[c];
    if (h) {
      const { uniformShape: m } = so(e.program.packedInputs, l.shape, l.texData.texShape);
      switch (m.length) {
        case 1:
          n.gl.uniform1iv(h, new Int32Array(m));
          break;
        case 2:
          n.gl.uniform2iv(h, new Int32Array(m));
          break;
        case 3:
          n.gl.uniform3iv(h, new Int32Array(m));
          break;
        case 4:
          n.gl.uniform4iv(h, new Int32Array(m));
          break;
      }
    }
    if (f && n.gl.uniform2i(f, l.texData.texShape[0], l.texData.texShape[1]), u != null) {
      if (l.isUniform) {
        if (_(l.shape) < 2)
          n.gl.uniform1f(u, l.uniformValues[0]);
        else {
          let m = l.uniformValues;
          m instanceof Float32Array || (m = new Float32Array(m)), n.gl.uniform1fv(u, m);
        }
        continue;
      }
      l.texData.slice != null && d != null && n.gl.uniform1i(d, l.texData.slice.flatOffset), n.setInputMatrixTexture(l.texData.texture.texture, u, c);
    }
  }
  const a = e.outShapeLocation;
  if (a)
    switch (r.shape.length) {
      case 1:
        n.gl.uniform1iv(a, new Int32Array(r.shape));
        break;
      case 2:
        n.gl.uniform2iv(a, new Int32Array(r.shape));
        break;
      case 3:
        n.gl.uniform3iv(a, new Int32Array(r.shape));
        break;
      case 4:
        n.gl.uniform4iv(a, new Int32Array(r.shape));
        break;
    }
  if (e.outShapeStridesLocation) {
    const c = me(r.shape);
    switch (r.shape.length) {
      case 2:
        n.gl.uniform1iv(e.outShapeStridesLocation, new Int32Array(c));
        break;
      case 3:
        n.gl.uniform2iv(e.outShapeStridesLocation, new Int32Array(c));
        break;
      case 4:
        n.gl.uniform3iv(e.outShapeStridesLocation, new Int32Array(c));
        break;
    }
  }
  if (e.outTexShapeLocation && n.gl.uniform2i(e.outTexShapeLocation, r.texData.texShape[0], r.texData.texShape[1]), e.program.customUniforms && s)
    for (let c = 0; c < e.program.customUniforms.length; ++c) {
      const l = e.program.customUniforms[c], u = e.customUniformLocations[c], d = s[c];
      if (l.type === "float")
        n.gl.uniform1fv(u, d);
      else if (l.type === "vec2")
        n.gl.uniform2fv(u, d);
      else if (l.type === "vec3")
        n.gl.uniform3fv(u, d);
      else if (l.type === "vec4")
        n.gl.uniform4fv(u, d);
      else if (l.type === "int")
        n.gl.uniform1iv(u, d);
      else if (l.type === "ivec2")
        n.gl.uniform2iv(u, d);
      else if (l.type === "ivec3")
        n.gl.uniform3iv(u, d);
      else if (l.type === "ivec4")
        n.gl.uniform4iv(u, d);
      else
        throw Error(`uniform type ${l.type} is not supported yet.`);
    }
  n.executeProgram();
}
function nx(n, e, t) {
  let r = "";
  e.concat(t).forEach((i) => {
    const a = i.texData != null && i.texData.slice != null && i.texData.slice.flatOffset > 0;
    if (n.enableShapeUniforms && !i.isUniform) {
      const c = i.texData.texShape, { useSqueezeShape: l, uniformShape: u, keptDims: d } = so(n.packedInputs, i.shape, c);
      let h = "", f = "", m = "";
      if (u.length === 1 && n.packedInputs) {
        const T = [Math.ceil(c[0] / 2), Math.ceil(c[1] / 2)];
        h = `${T[0] > 1}_${T[1] > 1}`;
      } else if (u.length === 2 && !n.packedInputs)
        f = `${u[0] > 1}_${u[1] > 1}`;
      else if (u.length > 2 && !n.packedInputs) {
        const T = me(u);
        m = `${T[0] === c[1]}_${T[T.length - 1] === c[1]}`;
      }
      const C = i.shape.length, w = u.length === 2 && ge(i.shape, c), x = _(i.shape) === 1, y = Er(i.shape, t.shape), v = !n.packedInputs && C === t.shape.length && ge(c, t.texData.texShape), I = n.packedInputs || u.length > 2 ? "" : `${c[0] > 1}_${c[1] > 1}`;
      r += `${C}_${v}_${l ? d : ""}_${u.length}_${x}_${y}_${w}_${h}_${f}_${m}_${I}_${a}`;
    } else {
      const c = i.isUniform ? "uniform" : i.texData.texShape;
      r += `${i.shape}_${c}_${a}`;
    }
  });
  const s = n.userCode;
  let o = n.constructor.name;
  return o += "_" + r + "_" + s + `${E().getNumber("WEBGL_VERSION")}`, o;
}
function Ce(n) {
  return E().getBool("WEBGL_USE_SHAPES_UNIFORMS") && n <= 4;
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class rx {
  constructor(e) {
    this.variableNames = ["A"], this.packedInputs = !1, this.packedOutput = !0, this.outPackingScheme = Xn.DENSE, this.customUniforms = [{ name: "texShape", type: "ivec2" }];
    const t = Se();
    this.outputShape = e, this.enableShapeUniforms = Ce(this.outputShape.length), this.userCode = `
      ivec3 outCoordsFromFlatIndex(int index) {
        ${this.enableShapeUniforms ? Ur(["r", "c", "d"], e) : Zt(["r", "c", "d"], e)}
        return ivec3(r, c, d);
      }

      void main() {
        ivec2 resTexRC = ivec2(resultUV.yx * vec2(texShape[0], texShape[1]));
        int index = 4 * (resTexRC.x * texShape[1] + resTexRC.y);

        vec4 result = vec4(0.);

        for (int i=0; i<4; i++) {
          int flatIndex = index + i;
          ivec3 rc = outCoordsFromFlatIndex(flatIndex);
          result[i] = getA(rc.x, rc.y, rc.z);
        }

        ${t.output} = result;
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class sx {
  constructor(e) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !0, this.outPackingScheme = Xn.DENSE, this.customUniforms = [{ name: "texShape", type: "ivec2" }];
    const t = Se();
    this.outputShape = e, this.enableShapeUniforms = Ce(this.outputShape.length), this.userCode = `
      ivec3 outCoordsFromFlatIndex(int index) {
        ${this.enableShapeUniforms ? Ur(["r", "c", "d"], e) : Zt(["r", "c", "d"], e)}
        return ivec3(r, c, d);
      }

      void main() {
        ivec2 resTexRC = ivec2(resultUV.yx * vec2(texShape[0], texShape[1]));
        int index = 4 * (resTexRC.x * texShape[1] + resTexRC.y);

        vec4 result = vec4(0.);

        for (int i=0; i<4; i++) {
          int flatIndex = index + i;
          ivec3 rc = outCoordsFromFlatIndex(flatIndex);
          result[i] = getChannel(getA(rc.x, rc.y, rc.z), vec2(rc.y, rc.z));
        }

        ${t.output} = result;
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ox {
  constructor(e) {
    this.variableNames = ["A"], this.outTexUsage = Pe.DOWNLOAD;
    const t = Se();
    this.outputShape = e, this.userCode = `
      ${kc}

      void main() {
        float x = getAAtOutCoords();
        ${t.output} = encode_float(x);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ix {
  constructor(e) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !1, this.outTexUsage = Pe.DOWNLOAD;
    const t = Se();
    this.outputShape = e, this.userCode = `
      ${kc}

      void main() {
        ivec3 coords = getOutputCoords();
        float x = getChannel(getAAtOutCoords(), vec2(coords.y, coords.z));
        ${t.output} = encode_float(x);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ax = {
  R: 0,
  G: 1,
  B: 2,
  A: 3
};
class Ko {
  constructor(e, t = !1, r = "RGBA") {
    this.variableNames = ["A"], this.customUniforms = [{ name: "texShape", type: "ivec2" }];
    const s = Se();
    this.outputShape = e, this.enableShapeUniforms = Ce(this.outputShape.length);
    let o = "result";
    t && (o = "floor(result * 255. + 0.5)");
    let i = "";
    for (let a = 0; a < r.length; a++) {
      const c = r[a];
      i += `
          if(offset == ${a}) {
            result = values[${ax[c]}];
          }`;
    }
    this.userCode = `
      ${this.enableShapeUniforms ? ro() : no(e)}

      void main() {
        ivec3 coords = getOutputCoords();
        int flatIndex = getFlatIndex(coords);
        float result = 0.;
        int offset = imod(flatIndex, ${r.length});

        flatIndex = idiv(flatIndex, ${r.length}, 1.);

        int r = flatIndex / texShape[1];
        if (r < texShape[0]) {
          int c = imod(flatIndex, texShape[1]);
          vec2 uv = (vec2(c, r) + halfCR) / vec2(texShape[1], texShape[0]);
          vec4 values = ${s.texture2D}(A, uv);
          ${i}
        }
        ${s.output} = vec4(${o}, 0., 0., 0.);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class cx {
  constructor(e, t = !1) {
    this.variableNames = ["A"], this.packedInputs = !1, this.packedOutput = !0, this.customUniforms = [{ name: "texShape", type: "ivec2" }];
    const r = Se();
    this.outputShape = e, this.enableShapeUniforms = Ce(this.outputShape.length);
    let s = "", o = "result";
    t && (o = "floor(result * 255. + 0.5)");
    for (let i = 0; i <= 1; i++)
      for (let a = 0; a <= 1; a++) {
        const c = i * 2 + a;
        s += `
          localCoords = coords;
          if(localCoords[2] + ${a} < ${this.enableShapeUniforms ? "outShape[2]" : `${e[2]}`}) {
          localCoords[2] += ${a};
          if (localCoords[1] + ${i} < ${this.enableShapeUniforms ? "outShape[1]" : `${e[1]}`}) {
            localCoords[1] += ${i};

            flatIndex = getFlatIndex(localCoords);
            offset = imod(flatIndex, 4);

            flatIndex = idiv(flatIndex, 4, 1.);

            int r = flatIndex / texShape[1];
            int c = imod(flatIndex, texShape[1]);
            vec2 uv = (vec2(c, r) + halfCR) / vec2(texShape[1], texShape[0]);
            values = ${r.texture2D}(A, uv);

            if (offset == 0) {
              result[${c}] = values[0];
            } else if (offset == 1) {
              result[${c}] = values[1];
            } else if (offset == 2) {
              result[${c}] = values[2];
            } else {
              result[${c}] = values[3];
            }
          }
        }
        `;
      }
    this.userCode = `
        ${this.enableShapeUniforms ? ro() : no(e)}

        void main() {
          ivec3 coords = getOutputCoords();

          vec4 result = vec4(0.);
          int flatIndex, r, c, offset;
          ivec3 localCoords;
          vec2 uv;
          vec4 values;

          ${s}

          ${r.output} = ${o};
        }
    `;
  }
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function lx(n) {
  const e = Se(), t = `${e.version}
    precision highp float;
    ${e.attribute} vec3 clipSpacePos;
    ${e.attribute} vec2 uv;
    ${e.varyingVs} vec2 resultUV;

    void main() {
      gl_Position = vec4(clipSpacePos, 1);
      resultUV = uv;
    }`;
  return Xm(n, t);
}
function ux(n) {
  const e = new Float32Array([-1, 1, 0, 0, 1, -1, -1, 0, 0, 0, 1, 1, 0, 1, 1, 1, -1, 0, 1, 0]);
  return Qm(n, e);
}
function dx(n) {
  const e = new Uint16Array([0, 1, 2, 2, 1, 3]);
  return Zm(n, e);
}
function nr(n, e, t, r, s, o) {
  eg(e, t);
  const i = Jm(n), a = n.TEXTURE_2D;
  return B(n, () => n.bindTexture(a, i)), B(n, () => n.texParameteri(a, n.TEXTURE_WRAP_S, n.CLAMP_TO_EDGE)), B(n, () => n.texParameteri(a, n.TEXTURE_WRAP_T, n.CLAMP_TO_EDGE)), B(n, () => n.texParameteri(a, n.TEXTURE_MIN_FILTER, n.NEAREST)), B(n, () => n.texParameteri(a, n.TEXTURE_MAG_FILTER, n.NEAREST)), E().getNumber("WEBGL_VERSION") === 1 ? B(n, () => n.texImage2D(a, 0, r, e, t, 0, s, o, null)) : B(n, () => n.texStorage2D(a, 1, r, e, t)), B(n, () => n.bindTexture(n.TEXTURE_2D, null)), { texture: i, texShape: [t, e] };
}
function Pc(n) {
  return n.internalFormatFloat;
}
function hx(n, e, t, r) {
  const [s, o] = er(e, t);
  return nr(n, s, o, Pc(r), r.textureFormatFloat, n.FLOAT);
}
function _c(n) {
  return n.internalFormatHalfFloat;
}
function fx(n, e, t, r) {
  const [s, o] = er(e, t);
  return nr(n, s, o, _c(r), r.textureFormatFloat, r.textureTypeHalfFloat);
}
function Bc(n) {
  return n.downloadTextureFormat;
}
function px(n, e, t, r) {
  const [s, o] = er(e, t);
  return nr(n, s, o, Bc(r), n.RGBA, n.UNSIGNED_BYTE);
}
function Lc(n) {
  return n.internalFormatPackedFloat;
}
function mx(n, e, t, r) {
  const [s, o] = Rn(e, t);
  return nr(n, s, o, Lc(r), n.RGBA, n.FLOAT);
}
function Mc(n) {
  return n.internalFormatPackedHalfFloat;
}
function gx(n, e, t, r) {
  const [s, o] = Rn(e, t);
  return nr(n, s, o, Mc(r), n.RGBA, r.textureTypeHalfFloat);
}
function xx(n, e, t) {
  return B(n, () => n.bindBuffer(n.ARRAY_BUFFER, t)), Ho(n, e, "clipSpacePos", t, 3, 20, 0) && Ho(n, e, "uv", t, 2, 20, 12);
}
function wx(n, e, t, r, s, o) {
  B(n, () => n.bindTexture(n.TEXTURE_2D, e));
  let i, a, c;
  s instanceof Uint8Array ? (i = new Uint8Array(t * r * 4), a = n.UNSIGNED_BYTE, c = n.RGBA) : (i = new Float32Array(t * r * 4), a = n.FLOAT, c = o.internalFormatPackedFloat), i.set(s), E().getNumber("WEBGL_VERSION") === 2 ? B(n, () => n.texSubImage2D(n.TEXTURE_2D, 0, 0, 0, t, r, n.RGBA, a, i)) : B(n, () => n.texImage2D(n.TEXTURE_2D, 0, c, t, r, 0, n.RGBA, a, i)), B(n, () => n.bindTexture(n.TEXTURE_2D, null));
}
function Cx(n, e, t) {
  B(n, () => n.bindTexture(n.TEXTURE_2D, e)), t.data instanceof Uint8Array ? E().getNumber("WEBGL_VERSION") === 2 ? B(n, () => n.texSubImage2D(n.TEXTURE_2D, 0, 0, 0, t.width, t.height, n.RGBA, n.UNSIGNED_BYTE, t.data)) : B(n, () => n.texImage2D(n.TEXTURE_2D, 0, n.RGBA, t.width, t.height, 0, n.RGBA, n.UNSIGNED_BYTE, t.data)) : E().getNumber("WEBGL_VERSION") === 2 ? B(n, () => n.texSubImage2D(n.TEXTURE_2D, 0, 0, 0, n.RGBA, n.UNSIGNED_BYTE, t)) : B(n, () => n.texImage2D(n.TEXTURE_2D, 0, n.RGBA, n.RGBA, n.UNSIGNED_BYTE, t)), B(n, () => n.bindTexture(n.TEXTURE_2D, null));
}
function bx(n, e, t, r) {
  const s = n.createBuffer();
  B(n, () => n.bindBuffer(n.PIXEL_PACK_BUFFER, s));
  const a = 4 * 4 * e * t;
  return B(n, () => n.bufferData(n.PIXEL_PACK_BUFFER, a, n.STREAM_READ)), B(n, () => n.readPixels(0, 0, t, e, n.RGBA, n.FLOAT, 0)), B(n, () => n.bindBuffer(n.PIXEL_PACK_BUFFER, null)), s;
}
function yx(n, e, t) {
  const r = n, s = new Float32Array(t);
  return r.bindBuffer(r.PIXEL_PACK_BUFFER, e), r.getBufferSubData(r.PIXEL_PACK_BUFFER, 0, s), r.bindBuffer(r.PIXEL_PACK_BUFFER, null), s;
}
function $x(n, e, t, r) {
  const [s, o] = er(e, t), i = 4, a = new Uint8Array(Mm(e * t, i));
  return B(n, () => n.readPixels(0, 0, s, o, r.downloadTextureFormat, n.UNSIGNED_BYTE, a)), new Float32Array(a.buffer);
}
function vx(n, e, t, r, s, o, i, a) {
  const c = n, l = new Float32Array(Um(o, i));
  return c.bindBuffer(c.PIXEL_PACK_BUFFER, e), c.getBufferSubData(c.PIXEL_PACK_BUFFER, 0, l), c.bindBuffer(c.PIXEL_PACK_BUFFER, null), l;
}
function Ix(n, e, t) {
  const r = new Float32Array(e * t * 4);
  return B(n, () => n.readPixels(0, 0, t, e, n.RGBA, n.FLOAT, r)), r;
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ss {
  constructor(e) {
    this.outputTexture = null, this.program = null, this.disposed = !1, this.itemsToPoll = [];
    const t = E().getNumber("WEBGL_VERSION");
    if (e != null ? (this.gl = e, _m(t, e)) : this.gl = Ze(t), e = this.gl, E().getNumber("WEBGL_VERSION") === 2) {
      const o = e;
      this.createVertexArray = () => B(o, () => o.createVertexArray()), this.bindVertexArray = (i) => B(o, () => o.bindVertexArray(i)), this.deleteVertexArray = (i) => B(o, () => o.deleteVertexArray(i)), this.getVertexArray = () => B(o, () => o.getParameter(o.VERTEX_ARRAY_BINDING));
    } else if (e != null) {
      const o = e.getExtension("OES_vertex_array_object");
      if (o == null)
        throw new Error("All WebGL1 implementations are expected to offer OES_vertex_array_object.");
      this.createVertexArray = () => B(e, () => o.createVertexArrayOES()), this.bindVertexArray = (i) => B(e, () => o.bindVertexArrayOES(i)), this.deleteVertexArray = (i) => B(e, () => o.deleteVertexArrayOES(i)), this.getVertexArray = () => B(e, () => e.getParameter(o.VERTEX_ARRAY_BINDING_OES));
    }
    let r = "WEBGL_color_buffer_float";
    const s = "EXT_color_buffer_half_float";
    if (this.parallelCompilationExtension = this.gl.getExtension("KHR_parallel_shader_compile"), E().getNumber("WEBGL_VERSION") === 1) {
      const o = "OES_texture_float", i = "OES_texture_half_float";
      if (this.textureFloatExtension = lr(this.gl, o), Ge(this.gl, i))
        this.textureHalfFloatExtension = lr(this.gl, i);
      else if (E().get("WEBGL_FORCE_F16_TEXTURES"))
        throw new Error("GL context does not support half float textures, yet the environment flag WEBGL_FORCE_F16_TEXTURES is set to true.");
      if (this.colorBufferFloatExtension = this.gl.getExtension(r), Ge(this.gl, s))
        this.colorBufferHalfFloatExtension = lr(this.gl, s);
      else if (E().get("WEBGL_FORCE_F16_TEXTURES"))
        throw new Error("GL context does not support color renderable half floats, yet the environment flag WEBGL_FORCE_F16_TEXTURES is set to true.");
    } else if (r = "EXT_color_buffer_float", Ge(this.gl, r))
      this.colorBufferFloatExtension = this.gl.getExtension(r);
    else if (Ge(this.gl, s))
      this.colorBufferHalfFloatExtension = this.gl.getExtension(s);
    else
      throw new Error("GL context does not support color renderable floats");
    this.vertexBuffer = ux(this.gl), this.indexBuffer = dx(this.gl), this.framebuffer = tg(this.gl), this.textureConfig = to(this.gl, this.textureHalfFloatExtension);
  }
  get debug() {
    return E().getBool("DEBUG");
  }
  dispose() {
    if (this.disposed)
      return;
    this.program != null && console.warn("Disposing a GPGPUContext that still has a bound WebGLProgram. This is probably a resource leak, delete the program with GPGPUContext.deleteProgram before disposing."), this.outputTexture != null && console.warn("Disposing a GPGPUContext that still has a bound output matrix texture.  This is probably a resource leak, delete the output matrix texture with GPGPUContext.deleteMatrixTexture before disposing.");
    const e = this.gl;
    B(e, () => e.finish()), B(e, () => e.bindFramebuffer(e.FRAMEBUFFER, null)), B(e, () => e.deleteFramebuffer(this.framebuffer)), B(e, () => e.bindBuffer(e.ARRAY_BUFFER, null)), B(e, () => e.bindBuffer(e.ELEMENT_ARRAY_BUFFER, null)), B(e, () => e.deleteBuffer(this.indexBuffer)), this.disposed = !0;
  }
  createFloat32MatrixTexture(e, t) {
    return this.throwIfDisposed(), hx(this.gl, e, t, this.textureConfig);
  }
  createFloat16MatrixTexture(e, t) {
    return this.throwIfDisposed(), fx(this.gl, e, t, this.textureConfig);
  }
  createUnsignedBytesMatrixTexture(e, t) {
    return this.throwIfDisposed(), px(this.gl, e, t, this.textureConfig);
  }
  uploadPixelDataToTexture(e, t) {
    this.throwIfDisposed(), Cx(this.gl, e, t);
  }
  uploadDenseMatrixToTexture(e, t, r, s) {
    this.throwIfDisposed(), wx(this.gl, e, t, r, s, this.textureConfig);
  }
  createFloat16PackedMatrixTexture(e, t) {
    return this.throwIfDisposed(), gx(this.gl, e, t, this.textureConfig);
  }
  createPackedMatrixTexture(e, t) {
    return this.throwIfDisposed(), mx(this.gl, e, t, this.textureConfig);
  }
  deleteMatrixTexture(e) {
    this.throwIfDisposed(), this.outputTexture === e && (Xo(this.gl, this.framebuffer), this.outputTexture = null), B(this.gl, () => this.gl.deleteTexture(e));
  }
  downloadByteEncodedFloatMatrixFromOutputTexture(e, t, r) {
    return this.downloadMatrixDriver(e, () => $x(this.gl, t, r, this.textureConfig));
  }
  downloadPackedMatrixFromBuffer(e, t, r, s, o, i) {
    return vx(this.gl, e, t, r, s, o, i, this.textureConfig);
  }
  downloadFloat32MatrixFromBuffer(e, t) {
    return yx(this.gl, e, t);
  }
  createBufferFromTexture(e, t, r) {
    this.bindTextureToFrameBuffer(e);
    const s = bx(this.gl, t, r, this.textureConfig);
    return this.unbindTextureToFrameBuffer(), s;
  }
  createAndWaitForFence() {
    const e = this.createFence(this.gl);
    return this.pollFence(e);
  }
  createFence(e) {
    let t, r;
    if (E().getBool("WEBGL_FENCE_API_ENABLED")) {
      const s = e, o = s.fenceSync(s.SYNC_GPU_COMMANDS_COMPLETE, 0);
      e.flush(), r = () => {
        const i = s.clientWaitSync(o, 0, 0);
        return i === s.ALREADY_SIGNALED || i === s.CONDITION_SATISFIED;
      }, t = o;
    } else E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_VERSION") > 0 ? (t = this.beginQuery(), this.endQuery(), r = () => this.isQueryAvailable(t, E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_VERSION"))) : r = () => !0;
    return { query: t, isFencePassed: r };
  }
  downloadMatrixFromPackedTexture(e, t, r) {
    return this.downloadMatrixDriver(e, () => Ix(this.gl, t, r));
  }
  createProgram(e) {
    this.throwIfDisposed();
    const t = this.gl;
    this.vertexShader == null && (this.vertexShader = lx(t));
    const r = Km(t);
    B(t, () => t.attachShader(r, this.vertexShader)), B(t, () => t.attachShader(r, e)), Ym(t, r);
    const s = Object.assign(r, { vao: this.createVertexArray() });
    return this.debug && es(t, s), s;
  }
  buildVao(e) {
    this.setProgram(e), this.bindVertexArray(e.vao);
    const t = this.gl;
    B(t, () => t.bindBuffer(t.ELEMENT_ARRAY_BUFFER, this.indexBuffer)), xx(t, e, this.vertexBuffer);
  }
  deleteProgram(e) {
    this.throwIfDisposed(), e === this.program && (this.program = null), e != null && (B(this.gl, () => this.gl.deleteProgram(e)), this.deleteVertexArray(e.vao));
  }
  setProgram(e) {
    this.throwIfDisposed(), this.program = e, this.program != null && this.debug && es(this.gl, this.program), B(this.gl, () => this.gl.useProgram(e));
  }
  getUniformLocation(e, t, r = !0) {
    return this.throwIfDisposed(), r ? rg(this.gl, e, t) : sg(this.gl, e, t);
  }
  getAttributeLocation(e, t) {
    return this.throwIfDisposed(), B(this.gl, () => this.gl.getAttribLocation(e, t));
  }
  getUniformLocationNoThrow(e, t) {
    return this.throwIfDisposed(), this.gl.getUniformLocation(e, t);
  }
  setInputMatrixTexture(e, t, r) {
    this.throwIfDisposed(), this.throwIfNoProgram(), og(this.gl, e, t, r);
  }
  setOutputMatrixTexture(e, t, r) {
    this.setOutputMatrixTextureDriver(e, r, t);
  }
  setOutputPackedMatrixTexture(e, t, r) {
    this.throwIfDisposed();
    const [s, o] = Rn(t, r);
    this.setOutputMatrixTextureDriver(e, s, o);
  }
  setOutputMatrixWriteRegion(e, t, r, s) {
    this.setOutputMatrixWriteRegionDriver(r, e, s, t);
  }
  setOutputPackedMatrixWriteRegion(e, t, r, s) {
    throw new Error("setOutputPackedMatrixWriteRegion not implemented.");
  }
  debugValidate() {
    this.program != null && es(this.gl, this.program), ur(this.gl);
  }
  executeProgram() {
    this.throwIfDisposed(), this.throwIfNoProgram();
    const e = this.gl;
    if (this.debug) {
      const t = this.getVertexArray();
      console.assert(t === this.program.vao, "VAO changed between setProgram and executeProgram!"), this.debugValidate();
    }
    B(e, () => e.drawElements(e.TRIANGLES, 6, e.UNSIGNED_SHORT, 0));
  }
  blockUntilAllProgramsCompleted() {
    this.throwIfDisposed(), B(this.gl, () => this.gl.finish());
  }
  getQueryTimerExtension() {
    return this.disjointQueryTimerExtension == null && (this.disjointQueryTimerExtension = lr(this.gl, E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_VERSION") === 2 ? "EXT_disjoint_timer_query_webgl2" : "EXT_disjoint_timer_query")), this.disjointQueryTimerExtension;
  }
  getQueryTimerExtensionWebGL2() {
    return this.getQueryTimerExtension();
  }
  getQueryTimerExtensionWebGL1() {
    return this.getQueryTimerExtension();
  }
  beginQuery() {
    if (E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_VERSION") === 2) {
      const r = this.gl, s = this.getQueryTimerExtensionWebGL2(), o = r.createQuery();
      return r.beginQuery(s.TIME_ELAPSED_EXT, o), o;
    }
    const e = this.getQueryTimerExtensionWebGL1(), t = e.createQueryEXT();
    return e.beginQueryEXT(e.TIME_ELAPSED_EXT, t), t;
  }
  endQuery() {
    if (E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_VERSION") === 2) {
      const t = this.gl, r = this.getQueryTimerExtensionWebGL2();
      t.endQuery(r.TIME_ELAPSED_EXT);
      return;
    }
    const e = this.getQueryTimerExtensionWebGL1();
    e.endQueryEXT(e.TIME_ELAPSED_EXT);
  }
  async waitForQueryAndGetTime(e) {
    return await wo(() => this.disposed || // while testing contexts are created / disposed
    // in rapid succession, so without this check we
    // may poll for the query timer indefinitely
    this.isQueryAvailable(e, E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_VERSION"))), this.getQueryTime(e, E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_VERSION"));
  }
  getQueryTime(e, t) {
    if (t === 0)
      return null;
    if (t === 2) {
      const r = this.gl;
      return r.getQueryParameter(e, r.QUERY_RESULT) / 1e6;
    } else {
      const r = this.getQueryTimerExtensionWebGL1();
      return r.getQueryObjectEXT(e, r.QUERY_RESULT_EXT) / 1e6;
    }
  }
  isQueryAvailable(e, t) {
    if (t === 0)
      return !0;
    if (t === 2) {
      const r = this.gl, s = this.getQueryTimerExtensionWebGL2(), o = r.getQueryParameter(e, r.QUERY_RESULT_AVAILABLE);
      return this.disjoint == null && (this.disjoint = this.gl.getParameter(s.GPU_DISJOINT_EXT)), o && !this.disjoint;
    } else {
      const r = this.getQueryTimerExtensionWebGL1(), s = r.getQueryObjectEXT(e, r.QUERY_RESULT_AVAILABLE_EXT);
      return this.disjoint == null && (this.disjoint = this.gl.getParameter(r.GPU_DISJOINT_EXT)), s && !this.disjoint;
    }
  }
  pollFence(e) {
    return new Promise((t) => {
      this.addItemToPoll(() => e.isFencePassed(), () => t());
    });
  }
  pollItems() {
    const e = Sx(this.itemsToPoll.map((t) => t.isDoneFn));
    for (let t = 0; t <= e; ++t) {
      const { resolveFn: r } = this.itemsToPoll[t];
      r();
    }
    this.itemsToPoll = this.itemsToPoll.slice(e + 1);
  }
  addItemToPoll(e, t) {
    if (this.itemsToPoll.push({ isDoneFn: e, resolveFn: t }), this.itemsToPoll.length > 1)
      return;
    let r;
    "setTimeoutCustom" in E().platform && (r = E().platform.setTimeoutCustom.bind(E().platform)), wo(() => (this.pollItems(), this.itemsToPoll.length === 0), () => 0, null, r);
  }
  bindTextureToFrameBuffer(e) {
    this.throwIfDisposed(), ts(this.gl, e, this.framebuffer), this.debug && ur(this.gl);
  }
  unbindTextureToFrameBuffer() {
    this.outputTexture != null ? (ts(this.gl, this.outputTexture, this.framebuffer), this.debug && ur(this.gl)) : Xo(this.gl, this.framebuffer);
  }
  downloadMatrixDriver(e, t) {
    this.bindTextureToFrameBuffer(e);
    const r = t();
    return this.unbindTextureToFrameBuffer(), r;
  }
  setOutputMatrixTextureDriver(e, t, r) {
    this.throwIfDisposed();
    const s = this.gl;
    ts(s, e, this.framebuffer), this.debug && ur(s), this.outputTexture = e, B(s, () => s.viewport(0, 0, t, r)), B(s, () => s.scissor(0, 0, t, r));
  }
  setOutputMatrixWriteRegionDriver(e, t, r, s) {
    this.throwIfDisposed(), B(this.gl, () => this.gl.scissor(e, t, r, s));
  }
  throwIfDisposed() {
    if (this.disposed)
      throw new Error("Attempted to use disposed GPGPUContext.");
  }
  throwIfNoProgram() {
    if (this.program == null)
      throw new Error("No GPU program is currently set.");
  }
}
function Sx(n) {
  let e = 0;
  for (; e < n.length && n[e](); ++e)
    ;
  return e - 1;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ex(n) {
  const e = new Float32Array(n.length);
  for (let t = 0; t < n.length; ++t)
    e[t] = Math.abs(n[t]);
  return e;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Te(n) {
  return (e, t, r, s, o) => {
    const i = ve(e, t), a = i.length, c = me(i), l = _(i), u = Ut(o, l), d = e.length, h = t.length, f = me(e), m = me(t), C = Er(e, i), w = Er(t, i);
    if (C.length + w.length === 0)
      for (let x = 0; x < u.length; ++x)
        u[x] = n(r[x % r.length], s[x % s.length]);
    else
      for (let x = 0; x < u.length; ++x) {
        const y = Fs(x, a, c), v = y.slice(-d);
        C.forEach((F) => v[F] = 0);
        const I = ls(v, d, f), T = y.slice(-h);
        w.forEach((F) => T[F] = 0);
        const A = ls(T, h, m);
        u[x] = n(r[I], s[A]);
      }
    return [u, i];
  };
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Rx(n, e, t, r) {
  if (r === "int32") {
    const s = Int32Array.from(n);
    return [e, "int32", s];
  }
  if (r === "bool") {
    const s = Or([0], t), [o, i] = Te((a, c) => a !== c ? 1 : 0)(e, [], n, s, "bool");
    return [i, "bool", o];
  }
  throw new Error(`Error in Cast: failed to cast ${t} to ${r}`);
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Tx = Te((n, e) => n + e);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Nx(n, e, t, r, s) {
  const o = _(r), i = Rt(s, t);
  for (let a = 0; a < n.length; a++) {
    const c = n[a];
    if (c < 0)
      throw new Error("Input x must be non-negative!");
    c >= s || (o > 0 ? i[c] += e[a] : i[c] += 1);
  }
  return i;
}
function kx(n, e, t, r = !1) {
  const s = n.shape[0], o = n.shape[1], i = xe([s, t], e.dtype);
  for (let a = 0; a < s; a++)
    for (let c = 0; c < o; c++) {
      const l = n.get(a, c);
      if (l < 0)
        throw new Error("Input x must be non-negative!");
      l >= t || (r ? i.set(1, a, l) : e.size > 0 ? i.set(i.get(a, l) + e.get(a, c), a, l) : i.set(i.get(a, l) + 1, a, l));
    }
  return i;
}
/**
 * @license
 * Copyright 2023 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Ax = Te((n, e) => n & e);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function wt(n) {
  return (e, t, r) => {
    const s = de(t, e.length);
    for (let o = 0; o < e.length; ++o)
      s[o] = n(e[o], r);
    return s;
  };
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Fx = wt((n) => Math.ceil(n));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Dx(n, e, t, r) {
  const s = de(t, _(e));
  if (r && t !== "string") {
    let o = 0;
    n.forEach((i) => {
      const a = _(i.shape);
      s.set(i.vals, o), o += a;
    });
  } else {
    let o = 0;
    n.forEach((i) => {
      const a = t === "string" ? bn(i.vals) : i.vals;
      let c = 0;
      for (let l = 0; l < i.shape[0]; ++l) {
        const u = l * e[1] + o;
        for (let d = 0; d < i.shape[1]; ++d)
          s[u + d] = a[c++];
      }
      o += i.shape[1];
    });
  }
  return s;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Ox = Te((n, e) => n === e ? 1 : 0);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Px = wt((n) => Math.exp(n));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const _x = wt((n) => Math.expm1(n));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Bx = wt((n) => Math.floor(n));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Lx = Te((n, e) => Math.floor(n / e));
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Mx(n, e, t, r, s, o, i, a, c) {
  const l = xe([r, o], t);
  for (let u = 0; u < r; u++) {
    const d = [];
    let h = 0;
    for (let f = 0; f < s; f++) {
      const m = n[u * s + f];
      h += m * i[f], d.push(m);
    }
    if (h < 0 || h >= c / o)
      throw new Error(`Invalid indices: ${d} does not index into ${a}`);
    for (let f = 0; f < o; f++)
      l.values[u * o + f] = e.get(...e.indexToLoc(h * o + f));
  }
  return l;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ux(n, e, t) {
  const r = xe(t, n.dtype);
  for (let s = 0; s < r.size; ++s) {
    const i = r.indexToLoc(s).slice(), a = i[0], c = i[2], l = e.locToIndex([a, c]);
    i[2] = e.values[l];
    const u = n.locToIndex(i);
    0 <= u && u < n.values.length && (r.values[s] = n.values[u]);
  }
  return r;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Vx = Te((n, e) => n > e ? 1 : 0);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Wx = Te((n, e) => n >= e ? 1 : 0);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Gx = Te((n, e) => n < e ? 1 : 0);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const zx = Te((n, e) => n <= e ? 1 : 0);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Hx(n, e, t) {
  const r = (e - n) / (t - 1), s = Rt(t, "float32");
  s[0] = n;
  for (let o = 1; o < s.length; o++)
    s[o] = s[o - 1] + r;
  return s;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Xx = wt((n) => Math.log(n));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function jx(n, e, t, r) {
  const s = Ut(r, _(t));
  for (let o = 0; o < s.length; ++o) {
    const i = o * e;
    let a = n[i];
    for (let c = 0; c < e; ++c) {
      const l = n[i + c];
      (Number.isNaN(l) || l > a) && (a = l);
    }
    s[o] = a;
  }
  return s;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const qx = Te((n, e) => Math.max(n, e));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Kx = Te((n, e) => Math.min(n, e));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Uc = Te((n, e) => n * e);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Yx(n, e, t) {
  const r = vn(-1, t);
  return Uc([], e, r, n, t);
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Qx = Te((n, e) => n !== e ? 1 : 0);
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Zx(n, e, t, r, s) {
  const o = e.length, i = _(e), a = me(e), c = me(s), l = Ut(t, _(s));
  for (let u = 0; u < i; ++u) {
    const d = Fs(u, o, a), h = new Array(d.length);
    for (let m = 0; m < h.length; m++)
      h[m] = d[r[m]];
    const f = ls(h, o, c);
    l[f] = n[u];
  }
  return l;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Jx(n, e, t, r) {
  const [s, o] = ht(n, r), i = dt(e, "int32"), a = Rt(_(s), i), c = _(o);
  for (let l = 0; l < a.length; ++l) {
    const u = l * c;
    let d = 1;
    for (let h = 0; h < c; ++h)
      d *= t[u + h];
    a[l] = d;
  }
  return { outVals: a, outShape: s, outDtype: i };
}
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function e0(n, e, t) {
  n.forEach((r, s) => {
    if (r < 0 || r >= t) {
      const o = Fs(s, e.length, me(e)).join(",");
      throw new Error(`indices[${o}] = ${r} is not in [0, ${t})`);
    }
  });
}
function t0(n, e) {
  for (let t = 0; t < n.length; ++t) {
    const r = n[t], s = t === n.length - 1 ? e : n[t + 1].length;
    if (r.length === 0)
      throw new Error("Ragged splits may not be empty");
    if (r[0] < 0)
      throw new Error("Ragged splits must be non-negative");
    if (r[r.length - 1] > s)
      throw new Error("Ragged splits must not point past values");
    for (let o = 1; o < r.length; ++o)
      if (r[o - 1] > r[o])
        throw new Error("Ragged splits must be sorted in ascending order");
  }
}
function n0(n, e, t, r) {
  const s = [];
  let o = 0;
  const i = e.length - 1 + t.length, a = new Array(i).fill(null).map(() => [0]);
  t0(t, r);
  let c = 1;
  for (let l = 0; l < e.length - 1; ++l) {
    c *= e[l];
    const u = e[l + 1];
    for (let d = 1; d < c + 1; ++d)
      a[l].push(d * u);
  }
  for (let l = 0; l < n.length; ++l) {
    let u = n[l], d = n[l] + 1;
    for (let h = 0; h < t.length; ++h) {
      const f = t[h], m = h + e.length - 1;
      if (m >= 0) {
        const C = a[m], w = C[C.length - 1] - f[u];
        for (let x = u; x < d; ++x)
          a[m].push(f[x + 1] + w);
      }
      u = f[u], d = f[d];
    }
    d !== u && (s.push([u, d]), o += d - u);
  }
  return { outSplits: a, valueSlices: s, numValues: o };
}
function r0(n) {
  const e = [];
  for (let t = 0; t < n.length; ++t) {
    const r = n[t].length, s = de("int32", r);
    e.push(s), n[t].forEach((o, i) => s[i] = o);
  }
  return e;
}
function Yo(n, e) {
  const t = n.slice(0, e);
  for (; t.length < e; )
    t.push(1);
  for (let r = e; r < n.length; r++)
    t[e - 1] *= n[r];
  return t;
}
function s0(n, e, t, r, s, o) {
  const i = Yo(e, 2)[1], a = Yo(o, 2)[1];
  let c = 0;
  for (const l of t)
    for (let u = l[0]; u < l[1]; ++u) {
      for (let d = 0; d < r; ++d)
        s[c * a + d] = n[u * i + d];
      ++c;
    }
}
function o0(n, e, t, r, s) {
  const o = e.slice();
  o[0] = s;
  const i = de(t, _(o)), a = n.length, c = a === 0 ? 0 : a / e[0];
  return s0(n, e, r, c, i, o), [i, o];
}
function i0(n, e, t, r, s, o, i, a) {
  if (n.length === 0)
    throw new Error("paramsNestedSplits must be non empty");
  if (e[0].length === 0)
    throw new Error("Split tensors must not be scalars");
  const c = e[0][0] - 1;
  if (e0(o, i, c), r.length === 0)
    throw new Error("params.rank must be nonzero");
  const l = r[0], { outSplits: u, valueSlices: d, numValues: h } = n0(o, i, n, l), f = r0(u), m = o0(t, r, s, d, h);
  return [f, m[0], m[1]];
}
/**
 * @license
 * Copyright 2022 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Qo = 2147483647;
function a0(n, e, t, r, s, o, i) {
  if (e.length > 1)
    throw new Error("starts must be a scalar or vector");
  if (s.length > 1)
    throw new Error("limits must be a scalar or vector");
  if (i.length > 1)
    throw new Error("deltas must be a scalar or vector");
  const a = e.length === 0, c = s.length === 0, l = i.length === 0, u = [];
  a || u.push(e[0]), c || u.push(s[0]), l || u.push(i[0]);
  for (let w = 1; w < u.length; ++w)
    if (u[w] !== u[w - 1])
      throw new Error("starts, limits, and deltas must have the same shape");
  const d = u.length === 0 ? 1 : u[0], h = de("int32", d + 1);
  h[0] = 0;
  for (let w = 0; w < d; ++w) {
    const x = a ? n[0] : n[w], y = c ? r[0] : r[w], v = l ? o[0] : o[w];
    if (v === 0)
      throw new Error("Requires delta != 0");
    let I;
    if (v > 0 && y < x || v < 0 && y > x)
      I = 0;
    else if (I = Math.ceil(Math.abs((y - x) / v)), I > Qo)
      throw new Error(`Requires ((limit - start) / delta) <= ${Qo}`);
    h[w + 1] = h[w] + I;
  }
  const f = h[d], m = de(t, f);
  let C = 0;
  for (let w = 0; w < d; ++w) {
    const x = h[w + 1] - h[w];
    let y = a ? n[0] : n[w];
    const v = l ? o[0] : o[w];
    for (let I = 0; I < x; ++I)
      m[C++] = y, y += v;
  }
  return [h, m];
}
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
var Be = Ye;
class Tr {
  constructor(e, t, r, s, o, i, a, c, l, u) {
    this.shape = e, this.shapeShape = t, this.values = r, this.valuesShape = s, this.valuesDType = o, this.defaultValue = i, this.defaultValueShape = a, this.rowPartitionValues = c, this.rowPartitionValuesShapes = l, this.rowPartitionTypes = qa(u), this.raggedRank = Ka(this.rowPartitionTypes);
  }
  getRowPartitionTypeByDimension(e) {
    return this.rowPartitionTypes[0] === Be.FIRST_DIM_SIZE ? this.rowPartitionTypes[e + 1] : this.rowPartitionTypes[e];
  }
  // Returns the relationship between dimension and dimension + 1.
  getRowPartitionTensor(e) {
    return this.rowPartitionTypes[0] === Be.FIRST_DIM_SIZE ? this.rowPartitionValues[e + 1] : this.rowPartitionValues[e];
  }
  getMaxWidth(e) {
    const t = this.getRowPartitionTensor(e - 1);
    switch (this.getRowPartitionTypeByDimension(e - 1)) {
      case Be.VALUE_ROWIDS:
        return Tr.getMaxWidthValueRowID(t);
      case Be.ROW_SPLITS:
        return Tr.getMaxWidthRowSplit(t);
      default:
        throw new Error(`Cannot handle partition type ${Be[this.getRowPartitionTypeByDimension(e - 1)]}`);
    }
  }
  static getMaxWidthRowSplit(e) {
    const t = e.length;
    if (t === 0 || t === 1)
      return 0;
    let r = 0;
    for (let s = 0; s < t - 1; ++s) {
      const o = e[s + 1] - e[s];
      o > r && (r = o);
    }
    return r;
  }
  static getMaxWidthValueRowID(e) {
    const t = e.length;
    if (t === 0)
      return 0;
    let r = 0, s = e[0], o = 0;
    for (let i = 1; i < t; ++i) {
      const a = e[i];
      a !== s && (s = a, o = Math.max(i - r, o), r = i);
    }
    return Math.max(t - r, o);
  }
  tensorShapeFromTensor(e, t, r = !0) {
    if (t.length === 0) {
      if (e[0] === -1)
        return [];
      throw new Error("The only valid scalar shape tensor is the fully unknown shape specified as -1.");
    }
    return Jo(e, r);
  }
  calculateOutputSize(e) {
    const t = this.valuesShape, r = this.defaultValueShape;
    Ya(r, t);
    const s = this.tensorShapeFromTensor(this.shape, this.shapeShape), i = ja(this.raggedRank, s, t);
    i[0] < 0 && (i[0] = e);
    for (let a = 1; a <= this.raggedRank; ++a)
      i[a] < 0 && (i[a] = this.getMaxWidth(a));
    return i;
  }
  /**
   * The outputIndex represents the index in the output tensor
   * where the first element of a particular dimension would be written.
   * If it is -1, it indicates that the index is out of scope.
   * Example, given firstDimension = 10, firstDimensionOutput = 6,
   * and outputIndexMultiplier = 100:
   * result = [0 100 200 300 400 500 -1 -1 -1 -1]
   * If firstDimensionOutput = 11 instead, then:
   * result = [0 100 200 300 400 500 600 700 800 900]
   */
  calculateFirstParentOutputIndex(e, t, r) {
    const s = Math.min(e, r), o = [];
    let i = 0;
    for (let a = 0; a < s; ++a, i += t)
      o.push(i);
    for (let a = s; a < e; ++a)
      o.push(-1);
    return O(o.length === e, () => "Final length of result must be equal to firstDimension."), o;
  }
  calculateOutputIndexRowSplit(e, t, r, s) {
    const o = e.length, i = [];
    for (let a = 0; a < o - 1; ++a) {
      const c = e[a + 1] - e[a];
      let l = Math.min(s, c), u = t[a];
      u === -1 && (l = 0);
      for (let d = 0; d < l; ++d)
        i.push(u), u += r;
      for (let d = 0; d < c - l; ++d)
        i.push(-1);
    }
    if (o > 0 && i.length !== e[o - 1])
      throw new Error("Invalid row split size.");
    return i;
  }
  // Calculate the output index of the first element of a list.
  // The parentOutputIndex is the same computation for the previous list.
  // -1 indicates an element or list that is out of range.
  // The outputIndexMultiplier is the number of output indices one moves
  // forward for each column.
  // E.g., given:
  // valueRowIds:[0 1 2 2 2 3 5 5 6]
  // parentOutputIndex:[1000 1100 2000 2100 -1 3000 4000]
  // outputIndexMultiplier: 10
  // outputSize: 2
  // You get:
  // result = [1000 1100 2000 2010 -1 2100 -1 -1 3000]
  // result[0] = parentOutputIndex[valueRowIds[0]]
  // result[1] = parentOutputIndex[valueRowIds[1]]
  // result[2] = parentOutputIndex[valueRowIds[2]]
  // result[3] = parentOutputIndex[valueRowIds[2] + 10]
  // result[4] = -1 because it is the third element the size is 2.
  // result[5] = parentOutputIndex[valueRowIds[3]]
  // result[6] = -1 because parentOutputIndex[valueRowIds[6]] == -1
  // result[7] = -1 because parentOutputIndex[valueRowIds[6]] == -1
  // result[8] = parentOutputIndex[valueRowIds[7]]
  calculateOutputIndexValueRowID(e, t, r, s) {
    const o = e.length, i = [];
    if (o === 0)
      return [];
    let a = 0, c = e[0];
    if (c >= t.length)
      throw new Error(`Got currentValueRowId=${c}, which is not less than ${t.length}`);
    let l = t[c];
    i.push(l);
    for (let u = 1; u < o; ++u) {
      const d = e[u];
      if (d === c)
        l >= 0 && (++a, a < s ? l += r : l = -1);
      else {
        if (a = 0, c = d, d >= t.length)
          throw new Error(`Got nextValueRowId=${d} which is not less than ${t.length}`);
        l = t[d];
      }
      i.push(l);
    }
    if (i.length !== e.length)
      throw new Error("Invalid row ids.");
    return i;
  }
  calculateOutputIndex(e, t, r, s) {
    const o = this.getRowPartitionTensor(e), i = this.getRowPartitionTypeByDimension(e);
    switch (i) {
      case Be.VALUE_ROWIDS:
        return this.calculateOutputIndexValueRowID(o, t, r, s);
      case Be.ROW_SPLITS:
        if (o.length - 1 > t.length)
          throw new Error(`Row partition size is greater than output size: ${o.length - 1} > ${t.length}`);
        return this.calculateOutputIndexRowSplit(o, t, r, s);
      default:
        throw new Error(`Unsupported partition type: ${Be[i]}`);
    }
  }
  getFirstDimensionSize() {
    const e = this.rowPartitionValues[0];
    if (this.rowPartitionTypes.length === 0)
      throw new Error("No row_partition_types given.");
    const t = this.rowPartitionTypes[0];
    switch (t) {
      case Be.FIRST_DIM_SIZE:
        return e[0];
      case Be.VALUE_ROWIDS:
        throw new Error("Cannot handle VALUE_ROWIDS in first dimension.");
      case Be.ROW_SPLITS:
        return this.rowPartitionValuesShapes[0][0] - 1;
      default:
        throw new Error(`Cannot handle type ${Be[t]}`);
    }
  }
  compute() {
    if (this.rowPartitionValues[0].length <= 0)
      throw new Error("Invalid first partition input. Tensor requires at least one element.");
    const t = this.getFirstDimensionSize(), r = this.calculateOutputSize(t), s = new Array(this.raggedRank + 1);
    s[s.length - 1] = 1;
    for (let c = s.length - 2; c >= 0; --c)
      s[c] = s[c + 1] * r[c + 1];
    const o = Jo(r, !1), i = de(this.valuesDType, _(o));
    if (s[0] * r[0] > 0) {
      let c = this.calculateFirstParentOutputIndex(t, s[0], r[0]);
      for (let l = 1; l <= this.raggedRank; ++l)
        c = this.calculateOutputIndex(l - 1, c, s[l], r[l]);
      this.setOutput(this.raggedRank, c, i, o);
    }
    return [o, i];
  }
  setOutput(e, t, r, s) {
    if (r.length === 0)
      return;
    const o = this.values, i = r;
    let a = s.slice();
    a = a.slice(e + 1);
    const c = _(a), l = t.length;
    let u = this.defaultValue;
    if (u.length !== c && u.length !== 1) {
      const m = this.defaultValueShape;
      se(() => {
        const C = zs(u, m);
        u = dp(C, a).dataSync();
      });
    }
    let d = 0, h = 0, f = 0;
    for (let m = 0; m <= l; ++m) {
      let C = m < l ? t[m] : -1;
      if (C === f) {
        ++f;
        continue;
      }
      if (h < f) {
        const w = o.subarray(d * c), x = i.subarray(h * c), y = (f - h) * c;
        Zo(x, w, y);
      }
      if (m >= l) {
        const w = r.length;
        C = Math.floor(w / c);
      }
      if (C > f)
        if (this.defaultValue.length === 1)
          i.subarray(f * c, C * c).fill(this.defaultValue[0]), f = C;
        else
          for (; C > f; ) {
            const w = i.slice(f * c);
            Zo(w, u, c), ++f;
          }
      C < 0 ? (d = m + 1, h = f) : (d = m, h = f, f = h + 1);
    }
  }
}
function Zo(n, e, t) {
  for (let r = 0; r < t; r++)
    n[r] = e[r];
}
function Jo(n, e) {
  const t = [];
  for (let r of n) {
    if (r < 0) {
      if (!e)
        throw new Error(`Dimension ${r} must be >= 0`);
      if (r < -1)
        throw new Error(`Dimension ${r} must be >= -1`);
      r = -1;
    }
    t.push(r);
  }
  return t;
}
function c0(n, e, t, r, s, o, i, a, c, l) {
  return new Tr(n, e, t, r, s, o, i, a, c, l).compute();
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function l0(n, e, t, r) {
  const s = n === e, o = n < e && t < 0, i = e < n && t > 1;
  if (s || o || i)
    return Rt(0, r);
  const a = Math.abs(Math.ceil((e - n) / t)), c = Rt(a, r);
  e < n && t === 1 && (t = -1), c[0] = n;
  for (let l = 1; l < c.length; l++)
    c[l] = c[l - 1] + t;
  return c;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const u0 = wt((n) => 1 / Math.sqrt(n));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function d0(n, e, t, r, s, o, i, a, c, l) {
  const u = [r / s, s], d = n.values, h = e.values;
  if (r === 0)
    return xe(t, e.dtype);
  const f = c instanceof vr ? c : xe(u, e.dtype);
  typeof c == "string" || typeof c == "number" ? f.values.fill(c) : typeof c == "boolean" && f.values.fill(+c);
  for (let m = 0; m < o; m++) {
    const C = [];
    let w = 0;
    for (let x = 0; x < i; x++) {
      const y = d[m * i + x];
      C.push(y), w += y * a[x];
    }
    if (w < 0 || w >= r / s)
      throw new Error(`Invalid indices: ${C} does not index into ${t}`);
    for (let x = 0; x < s; x++)
      l ? f.values[w * s + x] += h[m * s + x] : f.values[w * s + x] = e.rank === 0 ? h[0] : h[m * s + x];
  }
  return f;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const h0 = wt((n) => 1 / (1 + Math.exp(-n)));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function f0(n, e, t, r, s) {
  const o = Ks(r, e, t), i = _(t), a = me(r);
  if (o) {
    const d = Ys(e, a);
    return s === "string" ? n.slice(d, d + i) : n.subarray(d, d + i);
  }
  const c = s === "string" ? bn(n) : n, l = xe(r, s, c), u = xe(t, s);
  for (let d = 0; d < u.size; ++d) {
    const h = u.indexToLoc(d), f = h.map((m, C) => m + e[C]);
    u.set(l.get(...f), ...h);
  }
  return s === "string" ? Tc(u.values) : u.values;
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function p0(n, e, t, r, s, o, i) {
  const a = e[0], c = o[0], l = new Array(c), u = new Array(a), d = e[1];
  if (c === 0) {
    if (a !== 0)
      throw new Error(pc(a));
    const w = de(t, 0), x = de(s, 0);
    return [
      w,
      [0, d],
      x,
      l,
      u
    ];
  }
  let h = !0, f = 0;
  const m = new Array(c).fill(0);
  for (let w = 0; w < a; ++w) {
    const x = n[w * d];
    if (x < 0)
      throw new Error(mc(w, x));
    if (x >= c)
      throw new Error(gc(w, x, c));
    ++m[x], h = h && x >= f, f = x;
  }
  let C = !0;
  for (let w = 0; w < c; ++w) {
    const x = m[w] === 0;
    l[w] = x, C = C && !x, m[w] = Math.max(m[w], 1), w > 0 && (m[w] += m[w - 1]);
  }
  if (C && h) {
    const w = n, x = r;
    for (let y = 0; y < a; ++y)
      u[y] = y;
    return [
      w,
      [a, d],
      x,
      l,
      u
    ];
  } else {
    const w = m[c - 1], x = de(t, w * d), y = de(s, w), v = new Array(c).fill(0);
    for (let I = 0; I < a; ++I) {
      const T = n[I * d], A = v[T], F = (T === 0 ? 0 : m[T - 1]) + A;
      v[T]++;
      for (let k = 0; k < d; ++k)
        x[F * d + k] = n[I * d + k];
      y[F] = r[I], u[I] = F;
    }
    for (let I = 0; I < c; ++I)
      if (v[I] === 0) {
        const A = I === 0 ? 0 : m[I - 1];
        x[A * d + 0] = I;
        for (let F = 1; F < d; ++F)
          x[A * d + F] = 0;
        y[A] = i;
      }
    return [
      x,
      [w, d],
      y,
      l,
      u
    ];
  }
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function m0(n, e, t, r, s) {
  const o = _(r), i = e[0], a = s.length, c = [];
  let l = 1, u = -1;
  for (let w = 0; w < a; ++w) {
    const x = s[w];
    if (x === -1) {
      if (u !== -1)
        throw new Error(xc(u, w));
      u = w, c.push(1);
    } else {
      if (x < 0)
        throw new Error(wc(w, x));
      l *= x, c.push(x);
    }
  }
  if (u !== -1) {
    if (l <= 0)
      throw new Error(Cc());
    const w = Math.trunc(o / l);
    if (l * w !== o)
      throw new Error(bc(r, c));
    c[u] = w;
  }
  if (_(c) !== o)
    throw new Error(yc(r, c));
  const h = r.length, f = [];
  if (h > 0) {
    f[h - 1] = 1;
    for (let w = h - 2; w >= 0; --w)
      f[w] = f[w + 1] * r[w + 1];
  }
  const m = [];
  if (a > 0) {
    m[a - 1] = 1;
    for (let w = a - 2; w >= 0; --w)
      m[w] = m[w + 1] * c[w + 1];
  }
  const C = de(t, i * a);
  for (let w = 0; w < i; ++w) {
    let x = 0;
    for (let y = 0; y < h; ++y)
      x += n[w * h + y] * f[y];
    for (let y = 0; y < a; ++y)
      C[w * a + y] = Math.trunc(x / m[y]), x %= m[y];
  }
  return [C, [i, a], c];
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function g0(n, e, t, r, s, o = !1, i = 0) {
  const a = r.length, c = [e[0], n.length / e[0]], l = c[1], d = a > 0 ? s[a - 1] + 1 : 0;
  if (d < 0)
    throw new Error(Es());
  const h = e.slice();
  h[0] = d;
  const f = h.reduce((v, I) => v * I, 1), m = de(t, f);
  if (a === 0)
    return d > 0 && m.fill(i), [m, h];
  if (d <= 0)
    throw new Error(Es());
  let C = 0, w = 1, x = 0, y = s[C];
  for (; ; ) {
    let v = 0;
    if (w < a) {
      if (v = s[w], y === v) {
        ++w;
        continue;
      }
      if (y >= v)
        throw new Error($c());
    }
    if (y < 0 || y >= d)
      throw new Error(vc(y, d));
    y > x && m.fill(i, x * l, y * l);
    for (let I = C; I < w; ++I) {
      const T = r[I];
      if (T < 0 || T >= c[0])
        throw new Error(Ic(I, r[I], c[0]));
      for (let A = 0; A < l; A++)
        m[y * l + A] += n[T * l + A];
    }
    if (o)
      for (let I = 0; I < l; I++)
        m[y * l + I] /= w - C;
    if (C = w, ++w, x = y + 1, y = v, w > a)
      break;
  }
  return x < d && m.fill(i, x * l, d * l), [m, h];
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const x0 = wt((n) => Math.sqrt(n));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const w0 = Te((n, e) => {
  const t = n - e;
  return t * t;
});
/**
 * @license
 * Copyright 2023 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const C0 = wt((n, e) => {
  const { pattern: t, replaceGlobal: r, rewrite: s } = e;
  return n.replace(new RegExp(t, r ? "g" : ""), s);
});
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function b0(n, e, t, r) {
  const s = xe(n, e.dtype);
  for (let o = 0; o < s.size; o++) {
    const i = s.indexToLoc(o), a = new Array(i.length);
    for (let c = 0; c < a.length; c++)
      a[c] = i[c] * t[c] + r[c];
    s.set(e.get(...a), ...i);
  }
  return s;
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class y0 {
  constructor(e, t, r, s, o, i) {
    this.separator = Lt(e), this.nGramWidths = t, this.leftPad = Lt(r), this.rightPad = Lt(s), this.padWidth = o, this.preserveShort = i;
  }
  getPadWidth(e) {
    return Math.min(this.padWidth < 0 ? e - 1 : this.padWidth, e - 1);
  }
  getNumNGrams(e, t) {
    const r = this.getPadWidth(t);
    return Math.max(0, e + 2 * r - t + 1);
  }
  createNGrams(e, t, r, s, o, i) {
    for (let a = 0; a < o; ++a) {
      const c = this.getPadWidth(i), l = Math.max(0, c - a), u = Math.max(0, c - (o - (a + 1))), d = i - (l + u), h = t + (l > 0 ? 0 : a - c);
      let f = 0;
      f += l * this.leftPad.length;
      for (let y = 0; y < d; ++y)
        f += e[h + y].length;
      f += u * this.rightPad.length;
      const m = l + u + d - 1;
      f += m * this.separator.length, r[s + a] = new Uint8Array(f);
      const C = r[s + a];
      let w = 0;
      const x = (y) => y.forEach((v) => C[w++] = v);
      for (let y = 0; y < l; ++y)
        x(this.leftPad), x(this.separator);
      for (let y = 0; y < d - 1; ++y)
        x(e[h + y]), x(this.separator);
      if (d > 0) {
        x(e[h + d - 1]);
        for (let y = 0; y < u; ++y)
          x(this.separator), x(this.rightPad);
      } else {
        for (let y = 0; y < u - 1; ++y)
          x(this.rightPad), x(this.separator);
        x(this.rightPad);
      }
    }
  }
  // Data and splits together form the definition of the ragged tensor,
  // where data is 1 dimensional and contains the values of the tensor
  // and splits denotes the indices at which each row starts.
  compute(e, t) {
    const r = e.length, s = t.length;
    if (s > 0) {
      let c = t[0];
      if (c !== 0)
        throw new Error(`First split value must be 0, got ${c}`);
      for (let l = 1; l < s; ++l) {
        let u = t[l] >= c;
        if (u = u && t[l] <= r, !u)
          throw new Error(`Invalid split value ${t[l]}, must be in [${c}, ${r}]`);
        c = t[l];
      }
      if (c !== r)
        throw new Error(`Last split value must be data size. Expected ${r}, got ${c}`);
    }
    const o = s - 1, i = de("int32", s);
    if (r === 0 || s === 0) {
      const c = new Array(r);
      for (let l = 0; l <= o; ++l)
        i[l] = 0;
      return [c, i];
    }
    i[0] = 0;
    for (let c = 1; c <= o; ++c) {
      const l = t[c] - t[c - 1];
      let u = 0;
      this.nGramWidths.forEach((d) => {
        u += this.getNumNGrams(l, d);
      }), this.preserveShort && l > 0 && u === 0 && (u = 1), i[c] = i[c - 1] + u;
    }
    const a = new Array(i[o]);
    for (let c = 0; c < o; ++c) {
      const l = t[c];
      let u = i[c];
      if (this.nGramWidths.forEach((d) => {
        const h = t[c + 1] - t[c], f = this.getNumNGrams(h, d);
        this.createNGrams(e, l, a, u, f, d), u += f;
      }), this.preserveShort && u === i[c]) {
        const d = t[c + 1] - t[c];
        if (d === 0)
          continue;
        const h = d + 2 * this.padWidth;
        this.createNGrams(e, l, a, u, 1, h);
      }
    }
    return [a, i];
  }
}
function $0(n, e, t, r, s, o, i, a) {
  return new y0(t, r, s, o, i, a).compute(n, e);
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function v0(n, e, t, r) {
  if (!n.length)
    return;
  if (e.length === 0) {
    for (let o = 0; o < n.length; ++o)
      r.push(n.subarray(o, o + 1));
    return;
  }
  if (e.length === 1) {
    const o = e[0];
    let i = n.indexOf(o);
    for (; i !== -1; ) {
      const a = n.subarray(0, i);
      (!t || a.length !== 0) && r.push(a), n = n.subarray(i + 1), i = n.indexOf(o);
    }
    (!t || n.length !== 0) && r.push(n);
    return;
  }
  let s = 0;
  for (let o = 0; o < n.length + 1; o++)
    if (o === n.length || e.indexOf(n[o]) !== -1) {
      const i = n.subarray(s, o);
      (!t || i.length !== 0) && r.push(i), s = o + 1;
    }
}
function I0(n, e, t) {
  const r = n.length, s = [];
  let o = 0, i = 0;
  const a = new Array(r);
  for (let h = 0; h < r; ++h) {
    const f = s.length;
    v0(n[h], e, t, s);
    const m = s.length - f;
    a[h] = m, o += m, i = Math.max(i, m);
  }
  const c = de("int32", o * 2), l = new Array(o), u = [r, i];
  let d = 0;
  for (let h = 0; h < r; ++h)
    for (let f = 0; f < a[h]; ++f)
      c[d * 2] = h, c[d * 2 + 1] = f, l[d] = s[d], ++d;
  return [c, l, u];
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function S0(n, e) {
  const t = de("int32", n.length);
  for (let r = 0; r < n.length; ++r)
    t[r] = Hh(n[r]).modulo(e).getLowBitsUnsigned();
  return t;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const E0 = Te((n, e) => n - e);
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function R0(n, e) {
  const t = new Array(n.rank);
  for (let s = 0; s < t.length; s++)
    t[s] = n.shape[s] * e[s];
  const r = xe(t, n.dtype);
  for (let s = 0; s < r.values.length; ++s) {
    const o = r.indexToLoc(s), i = new Array(n.rank);
    for (let c = 0; c < i.length; c++)
      i[c] = o[c] % n.shape[c];
    const a = n.locToIndex(i);
    r.values[s] = n.values[a];
  }
  return r;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Wn = (n, e) => {
  const t = e.value - n.value;
  return t === 0 ? n.index - e.index : t;
};
function Vc(n, e, t = 0, r = n.length - 1) {
  for (; r > t; ) {
    if (r - t > 600) {
      const a = r - t + 1, c = e - t + 1, l = Math.log(a), u = 0.5 * Math.exp(2 * l / 3), d = 0.5 * Math.sqrt(l * u * (a - u) / a) * Math.sign(c - a / 2), h = Math.max(t, Math.floor(e - c * u / a + d)), f = Math.min(r, Math.floor(e + (a - c) * u / a + d));
      Vc(n, e, h, f);
    }
    const s = n[e];
    let o = t, i = r;
    for (Ln(n, t, e), Wn(n[r], s) > 0 && Ln(n, t, r); o < i; ) {
      for (Ln(n, o, i), o++, i--; Wn(n[o], s) < 0; )
        o = o + 1;
      for (; Wn(n[i], s) > 0; )
        i = i - 1;
    }
    Wn(n[t], s) === 0 ? Ln(n, t, i) : (i = i + 1, Ln(n, i, r)), i <= e && (t = i + 1), e <= i && (r = i - 1);
  }
}
function T0(n, e, t, r, s) {
  const o = e[e.length - 1], [i, a] = [n.length / o, o], c = Ut(t, i * r), l = Ut("int32", i * r);
  for (let d = 0; d < i; d++) {
    const h = d * a, f = n.subarray(h, h + a);
    let m = new Array(f.length);
    f.forEach((y, v) => m[v] = { value: y, index: v }), r < m.length && (Vc(m, r), m = m.slice(0, r)), s && m.sort(Wn);
    const C = d * r, w = c.subarray(C, C + r), x = l.subarray(C, C + r);
    for (let y = 0; y < r; y++)
      w[y] = m[y].value, x[y] = m[y].index;
  }
  const u = e.slice();
  return u[u.length - 1] = r, [
    xe(u, t, c),
    xe(u, "int32", l)
  ];
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function N0(n, e, t, r) {
  const s = Re(e, t)[0], o = [1, t[0], 1];
  for (let m = 0; m < s; m++)
    o[0] *= t[m];
  o[1] = t[s];
  for (let m = s + 1; m < t.length; m++)
    o[2] *= t[m];
  const i = /* @__PURE__ */ new Map(), a = new Int32Array(t[s]), c = new vr(o, r, n), l = [], u = o[0] === 1 && o[2] === 1;
  for (let m = 0; m < t[s]; m++) {
    let C;
    if (u)
      C = n[m].toString();
    else {
      const x = [];
      for (let y = 0; y < o[0]; y++)
        for (let v = 0; v < o[2]; v++)
          x.push(c.get(y, m, v));
      C = x.join(",");
    }
    const w = i.get(C);
    if (w != null)
      a[m] = w;
    else {
      const x = i.size;
      i.set(C, x), a[m] = x, l.push(m);
    }
  }
  const d = o.slice();
  d[1] = i.size;
  const h = new vr(d, r);
  l.forEach((m, C) => {
    for (let w = 0; w < o[0]; w++)
      for (let x = 0; x < o[2]; x++)
        h.set(c.get(w, m, x), w, C, x);
  });
  const f = t.slice();
  return f[s] = d[1], {
    outputValues: h.values,
    outputShape: f,
    indices: a
  };
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const k0 = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  addImpl: Tx,
  bincountImpl: Nx,
  bincountReduceImpl: kx,
  bitwiseAndImpl: Ax,
  castImpl: Rx,
  ceilImpl: Fx,
  concatImpl: Dx,
  equalImpl: Ox,
  expImpl: Px,
  expm1Impl: _x,
  floorDivImpl: Lx,
  floorImpl: Bx,
  gatherNdImpl: Mx,
  gatherV2Impl: Ux,
  greaterEqualImpl: Wx,
  greaterImpl: Vx,
  lessEqualImpl: zx,
  lessImpl: Gx,
  linSpaceImpl: Hx,
  logImpl: Xx,
  maxImpl: jx,
  maximumImpl: qx,
  minimumImpl: Kx,
  multiplyImpl: Uc,
  negImpl: Yx,
  notEqualImpl: Qx,
  prodImpl: Jx,
  raggedGatherImpl: i0,
  raggedRangeImpl: a0,
  raggedTensorToTensorImpl: c0,
  rangeImpl: l0,
  rsqrtImpl: u0,
  scatterImpl: d0,
  sigmoidImpl: h0,
  simpleAbsImpl: Ex,
  sliceImpl: f0,
  sparseFillEmptyRowsImpl: p0,
  sparseReshapeImpl: m0,
  sparseSegmentReductionImpl: g0,
  sqrtImpl: x0,
  squaredDifferenceImpl: w0,
  staticRegexReplaceImpl: C0,
  stridedSliceImpl: b0,
  stringNGramsImpl: $0,
  stringSplitImpl: I0,
  stringToHashBucketFastImpl: S0,
  subImpl: E0,
  tileImpl: R0,
  topKImpl: T0,
  transposeImpl: Zx,
  uniqueImpl: N0
}, Symbol.toStringTag, { value: "Module" }));
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const { addImpl: A0, bincountImpl: Wc, bincountReduceImpl: F0, bitwiseAndImpl: D0, castImpl: O0, ceilImpl: P0, concatImpl: _0, equalImpl: B0, expImpl: L0, expm1Impl: M0, floorImpl: U0, gatherNdImpl: V0, gatherV2Impl: W0, greaterImpl: G0, greaterEqualImpl: z0, lessImpl: H0, lessEqualImpl: X0, linSpaceImpl: j0, logImpl: q0, maxImpl: K0, maximumImpl: Y0, minimumImpl: Q0, multiplyImpl: Z0, negImpl: J0, notEqualImpl: ew, prodImpl: tw, raggedGatherImpl: nw, raggedRangeImpl: rw, raggedTensorToTensorImpl: sw, rangeImpl: ow, rsqrtImpl: iw, scatterImpl: aw, sigmoidImpl: cw, simpleAbsImpl: Gc, sliceImpl: lw, sparseFillEmptyRowsImpl: uw, sparseReshapeImpl: dw, sparseSegmentReductionImpl: zc, sqrtImpl: hw, staticRegexReplaceImpl: fw, stridedSliceImpl: pw, stringNGramsImpl: mw, stringSplitImpl: gw, stringToHashBucketFastImpl: xw, subImpl: ww, tileImpl: Cw, topKImpl: bw, transposeImpl: oo, uniqueImpl: yw } = k0;
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Hc(n, e) {
  return ["x", "y", "z", "w", "u", "v"].slice(0, e).map((t) => `${n}.${t}`);
}
function $e(n, e) {
  return e === 1 ? [n] : Hc(n, e);
}
function $w(n, e) {
  if (n === 1)
    return "rc";
  let t = "";
  for (let r = 0; r < n; r++)
    t += e[r], r < n - 1 && (t += ",");
  return t;
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class vw {
  constructor(e) {
    if (this.variableNames = ["A"], this.packedInputs = !1, this.packedOutput = !0, this.outputShape = e, this.rank = e.length, this.enableShapeUniforms = Ce(this.outputShape.length), this.rank === 0)
      this.userCode = `
        void main() {
          setOutput(vec4(getA(), 0., 0., 0.));
        }
      `;
    else {
      const t = $e("rc", this.rank), r = K(this.rank), s = this.getOutOfBoundsCondition(t), o = this.getSetup(t), i = this.getOutput(t);
      this.userCode = `
        void main() {
          ${r} rc = getOutputCoords();

          if(${s}) {
            setOutput(vec4(0));
          } else {
            ${o}

            setOutput(vec4(${i}));
          }
        }
      `;
    }
  }
  getSourceCoordsArr(e) {
    const t = [];
    for (let r = 0; r <= 1; r++)
      for (let s = 0; s <= 1; s++) {
        let o = `${r === 0 ? "r" : "rp1"}, ${s === 0 ? "c" : "cp1"}`;
        for (let i = 2; i < this.rank; i++)
          o = `${e[e.length - 1 - i]},` + o;
        t.push(o);
      }
    return t;
  }
  getOutOfBoundsCondition(e) {
    if (this.rank === 1)
      return `rc > ${this.enableShapeUniforms ? "outShape" : this.outputShape[0]}`;
    let t = "";
    for (let r = this.rank - 2; r < this.rank; r++)
      t += `${e[r]} >= ${this.enableShapeUniforms ? `outShape[${r}]` : this.outputShape[r]}`, r < this.rank - 1 && (t += "||");
    return t;
  }
  getSetup(e) {
    if (this.rank === 1)
      return "";
    const t = e.slice(-2), r = this.enableShapeUniforms ? `outShape[${this.rank} - 1]` : this.outputShape[this.rank - 1], s = this.enableShapeUniforms ? `outShape[${this.rank} - 2]` : this.outputShape[this.rank - 2];
    return `
      int r = ${t[0]};
      int c = ${t[1]};
      int rp1 = r + 1;
      int cp1 = c + 1;

      bool cEdge = cp1 >= ${r};
      bool rEdge = rp1 >= ${s};
    `;
  }
  getOutput(e) {
    const t = this.getSourceCoordsArr(e);
    return this.rank === 1 ? `getA(rc), (rc + 1 >= ${this.enableShapeUniforms ? "outShape" : this.outputShape[0]} ? 0. : getA(rc + 1)), 0, 0` : `getA(${t[0]}),
            cEdge ? 0. : getA(${t[1]}),
            rEdge ? 0. : getA(${t[2]}),
            rEdge || cEdge ? 0. : getA(${t[3]})`;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Xc {
  constructor(e, t) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !0, this.customUniforms = [{ name: "inputShape", type: "ivec3" }], this.outputShape = e, this.enableShapeUniforms = Ce(this.outputShape.length);
    let r = "";
    for (let s = 0; s < 4; s++) {
      let o = "thisRC = rc;";
      s % 2 === 1 && (o += "thisRC.z += 1;"), s > 1 && (o += "thisRC.y += 1;"), r += `
        ${o}
        ${s > 0 ? "if(thisRC.y < rows && thisRC.z < cols){" : ""}
          int flatIndex = getFlatIndex(thisRC);

          ivec3 inputRC = inputCoordsFromReshapedOutCoords(flatIndex);
          vec2 inputRCInnerDims = vec2(float(inputRC.y),float(inputRC.z));

          result[${s}] =
            getChannel(getA(inputRC.x, inputRC.y, inputRC.z), inputRCInnerDims);
        ${s > 0 ? "}" : ""}
      `;
    }
    this.userCode = `
      ${Iw(t, this.enableShapeUniforms)}
      ${this.enableShapeUniforms ? ro() : no(e)}

      void main() {
        ivec3 rc = getOutputCoords();

        vec4 result = vec4(0.);

        ivec3 thisRC;
        int rows = ${this.enableShapeUniforms ? "outShape[1]" : e[1]};
        int cols = ${this.enableShapeUniforms ? "outShape[2]" : e[2]};

        ${r}

        setOutput(result);
      }
    `;
  }
}
function Iw(n, e) {
  return `
    ivec3 inputCoordsFromReshapedOutCoords(int index) {
      ${e ? xg(["r", "c", "d"], "inputShape") : Zt(["r", "c", "d"], n)}
      return ivec3(r, c, d);
    }
  `;
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Sw {
  constructor(e) {
    this.gpgpu = e, this.numUsedTextures = 0, this.numFreeTextures = 0, this._numBytesAllocated = 0, this._numBytesFree = 0, this.freeTextures = {}, this.usedTextures = {}, this.logEnabled = !1;
  }
  acquireTexture(e, t, r) {
    const s = ti(t, r), o = ni(e, s, r);
    o in this.freeTextures || (this.freeTextures[o] = []), o in this.usedTextures || (this.usedTextures[o] = []);
    const i = ei(e, s, this.gpgpu.gl, this.gpgpu.textureConfig, r);
    if (this.freeTextures[o].length > 0) {
      this.numFreeTextures--, this.numUsedTextures++, this._numBytesFree -= i, this.log();
      const c = this.freeTextures[o].pop();
      return this.usedTextures[o].push(c), c;
    }
    let a;
    return s === pe.PACKED_2X2_FLOAT32 ? a = this.gpgpu.createPackedMatrixTexture(e[0], e[1]) : s === pe.PACKED_2X2_FLOAT16 ? a = this.gpgpu.createFloat16PackedMatrixTexture(e[0], e[1]) : s === pe.UNPACKED_FLOAT32 ? a = this.gpgpu.createFloat32MatrixTexture(e[0], e[1]) : s === pe.UNPACKED_FLOAT16 ? a = this.gpgpu.createFloat16MatrixTexture(e[0], e[1]) : s === pe.PACKED_4X1_UNSIGNED_BYTE && (a = this.gpgpu.createUnsignedBytesMatrixTexture(e[0], e[1])), this.usedTextures[o].push(a), this.numUsedTextures++, this._numBytesAllocated += i, this.log(), a;
  }
  releaseTexture(e, t, r, s) {
    if (this.freeTextures == null)
      return;
    const o = ti(r, s), i = ni(t, o, s);
    i in this.freeTextures || (this.freeTextures[i] = []);
    const a = ei(t, o, this.gpgpu.gl, this.gpgpu.textureConfig, s), c = E().get("WEBGL_DELETE_TEXTURE_THRESHOLD");
    c !== -1 && this._numBytesAllocated > c ? (this.gpgpu.deleteMatrixTexture(e.texture), this._numBytesAllocated -= a) : (this.freeTextures[i].push(e), this.numFreeTextures++, this._numBytesFree += a), this.numUsedTextures--;
    const l = this.usedTextures[i], u = l && l.indexOf(e);
    if (u == null || u < 0)
      throw new Error("Cannot release a texture that was never provided by this texture manager");
    l[u] = l[l.length - 1], l.pop(), this.log();
  }
  log() {
    if (!this.logEnabled)
      return;
    const e = this.numFreeTextures + this.numUsedTextures;
    console.log("Free/Used", `${this.numFreeTextures} / ${this.numUsedTextures}`, `(${e})`);
    const t = this._numBytesFree / this._numBytesAllocated;
    console.log(`Bytes allocated: ${this._numBytesAllocated}`), console.log(`Bytes unused: ${this._numBytesFree} (${Math.round(100 * t)}%)`);
  }
  get numBytesAllocated() {
    return this._numBytesAllocated;
  }
  get numBytesFree() {
    return this._numBytesFree;
  }
  getNumUsedTextures() {
    return this.numUsedTextures;
  }
  getNumFreeTextures() {
    return this.numFreeTextures;
  }
  dispose() {
    if (this.freeTextures != null) {
      for (const e in this.freeTextures)
        this.freeTextures[e].forEach((t) => {
          this.gpgpu.deleteMatrixTexture(t.texture);
        });
      for (const e in this.usedTextures)
        this.usedTextures[e].forEach((t) => {
          this.gpgpu.deleteMatrixTexture(t.texture);
        });
      this.freeTextures = null, this.usedTextures = null, this.numUsedTextures = 0, this.numFreeTextures = 0, this._numBytesAllocated = 0, this._numBytesFree = 0;
    }
  }
}
function Ew(n, e) {
  const t = n;
  if (e === t.R32F)
    return 4;
  if (e === t.R16F)
    return 2;
  if (e === t.RGBA32F)
    return 16;
  if (e === n.RGBA)
    return 16;
  if (e === t.RGBA16F)
    return 8;
  if (e === t.RGBA8)
    return 4;
  throw new Error(`Unknown internal format ${e}`);
}
function ei(n, e, t, r, s) {
  const o = Rw(e, r);
  let i;
  if (s) {
    const [c, l] = Rn(n[0], n[1]);
    i = c * l;
  } else {
    const [c, l] = er(n[0], n[1]);
    i = c * l;
  }
  const a = Ew(t, o);
  return i * a;
}
function Rw(n, e) {
  switch (n) {
    case pe.PACKED_2X2_FLOAT32:
      return Lc(e);
    case pe.PACKED_2X2_FLOAT16:
      return Mc(e);
    case pe.UNPACKED_FLOAT32:
      return Pc(e);
    case pe.UNPACKED_FLOAT16:
      return _c(e);
    case pe.PACKED_4X1_UNSIGNED_BYTE:
      return Bc(e);
    default:
      throw new Error(`Unknown physical texture type ${n}`);
  }
}
function Tw(n) {
  return E().getBool("WEBGL_RENDER_FLOAT32_ENABLED") ? n ? pe.PACKED_2X2_FLOAT32 : pe.UNPACKED_FLOAT32 : n ? pe.PACKED_2X2_FLOAT16 : pe.UNPACKED_FLOAT16;
}
function ti(n, e) {
  if (n === Pe.UPLOAD)
    return pe.PACKED_2X2_FLOAT32;
  if (n === Pe.RENDER || n == null)
    return Tw(e);
  if (n === Pe.DOWNLOAD || n === Pe.PIXELS)
    return pe.PACKED_4X1_UNSIGNED_BYTE;
  throw new Error(`Unknown logical texture type ${n}`);
}
function ni(n, e, t) {
  return `${n[0]}_${n[1]}_${e}_${t}`;
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ct {
  constructor(e, t) {
    this.variableNames = ["A"], this.outputShape = e, this.enableShapeUniforms = Ce(this.outputShape.length), this.userCode = `
      float unaryOperation(float x) {
        ${t}
      }

      void main() {
        float x = getAAtOutCoords();
        float y = unaryOperation(x);

        setOutput(y);
      }
    `;
  }
}
const je = "if (isnan(x)) return x;", Nw = "return x;", ri = "return abs(x);", kw = "return (x >= 0.0) ? x : (exp(x) - 1.0);", Aw = je + `
  return (x < 0.0) ? 0.0 : x;
`, Fw = je + `
  return (x < 0.0) ? 0.0 : min(6.0, x);
`, vt = "return x;", Dw = "return 1.0 / (1.0 + exp(-1.0 * x));";
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Ow = "return x;", Pw = `
  vec4 result;

  result.r = (x.r >= 0.0) ? x.r : (exp(x.r) - 1.0);
  result.g = (x.g >= 0.0) ? x.g : (exp(x.g) - 1.0);
  result.b = (x.b >= 0.0) ? x.b : (exp(x.b) - 1.0);
  result.a = (x.a >= 0.0) ? x.a : (exp(x.a) - 1.0);

  return result;
`, _w = `
  vec4 result = x * vec4(greaterThanEqual(x, vec4(0.0)));
  bvec4 isNaN = isnan(x);

  result.r = isNaN.r ? x.r : result.r;
  result.g = isNaN.g ? x.g : result.g;
  result.b = isNaN.b ? x.b : result.b;
  result.a = isNaN.a ? x.a : result.a;

  return result;
`, Bw = `
  vec4 result = min(x, vec4(6.)) * vec4(greaterThanEqual(x, vec4(0.0)));
  bvec4 isNaN = isnan(x);

  result.r = isNaN.r ? x.r : result.r;
  result.g = isNaN.g ? x.g : result.g;
  result.b = isNaN.b ? x.b : result.b;
  result.a = isNaN.a ? x.a : result.a;

  return result;
`, Lw = "return 1.0 / (1.0 + exp(-1.0 * x));";
class St {
  constructor(e, t) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !0, this.outputShape = e, this.enableShapeUniforms = Ce(this.outputShape.length), this.userCode = `
      vec4 unaryOperation(vec4 x) {
        ${t}
      }

      void main() {
        vec4 x = getAAtOutCoords();
        vec4 y = unaryOperation(x);

        setOutput(y);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Mw {
  constructor(e) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !1, this.outputShape = e, this.enableShapeUniforms = Ce(this.outputShape.length);
    const t = e.length, r = $e("rc", t), s = K(t), o = $w(t, r), i = r.slice(-2), a = t <= 1 ? "rc" : `vec2(${i.join(",")})`;
    this.userCode = `
      void main() {
        ${s} rc = getOutputCoords();
        vec4 packedInput = getA(${o});

        setOutput(getChannel(packedInput, ${a}));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Uw = _p, Vw = 1e-7, Ww = 1e-4, fr = {};
function Gw(n) {
  return n in fr || (fr[n] = {}), fr[n];
}
const zw = E().getNumber("CPU_HANDOFF_SIZE_THRESHOLD"), Hw = 600;
function Xw() {
  return E().global.screen == null ? 1024 : E().global.screen.height * E().global.screen.width * window.devicePixelRatio * Hw / 1024 / 1024;
}
class Vr extends $i {
  nextDataId() {
    return Vr.nextDataId++;
  }
  constructor(e) {
    if (super(), this.pendingRead = /* @__PURE__ */ new WeakMap(), this.pendingDisposal = /* @__PURE__ */ new WeakSet(), this.dataRefCount = /* @__PURE__ */ new WeakMap(), this.numBytesInGPU = 0, this.uploadWaitMs = 0, this.downloadWaitMs = 0, this.lastGlFlushTime = 0, this.warnedAboutMemory = !1, this.pendingDeletes = 0, this.disposed = !1, !E().getBool("HAS_WEBGL"))
      throw new Error("WebGL is not supported on this device");
    let t;
    if (e != null) {
      if (e instanceof ss)
        t = e;
      else {
        const r = Ze(E().getNumber("WEBGL_VERSION"), e);
        t = new ss(r);
      }
      this.binaryCache = {}, this.gpgpuCreatedLocally = !1;
    } else {
      const r = Ze(E().getNumber("WEBGL_VERSION"));
      t = new ss(r), this.binaryCache = Gw(E().getNumber("WEBGL_VERSION")), this.gpgpuCreatedLocally = !0;
    }
    this.gpgpu = t, this.canvas = this.gpgpu.gl.canvas, this.textureManager = new Sw(this.gpgpu), this.numMBBeforeWarning = Xw(), this.texData = new Fl(this, $t());
  }
  numDataIds() {
    return this.texData.numDataIds() - this.pendingDeletes;
  }
  // Writes a new entry to the data store with a WebGL texture, and registers it
  // to the texture manager.
  writeTexture(e, t, r, s, o, i) {
    const a = this.makeTensorInfo(t, r), c = this.texData.get(a.dataId);
    c.isPacked = !1, c.texture = { texture: e, texShape: [s, o] }, c.texShape = [s, o];
    const l = dr(t), u = new Ko(l, !1, i), d = this.runWebGLProgram(u, [a], r, [[s, o]]);
    return d.shape = t, c.texture = null, this.disposeIntermediateTensorInfo(a), d.dataId;
  }
  write(e, t, r) {
    if ((E().getBool("WEBGL_CHECK_NUMERICAL_PROBLEMS") || E().getBool("DEBUG")) && this.checkNumericalProblems(e), r === "complex64" && e != null)
      throw new Error("Cannot write to a complex64 dtype. Please use tf.complex(real, imag).");
    const s = { id: this.nextDataId() };
    return this.texData.set(s, { shape: t, dtype: r, values: e, usage: Pe.UPLOAD, refCount: 1 }), s;
  }
  /** Return refCount of a `TensorData`. */
  refCount(e) {
    return this.texData.has(e) ? this.texData.get(e).refCount : 0;
  }
  /** Increase refCount of a `TextureData`. */
  incRef(e) {
    const t = this.texData.get(e);
    t.refCount++;
  }
  /** Decrease refCount of a `TextureData`. */
  decRef(e) {
    if (this.texData.has(e)) {
      const t = this.texData.get(e);
      t.refCount--;
    }
  }
  move(e, t, r, s, o) {
    if (E().getBool("DEBUG") && this.checkNumericalProblems(t), s === "complex64")
      throw new Error("Cannot write to a complex64 dtype. Please use tf.complex(real, imag).");
    this.texData.set(e, { shape: r, dtype: s, values: t, usage: Pe.UPLOAD, refCount: o });
  }
  disposeIntermediateTensorInfo(e) {
    this.disposeData(e.dataId);
  }
  readSync(e) {
    const t = this.texData.get(e), { values: r, dtype: s, complexTensorInfos: o, slice: i, shape: a, isPacked: c } = t;
    if (i != null) {
      let h;
      c ? h = new St(a, vt) : h = new ct(a, vt);
      const f = this.runWebGLProgram(h, [{ dataId: e, shape: a, dtype: s }], s), m = this.readSync(f.dataId);
      return this.disposeIntermediateTensorInfo(f), m;
    }
    if (r != null)
      return this.convertAndCacheOnCPU(e);
    if (s === "string")
      return r;
    const l = this.activeTimers != null;
    let u;
    l && (u = qe());
    let d;
    if (s === "complex64") {
      const h = this.readSync(o.real.dataId), f = this.readSync(o.imag.dataId);
      d = Ss(h, f);
    } else
      d = this.getValuesFromTexture(e);
    return l && (this.downloadWaitMs += qe() - u), this.convertAndCacheOnCPU(e, d);
  }
  async read(e) {
    if (this.pendingRead.has(e)) {
      const m = this.pendingRead.get(e);
      return new Promise((C) => m.push(C));
    }
    const t = this.texData.get(e), { values: r, shape: s, slice: o, dtype: i, complexTensorInfos: a, isPacked: c } = t;
    if (o != null) {
      let m;
      c ? m = new St(s, vt) : m = new ct(s, vt);
      const C = this.runWebGLProgram(m, [{ dataId: e, shape: s, dtype: i }], i), w = this.read(C.dataId);
      return this.disposeIntermediateTensorInfo(C), w;
    }
    if (r != null)
      return this.convertAndCacheOnCPU(e);
    if (E().getBool("DEBUG") && !E().getBool("WEBGL_DOWNLOAD_FLOAT_ENABLED") && E().getNumber("WEBGL_VERSION") === 2)
      throw new Error("tensor.data() with WEBGL_DOWNLOAD_FLOAT_ENABLED=false and WEBGL_VERSION=2 not yet supported.");
    let l = null, u;
    if (i !== "complex64" && E().get("WEBGL_BUFFER_SUPPORTED")) {
      u = this.decode(e);
      const m = this.texData.get(u.dataId);
      l = this.gpgpu.createBufferFromTexture(m.texture.texture, ...cr(s));
    }
    this.pendingRead.set(e, []), i !== "complex64" && await this.gpgpu.createAndWaitForFence();
    let d;
    if (i === "complex64") {
      const m = await Promise.all([
        this.read(a.real.dataId),
        this.read(a.imag.dataId)
      ]), C = m[0], w = m[1];
      d = Ss(C, w);
    } else if (l == null)
      d = this.getValuesFromTexture(e);
    else {
      const m = _(s);
      d = this.gpgpu.downloadFloat32MatrixFromBuffer(l, m);
    }
    if (u != null && this.disposeIntermediateTensorInfo(u), l != null) {
      const m = this.gpgpu.gl;
      B(m, () => m.deleteBuffer(l));
    }
    const h = this.convertAndCacheOnCPU(e, d), f = this.pendingRead.get(e);
    return this.pendingRead.delete(e), f.forEach((m) => m(h)), this.pendingDisposal.has(e) && (this.pendingDisposal.delete(e), this.disposeData(e) && $t().removeDataId(e, this), this.pendingDeletes--), h;
  }
  /**
   * Read tensor to a new texture that is densely packed for ease of use.
   * @param dataId The source tensor.
   * @param options
   *     customTexShape: Optional. If set, will use the user defined texture
   *     shape to create the texture.
   */
  readToGPU(e, t = {}) {
    const r = this.texData.get(e), { values: s, shape: o, slice: i, dtype: a, isPacked: c, texture: l } = r;
    if (a === "complex64")
      throw new Error("Does not support reading texture for complex64 dtype.");
    if (i != null) {
      let f;
      c ? f = new St(o, vt) : f = new ct(o, vt);
      const m = this.runWebGLProgram(f, [{ dataId: e, shape: o, dtype: a }], a), C = this.readToGPU(m, t);
      return this.disposeIntermediateTensorInfo(m), C;
    }
    if (l == null)
      throw s != null ? new Error("Data is not on GPU but on CPU.") : new Error("There is no data on GPU or CPU.");
    const u = this.decode(e, t.customTexShape), d = $t().makeTensorFromTensorInfo(u), h = this.texData.get(u.dataId);
    return Object.assign({ tensorRef: d }, h.texture);
  }
  bufferSync(e) {
    const t = this.readSync(e.dataId);
    if (e.dtype === "string")
      try {
        const r = t.map((s) => xn(s));
        return xe(e.shape, e.dtype, r);
      } catch {
        throw new Error("Failed to decode encoded string bytes into utf-8");
      }
    return xe(e.shape, e.dtype, t);
  }
  checkNumericalProblems(e) {
    if (e != null)
      for (let t = 0; t < e.length; t++) {
        const r = e[t];
        if (!zm(r))
          throw E().getBool("WEBGL_RENDER_FLOAT32_CAPABLE") ? Error(`The value ${r} cannot be represented with your current settings. Consider enabling float32 rendering: 'tf.env().set('WEBGL_RENDER_FLOAT32_ENABLED', true);'`) : Error(`The value ${r} cannot be represented on this device.`);
      }
  }
  getValuesFromTexture(e) {
    const { shape: t, dtype: r, isPacked: s } = this.texData.get(e), o = _(t);
    if (E().getBool("WEBGL_DOWNLOAD_FLOAT_ENABLED")) {
      const h = this.decode(e), f = this.texData.get(h.dataId), m = this.gpgpu.downloadMatrixFromPackedTexture(f.texture.texture, ...cr(t)).subarray(0, o);
      return this.disposeIntermediateTensorInfo(h), m;
    }
    const i = E().getBool("WEBGL_PACK") && s === !0, a = i ? dr(t) : t, c = i ? new ix(a) : new ox(a), l = this.runWebGLProgram(c, [{ shape: a, dtype: r, dataId: e }], "float32"), u = this.texData.get(l.dataId), d = this.gpgpu.downloadByteEncodedFloatMatrixFromOutputTexture(u.texture.texture, u.texShape[0], u.texShape[1]).subarray(0, o);
    return this.disposeIntermediateTensorInfo(l), d;
  }
  timerAvailable() {
    return E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_RELIABLE") > 0;
  }
  time(e) {
    const t = this.activeTimers, r = [];
    let s = !1;
    this.programTimersStack == null ? (this.programTimersStack = r, s = !0) : this.activeTimers.push(r), this.activeTimers = r, e();
    const o = Vt(this.activeTimers.map((c) => c.query)).filter((c) => c != null), i = Vt(this.activeTimers.map((c) => c.name)).filter((c) => c != null);
    this.activeTimers = t, s && (this.programTimersStack = null);
    const a = {
      uploadWaitMs: this.uploadWaitMs,
      downloadWaitMs: this.downloadWaitMs,
      kernelMs: null,
      wallMs: null
      // will be filled by the engine
    };
    return (async () => {
      if (E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_RELIABLE") > 0) {
        const c = await Promise.all(o);
        a.kernelMs = Dl(c), a.getExtraProfileInfo = () => c.map((l, u) => ({ name: i[u], ms: l })).map((l) => `${l.name}: ${l.ms}`).join(", ");
      } else
        a.kernelMs = {
          error: "WebGL query timers are not supported in this environment."
        };
      return this.uploadWaitMs = 0, this.downloadWaitMs = 0, a;
    })();
  }
  memory() {
    return {
      unreliable: !1,
      numBytesInGPU: this.numBytesInGPU,
      numBytesInGPUAllocated: this.textureManager.numBytesAllocated,
      numBytesInGPUFree: this.textureManager.numBytesFree
    };
  }
  startTimer() {
    return E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_RELIABLE") > 0 ? this.gpgpu.beginQuery() : { startMs: qe(), endMs: null };
  }
  endTimer(e) {
    return E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_RELIABLE") > 0 ? (this.gpgpu.endQuery(), e) : (e.endMs = qe(), e);
  }
  async getQueryTime(e) {
    if (E().getNumber("WEBGL_DISJOINT_QUERY_TIMER_EXTENSION_RELIABLE") > 0)
      return this.gpgpu.waitForQueryAndGetTime(e);
    const t = e;
    return t.endMs - t.startMs;
  }
  /**
   * Decrease the RefCount on the dataId and dispose the memory if the dataId
   * has 0 refCount. If there are pending read on the data, the disposal would
   * added to the pending delete queue. Return true if the dataId is removed
   * from backend or the backend does not contain the dataId, false if the
   * dataId is not removed. Memory may or may not be released even when dataId
   * is removed, which also depends on dataRefCount, see `releaseGPU`.
   * @param dataId
   * @oaram force Optional, remove the data regardless of refCount
   */
  disposeData(e, t = !1) {
    if (this.pendingDisposal.has(e))
      return !1;
    if (!this.texData.has(e))
      return !0;
    if (t ? this.texData.get(e).refCount = 0 : this.texData.get(e).refCount--, !t && this.texData.get(e).refCount > 0)
      return !1;
    if (this.pendingRead.has(e))
      return this.pendingDisposal.add(e), this.pendingDeletes++, !1;
    this.releaseGPUData(e);
    const { complexTensorInfos: r } = this.texData.get(e);
    return r != null && (this.disposeData(r.real.dataId, t), this.disposeData(r.imag.dataId, t)), this.texData.delete(e), !0;
  }
  releaseGPUData(e) {
    const { texture: t, dtype: r, texShape: s, usage: o, isPacked: i, slice: a } = this.texData.get(e), c = a && a.origDataId || e, l = this.dataRefCount.get(c);
    l > 1 ? this.dataRefCount.set(c, l - 1) : (this.dataRefCount.delete(c), t != null && (this.numBytesInGPU -= this.computeBytes(s, r), this.textureManager.releaseTexture(t, s, o, i)));
    const u = this.texData.get(e);
    u.texture = null, u.texShape = null, u.isPacked = !1, u.slice = null;
  }
  getTexture(e) {
    return this.uploadToGPU(e), this.texData.get(e).texture.texture;
  }
  /**
   * Returns internal information for the specific data bucket. Used in unit
   * tests.
   */
  getDataInfo(e) {
    return this.texData.get(e);
  }
  /*
  Tests whether all the inputs to an op are small and on the CPU. This heuristic
  determines when it would be faster to execute a kernel on the CPU. WebGL
  kernels opt into running this check and forwarding when appropriate.
  TODO(https://github.com/tensorflow/tfjs/issues/872): Develop a more
  sustainable strategy for optimizing backend execution of ops.
   */
  shouldExecuteOnCPU(e, t = zw) {
    return E().getBool("WEBGL_CPU_FORWARD") && e.every((r) => this.texData.get(r.dataId).texture == null && _(r.shape) < t);
  }
  getGPGPUContext() {
    return this.gpgpu;
  }
  where(e) {
    Qe("tf.where() in webgl locks the UI thread. Call tf.whereAsync() instead");
    const t = e.dataSync();
    return Uw(e.shape, t);
  }
  packedUnaryOp(e, t, r) {
    const s = new St(e.shape, t), o = this.compileAndRun(s, [e], r);
    return $t().makeTensorFromTensorInfo(o);
  }
  // TODO(msoulanille) remove this once the backend has been modularized
  // a copy is needed here to break a circular dependency.
  // Also remove the op from unary_op.
  abs(e) {
    if (this.shouldExecuteOnCPU([e]) && e.dtype !== "complex64") {
      const s = Gc(this.texData.get(e.dataId).values);
      return this.makeOutput(e.shape, e.dtype, s);
    }
    if (E().getBool("WEBGL_PACK_UNARY_OPERATIONS"))
      return this.packedUnaryOp(e, ri, e.dtype);
    const t = new ct(e.shape, ri), r = this.compileAndRun(t, [e]);
    return $t().makeTensorFromTensorInfo(r);
  }
  makeTensorInfo(e, t, r) {
    let s;
    if (t === "string" && r != null && r.length > 0 && Fr(r[0])) {
      const o = r.map((i) => Lt(i));
      s = this.write(o, e, t);
    } else
      s = this.write(r, e, t);
    return this.texData.get(s).usage = null, { dataId: s, shape: e, dtype: t };
  }
  makeOutput(e, t, r) {
    return $t().makeTensorFromTensorInfo(this.makeTensorInfo(e, t, r), this);
  }
  unpackTensor(e) {
    const t = new Mw(e.shape);
    return this.runWebGLProgram(t, [e], e.dtype);
  }
  packTensor(e) {
    const t = new vw(e.shape);
    return this.runWebGLProgram(t, [e], e.dtype, null, !0);
  }
  packedReshape(e, t) {
    const r = [
      yn(e.shape),
      ...$n(e.shape)
    ], s = {
      dtype: e.dtype,
      shape: r,
      dataId: e.dataId
    }, o = [
      yn(t),
      ...$n(t)
    ], i = new Xc(o, r), a = !0, c = [r], l = this.runWebGLProgram(i, [s], e.dtype, c, a);
    return { dataId: l.dataId, shape: t, dtype: l.dtype };
  }
  decode(e, t) {
    const r = this.texData.get(e), { isPacked: s, shape: o, dtype: i } = r;
    if (t != null) {
      const h = _(o), f = t[0] * t[1] * 4;
      O(h <= f, () => "customTexShape is too small. Row * Column * 4 should be equal or larger than the size of the tensor data.");
    }
    const a = dr(o);
    let c;
    s ? c = new sx(a) : c = new rx(a);
    const l = !0, u = [t ?? cr(a)], d = this.runWebGLProgram(c, [{ shape: a, dtype: i, dataId: e }], i, u, l, t);
    return { dtype: i, shape: o, dataId: d.dataId };
  }
  runWebGLProgram(e, t, r, s, o = !1, i) {
    const a = this.makeTensorInfo(e.outputShape, r), c = this.texData.get(a.dataId);
    if (e.packedOutput && (c.isPacked = !0), e.outPackingScheme === Xn.DENSE) {
      const x = i ?? cr(e.outputShape);
      c.texShape = x.map((y) => y * 2);
    }
    if (e.outTexUsage != null && (c.usage = e.outTexUsage), _(a.shape) === 0)
      return c.values = Ut(a.dtype, 0), a;
    const l = [], u = t.map((x) => {
      if (x.dtype === "complex64")
        throw new Error("GPGPUProgram does not support complex64 input. For complex64 dtypes, please separate the program into real and imaginary parts.");
      let y = this.texData.get(x.dataId);
      if (y.texture == null) {
        if (!e.packedInputs && _(x.shape) <= E().getNumber("WEBGL_SIZE_UPLOAD_UNIFORM"))
          return {
            shape: x.shape,
            texData: null,
            isUniform: !0,
            uniformValues: y.values
          };
        e.packedInputs && (y.isPacked = !0, y.shape = x.shape);
      }
      if (this.uploadToGPU(x.dataId), !!y.isPacked != !!e.packedInputs)
        x = y.isPacked ? this.unpackTensor(x) : this.packTensor(x), l.push(x), y = this.texData.get(x.dataId);
      else if (y.isPacked && !Rr(y.shape, x.shape)) {
        const v = x, I = x.shape;
        x.shape = y.shape, x = this.packedReshape(x, I), l.push(x), y = this.texData.get(x.dataId), v.shape = I;
      }
      return { shape: x.shape, texData: y, isUniform: !1 };
    });
    this.uploadToGPU(a.dataId);
    const d = { shape: a.shape, texData: c, isUniform: !1 }, h = nx(e, u, d), f = this.getAndSaveBinary(h, () => ex(this.gpgpu, e, u, d)), m = this.activeTimers != null;
    let C;
    m && (C = this.startTimer()), E().get("ENGINE_COMPILE_ONLY") || tx(this.gpgpu, f, u, d, s), l.forEach((x) => this.disposeIntermediateTensorInfo(x)), m && (C = this.endTimer(C), this.activeTimers.push({ name: e.constructor.name, query: this.getQueryTime(C) }));
    const w = E().get("WEBGL_FLUSH_THRESHOLD");
    if (w > 0) {
      const x = qe();
      x - this.lastGlFlushTime > w && (this.gpgpu.gl.flush(), this.lastGlFlushTime = x);
    }
    if (!E().getBool("WEBGL_LAZILY_UNPACK") && c.isPacked && o === !1) {
      const x = this.unpackTensor(a);
      return this.disposeIntermediateTensorInfo(a), x;
    }
    return a;
  }
  compileAndRun(e, t, r, s, o = !1) {
    return r = r || t[0].dtype, this.runWebGLProgram(e, t, r, s, o);
  }
  getAndSaveBinary(e, t) {
    return e in this.binaryCache || (this.binaryCache[e] = t()), this.binaryCache[e];
  }
  getTextureManager() {
    return this.textureManager;
  }
  dispose() {
    this.disposed || (E().getBool("IS_TEST") || Object.keys(this.binaryCache).forEach((t) => {
      this.gpgpu.deleteProgram(this.binaryCache[t].webGLProgram), delete this.binaryCache[t];
    }), this.textureManager.dispose(), this.canvas != null && typeof HTMLCanvasElement < "u" && this.canvas instanceof HTMLCanvasElement ? this.canvas.remove() : this.canvas = null, this.gpgpuCreatedLocally && (this.gpgpu.program = null, this.gpgpu.dispose()), this.disposed = !0);
  }
  floatPrecision() {
    return this.floatPrecisionValue == null && (this.floatPrecisionValue = se(() => {
      if (!E().get("WEBGL_RENDER_FLOAT32_ENABLED")) {
        const e = E().getBool("DEBUG");
        E().set("DEBUG", !1);
        const t = this.abs(Tt(1e-8)).dataSync()[0];
        if (E().set("DEBUG", e), t > 0)
          return 32;
      }
      return 16;
    })), this.floatPrecisionValue;
  }
  /** Returns the smallest representable number.  */
  epsilon() {
    return this.floatPrecision() === 32 ? Vw : Ww;
  }
  uploadToGPU(e) {
    const t = this.texData.get(e), { shape: r, dtype: s, values: o, texture: i, usage: a, isPacked: c } = t;
    if (i != null)
      return;
    const l = this.activeTimers != null;
    let u;
    l && (u = qe());
    let d = t.texShape;
    if (d == null && (d = cg(r, c), t.texShape = d), o != null) {
      const h = dr(r);
      let f, m = d[1], C = d[0];
      const w = o instanceof Uint8Array || o instanceof Uint8ClampedArray;
      (c || !w) && ([m, C] = Rn(d[0], d[1])), c ? f = new cx(h, w) : f = new Ko(h, w);
      const x = w ? [C, m] : d, y = this.makeTensorInfo(x, s), v = this.texData.get(y.dataId);
      w ? v.usage = Pe.PIXELS : v.usage = Pe.UPLOAD, v.texShape = x, this.gpgpu.uploadDenseMatrixToTexture(this.getTexture(y.dataId), m, C, o);
      const I = [[C, m]], A = this.runWebGLProgram(f, [y], s, I, !0), F = this.texData.get(A.dataId);
      t.texShape = F.texShape, t.isPacked = F.isPacked, t.usage = F.usage, E().get("ENGINE_COMPILE_ONLY") ? this.disposeData(A.dataId) : (t.texture = F.texture, t.values = null, this.texData.delete(A.dataId)), this.disposeIntermediateTensorInfo(y), l && (this.uploadWaitMs += qe() - u);
    } else {
      const h = this.acquireTexture(d, a, s, c);
      t.texture = h;
    }
  }
  convertAndCacheOnCPU(e, t) {
    const r = this.texData.get(e), { dtype: s } = r;
    return t != null && (r.values = jw(t, s)), r.values;
  }
  acquireTexture(e, t, r, s) {
    if (this.numBytesInGPU += this.computeBytes(e, r), !this.warnedAboutMemory && this.numBytesInGPU > this.numMBBeforeWarning * 1024 * 1024) {
      const o = (this.numBytesInGPU / 1024 / 1024).toFixed(2);
      this.warnedAboutMemory = !0, console.warn(`High memory usage in GPU: ${o} MB, most likely due to a memory leak`);
    }
    return this.textureManager.acquireTexture(e, t, s);
  }
  computeBytes(e, t) {
    return e[0] * e[1] * br(t);
  }
  checkCompileCompletion() {
    for (const [, e] of Object.entries(this.binaryCache))
      this.checkCompletion_(e);
  }
  async checkCompileCompletionAsync() {
    const e = [];
    if (this.gpgpu.parallelCompilationExtension) {
      for (const [, t] of Object.entries(this.binaryCache))
        e.push(this.checkCompletionAsync_(t));
      return Promise.all(e);
    } else {
      for (const [, t] of Object.entries(this.binaryCache)) {
        const r = new Promise((s) => {
          try {
            this.checkCompletion_(t), s(!0);
          } catch (o) {
            throw o;
          }
        });
        e.push(r);
      }
      return Promise.all(e);
    }
  }
  async checkCompletionAsync_(e) {
    return this.gpgpu.gl.getProgramParameter(e.webGLProgram, this.gpgpu.parallelCompilationExtension.COMPLETION_STATUS_KHR) ? this.checkCompletion_(e) : (await Im(), this.checkCompletionAsync_(e));
  }
  checkCompletion_(e) {
    if (this.gpgpu.gl.getProgramParameter(e.webGLProgram, this.gpgpu.gl.LINK_STATUS) === !1)
      throw console.log(this.gpgpu.gl.getProgramInfoLog(e.webGLProgram)), this.gpgpu.gl.getShaderParameter(e.fragmentShader, this.gpgpu.gl.COMPILE_STATUS) === !1 ? (Nc(e.source, this.gpgpu.gl.getShaderInfoLog(e.fragmentShader)), new Error("Failed to compile fragment shader.")) : new Error("Failed to link vertex and fragment shaders.");
    return !0;
  }
  getUniformLocations() {
    for (const e of Object.values(this.binaryCache)) {
      this.gpgpu.buildVao(e.webGLProgram);
      const { variablesLocations: t, customUniformLocations: r, infLoc: s, nanLoc: o, outShapeLocation: i, outShapeStridesLocation: a, outTexShapeLocation: c } = Oc(this.gpgpu, e.program, e.webGLProgram);
      e.variablesLocations = t, e.customUniformLocations = r, e.infLoc = s, e.nanLoc = o, e.outShapeLocation = i, e.outShapeStridesLocation = a, e.outTexShapeLocation = c;
    }
  }
  /**
   * Create a TF.js tensor out of an existing WebGL texture. A new texture will
   * be created.
   */
  createTensorFromGPUData(e, t, r) {
    e.channels = e.channels || "RGBA";
    const { texture: s, height: o, width: i, channels: a } = e, c = $t().backend;
    if (!c.gpgpu.gl.isTexture(s))
      throw new Error("The texture is invalid. Also, please make sure the texture and the TFJS WebGL backend are using the same canvas. If you want to use your own custom canvas, you have to create and use the custom TFJS WebGL backend created from the canvas through 'new tf.MathBackendWebGL(customCanvas)'.");
    const l = c.writeTexture(s, t, r, o, i, a);
    return $t().makeTensorFromDataId(l, t, r, c);
  }
}
Vr.nextDataId = 0;
function jw(n, e) {
  if (e === "float32" || e === "complex64")
    return n;
  if (e === "int32" || e === "bool") {
    const t = e === "int32" ? new Int32Array(n.length) : new Uint8Array(n.length);
    for (let r = 0; r < t.length; ++r)
      t[r] = Math.round(n[r]);
    return t;
  } else
    throw new Error(`Unknown dtype ${e}`);
}
/**
 * @license
 * Copyright 2020 Google Inc. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
ga() && jf(
  "webgl",
  () => new Vr(),
  2
  /* priority */
);
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const io = `
  if (isnan(a)) return a;
  if (isnan(b)) return b;
`;
class Xt {
  constructor(e, t, r) {
    this.variableNames = ["A", "B"], this.outputShape = ve(t, r), this.enableShapeUniforms = Ce(this.outputShape.length), this.userCode = `
      float binaryOperation(float a, float b) {
        ${e}
      }

      void main() {
        float a = getAAtOutCoords();
        float b = getBAtOutCoords();
        setOutput(binaryOperation(a, b));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const en = `
  result.r = isNaN.r ? NAN : result.r;
  result.g = isNaN.g ? NAN : result.g;
  result.b = isNaN.b ? NAN : result.b;
  result.a = isNaN.a ? NAN : result.a;
`;
class Fn {
  constructor(e, t, r, s = !1) {
    this.variableNames = ["A", "B"], this.supportsBroadcasting = !0, this.packedInputs = !0, this.packedOutput = !0, this.outputShape = ve(t, r);
    const o = this.outputShape.length;
    this.enableShapeUniforms = Ce(o);
    let i = "";
    if (s)
      if (o === 0 || _(this.outputShape) === 1)
        i = `
          result.y = 0.;
          result.z = 0.;
          result.w = 0.;
        `;
      else if (i = `
          ${K(o)} coords = getOutputCoords();
        `, o === 1)
        this.enableShapeUniforms ? i += `
            result.y = (coords + 1) >= outShape ? 0. : result.y;
            result.z = 0.;
            result.w = 0.;
          ` : i += `
            result.y = (coords + 1) >= ${this.outputShape[0]} ? 0. : result.y;
            result.z = 0.;
            result.w = 0.;
          `;
      else {
        const c = $e("coords", o);
        this.enableShapeUniforms ? i += `
            bool nextRowOutOfBounds =
              (${c[o - 2]} + 1) >= outShape[${o} - 2];
            bool nextColOutOfBounds =
              (${c[o - 1]} + 1) >= outShape[${o} - 1];
            result.y = nextColOutOfBounds ? 0. : result.y;
            result.z = nextRowOutOfBounds ? 0. : result.z;
            result.w = nextColOutOfBounds || nextRowOutOfBounds ? 0. : result.w;
          ` : i += `
            bool nextRowOutOfBounds =
              (${c[o - 2]} + 1) >= ${this.outputShape[o - 2]};
            bool nextColOutOfBounds =
              (${c[o - 1]} + 1) >= ${this.outputShape[o - 1]};
            result.y = nextColOutOfBounds ? 0. : result.y;
            result.z = nextRowOutOfBounds ? 0. : result.z;
            result.w = nextColOutOfBounds || nextRowOutOfBounds ? 0. : result.w;
          `;
      }
    this.userCode = `
      vec4 binaryOperation(vec4 a, vec4 b) {
        ${e}
      }

      void main() {
        vec4 a = getAAtOutCoords();
        vec4 b = getBAtOutCoords();

        vec4 result = binaryOperation(a, b);
        ${i}

        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function De(n) {
  const { inputs: e, backend: t } = n, { x: r } = e;
  return t.incRef(r.dataId), { dataId: r.dataId, shape: r.shape, dtype: r.dtype };
}
const qw = {
  kernelName: Bs,
  backendName: "webgl",
  kernelFunc: De
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Nt(n) {
  const { inputs: e, backend: t } = n, { real: r, imag: s } = e, o = t.makeTensorInfo(r.shape, "complex64"), i = t.texData.get(o.dataId), a = De({ inputs: { x: r }, backend: t }), c = De({ inputs: { x: s }, backend: t });
  return i.complexTensorInfos = { real: a, imag: c }, o;
}
const Kw = {
  kernelName: Fi,
  backendName: "webgl",
  kernelFunc: Nt
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const jc = "return (a < 0.) ? b * a : a;", qc = `
  vec4 aLessThanZero = vec4(lessThan(a, vec4(0.)));
  return (aLessThanZero * (b * a)) + ((vec4(1.0) - aLessThanZero) * a);
`;
function Yw(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { alpha: o } = r, i = t.makeTensorInfo([], "float32", vn(o, "float32")), a = E().getBool("WEBGL_PACK_BINARY_OPERATIONS") ? new Fn(qc, s.shape, i.shape) : new Xt(jc, s.shape, i.shape), c = t.runWebGLProgram(a, [s, i], "float32");
  return t.disposeIntermediateTensorInfo(i), c;
}
const Qw = {
  kernelName: Li,
  backendName: "webgl",
  kernelFunc: Yw
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Kc = "return (a < 0.) ? b * a : a;", Yc = `
  vec4 aLessThanZero = vec4(lessThan(a, vec4(0.)));
  return (aLessThanZero * (b * a)) + ((vec4(1.0) - aLessThanZero) * a);
`;
function Zw(n) {
  const { inputs: e, backend: t } = n, { x: r, alpha: s } = e, o = E().getBool("WEBGL_PACK_BINARY_OPERATIONS") ? new Fn(Yc, r.shape, s.shape) : new Xt(Kc, r.shape, s.shape);
  return t.runWebGLProgram(o, [r, s], "float32");
}
const Jw = {
  kernelName: Wi,
  backendName: "webgl",
  kernelFunc: Zw
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Dn = "if (isnan(x)) return x;";
function H({ opSnippet: n, packedOpSnippet: e, cpuKernelImpl: t, dtype: r }) {
  return ({ inputs: s, backend: o }) => {
    const { x: i } = s, a = o, c = r || i.dtype;
    if (a.shouldExecuteOnCPU([i]) && t != null) {
      const d = a.texData.get(i.dataId), h = t(d.values, c);
      return a.makeTensorInfo(i.shape, c, h);
    }
    const l = E().getBool("WEBGL_PACK_UNARY_OPERATIONS") && e != null;
    let u;
    return l ? u = new St(i.shape, e) : u = new ct(i.shape, n), a.runWebGLProgram(u, [i], c);
  };
}
function we({ opSnippet: n, packedOpSnippet: e, checkOutOfBounds: t = !1, supportsComplex: r = !1, cpuKernelImpl: s, dtype: o }) {
  return ({ inputs: i, backend: a }) => {
    const { a: c, b: l } = i, u = a;
    if (r && c.dtype === "complex64") {
      const m = u.texData.get(c.dataId), C = u.texData.get(l.dataId), [w, x] = [
        [m.complexTensorInfos.real, C.complexTensorInfos.real],
        [m.complexTensorInfos.imag, C.complexTensorInfos.imag]
      ].map((v) => {
        const [I, T] = v, A = {
          dataId: I.dataId,
          dtype: I.dtype,
          shape: c.shape
        }, F = {
          dataId: T.dataId,
          dtype: T.dtype,
          shape: l.shape
        }, k = new Xt(n, c.shape, l.shape);
        return u.runWebGLProgram(k, [A, F], dt(I.dtype, T.dtype));
      }), y = Nt({ inputs: { real: w, imag: x }, backend: u });
      return u.disposeIntermediateTensorInfo(w), u.disposeIntermediateTensorInfo(x), y;
    }
    const d = o || dt(c.dtype, l.dtype);
    if ((c.dtype === "string" || l.dtype === "string" || u.shouldExecuteOnCPU([c, l])) && s != null) {
      const m = u.texData.get(c.dataId).values, C = u.texData.get(l.dataId).values, w = c.dtype === "string" ? (
        // tslint:disable-next-line: no-any
        bn(m)
      ) : m, x = c.dtype === "string" ? (
        // tslint:disable-next-line: no-any
        bn(C)
      ) : C, [y, v] = s(c.shape, l.shape, w, x, d), I = u.makeTensorInfo(v, d), T = u.texData.get(I.dataId);
      return T.values = y, I;
    }
    const h = E().getBool("WEBGL_PACK_BINARY_OPERATIONS") && e != null;
    let f;
    return h ? f = new Fn(e, c.shape, l.shape, t) : f = new Xt(n, c.shape, l.shape), u.runWebGLProgram(f, [c, l], d);
  };
}
function jn(n, e = !1) {
  if (n === "linear")
    return e ? Ow : Nw;
  if (n === "relu")
    return e ? _w : Aw;
  if (n === "elu")
    return e ? Pw : kw;
  if (n === "relu6")
    return e ? Bw : Fw;
  if (n === "prelu")
    return e ? Yc : Kc;
  if (n === "leakyrelu")
    return e ? qc : jc;
  if (n === "sigmoid")
    return e ? Lw : Dw;
  throw new Error(`Activation ${n} has not been implemented for the WebGL backend.`);
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Qc {
  constructor(e, t, r, s = !1, o = !1, i = !1, a = null, c = !1, l = !1) {
    this.variableNames = ["matrixA", "matrixB"], this.packedInputs = !0, this.packedOutput = !0, this.outputShape = r, this.enableShapeUniforms = Ce(this.outputShape.length);
    const u = s ? e[1] : e[2], d = Math.ceil(u / 2), h = s ? "i * 2, rc.y" : "rc.y, i * 2", f = o ? "rc.z, i * 2" : "i * 2, rc.z", m = s ? ["a.xxyy", "a.zzww"] : ["a.xxzz", "a.yyww"], C = o ? ["b.xzxz", "b.ywyw"] : ["b.xyxy", "b.zwzw"];
    let w = "", x = "";
    a && (c ? w = `vec4 activation(vec4 a) {
          vec4 b = getPreluActivationWeightsAtOutCoords();
          ${a}
        }` : l ? w = `vec4 activation(vec4 a) {
          vec4 b = getLeakyreluAlphaAtOutCoords();
          ${a}
        }` : w = `vec4 activation(vec4 x) {
          ${a}
        }`, x = "result = activation(result);");
    const y = i ? "result += getBiasAtOutCoords();" : "";
    i && this.variableNames.push("bias"), c && this.variableNames.push("preluActivationWeights"), l && this.variableNames.push("leakyreluAlpha");
    let v = "rc.x", I = "rc.x";
    e[0] < t[0] ? v = `imod(rc.x, ${e[0]})` : t[0] < e[0] && (I = `imod(rc.x, ${t[0]})`), this.userCode = `
      ${w}
      // Don't use uniform for sharedDimensionPacked for performance.
      const float sharedDimension = ${d}.0;

      vec4 dot2x2ARowBCol(ivec3 rc) {
        vec4 result = vec4(0);
        int batchA = ${v};
        int batchB = ${I};
        for (int i = 0; i < ${d}; i++) {
          vec4 a = getMatrixA(batchA, ${h});
          vec4 b = getMatrixB(batchB, ${f});

          // These swizzled products need to be separately added.
          // See: https://github.com/tensorflow/tfjs/issues/1735
          result += (${m[0]} * ${C[0]});
          result += (${m[1]} * ${C[1]});
        }
        return result;
      }

      void main() {
        ivec3 rc = getOutputCoords();
        vec4 result = dot2x2ARowBCol(rc);

        ${y}

        ${x}

        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const si = {
  REAL: "return areal * breal - aimag * bimag;",
  IMAG: "return areal * bimag + aimag * breal;"
};
class oi {
  constructor(e, t, r) {
    this.variableNames = ["AReal", "AImag", "BReal", "BImag"], this.outputShape = ve(t, r), this.userCode = `
      float binaryOpComplex(
          float areal, float aimag, float breal, float bimag) {
        ${e}
      }

      void main() {
        float areal = getARealAtOutCoords();
        float aimag = getAImagAtOutCoords();
        float breal = getBRealAtOutCoords();
        float bimag = getBImagAtOutCoords();
        setOutput(binaryOpComplex(areal, aimag, breal, bimag));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ii = "return a * b;";
function ao(n) {
  const { inputs: e, backend: t } = n, { a: r, b: s } = e, o = dt(r.dtype, s.dtype);
  if (r.dtype === "complex64") {
    const a = t.texData.get(r.dataId), c = t.texData.get(s.dataId), l = new oi(si.REAL, r.shape, s.shape), u = new oi(si.IMAG, r.shape, s.shape), d = [
      {
        dataId: a.complexTensorInfos.real.dataId,
        dtype: a.complexTensorInfos.real.dtype,
        shape: r.shape
      },
      {
        dataId: a.complexTensorInfos.imag.dataId,
        dtype: a.complexTensorInfos.imag.dtype,
        shape: r.shape
      },
      {
        dataId: c.complexTensorInfos.real.dataId,
        dtype: c.complexTensorInfos.real.dtype,
        shape: s.shape
      },
      {
        dataId: c.complexTensorInfos.imag.dataId,
        dtype: c.complexTensorInfos.imag.dtype,
        shape: s.shape
      }
    ], h = t.runWebGLProgram(l, d, "float32"), f = t.runWebGLProgram(u, d, "float32"), m = Nt({ inputs: { real: h, imag: f }, backend: t });
    return t.disposeIntermediateTensorInfo(h), t.disposeIntermediateTensorInfo(f), m;
  }
  if (t.shouldExecuteOnCPU([r, s])) {
    const a = t.texData.get(r.dataId), c = t.texData.get(s.dataId), [l, u] = Z0(r.shape, s.shape, a.values, c.values, o), d = t.makeTensorInfo(u, o), h = t.texData.get(d.dataId);
    return h.values = l, d;
  }
  let i;
  return E().getBool("WEBGL_PACK_BINARY_OPERATIONS") ? i = new Fn(ii, r.shape, s.shape) : i = new Xt(ii, r.shape, s.shape), t.runWebGLProgram(i, [r, s], o);
}
const e1 = {
  kernelName: Ui,
  backendName: "webgl",
  kernelFunc: ao
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function t1(n, e, t) {
  const r = [
    yn(n.shape),
    ...$n(n.shape)
  ], s = {
    dtype: n.dtype,
    shape: r,
    dataId: n.dataId
  }, o = [
    yn(e),
    ...$n(e)
  ], i = new Xc(o, r), a = !0, c = [r], l = t.runWebGLProgram(i, [s], n.dtype, c, a);
  return { dataId: l.dataId, shape: e, dtype: l.dtype };
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function D(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { shape: o } = r, i = t, a = _(s.shape), c = Ol(o, a), l = _(c);
  O(a === l, () => `The new shape (${c}) has ${l} elements and the old shape (${s.shape}) has ${a} elements. The new shape and old shape must have the same number of elements.`);
  const u = i.texData.get(s.dataId);
  return u.isPacked && !Rr(s.shape, c) && !(u.texture !== null && Rr(u.shape, c)) ? t1(s, c, i) : (i.incRef(s.dataId), { dataId: s.dataId, shape: c, dtype: s.dtype });
}
const n1 = {
  kernelName: zi,
  backendName: "webgl",
  kernelFunc: D
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ai {
  constructor(e, t) {
    this.variableNames = ["x"];
    const { windowSize: r, batchSize: s, inSize: o, outSize: i } = e;
    this.outputShape = [s, i];
    const a = Math.floor(r / 4) * 4, c = r % 4;
    let l = "sumValue += dot(values, ones);";
    if (t != null) {
      const d = 1 / t;
      l = `sumValue += dot(values * ${Cr(d) ? d.toPrecision(2) : d}, ones);`;
    }
    let u = "";
    o % r > 0 && (u = `
        if (inIdx < 0 || inIdx >= ${o}) {
          return 0.0;
        }
      `), this.userCode = `
      const vec4 ones = vec4(1.0, 1.0, 1.0, 1.0);

      float getValue(int batch, int inIdx) {
        ${u}
        return getX(batch, inIdx);
      }

      void main() {
        ivec2 coords = getOutputCoords();
        int batch = coords[0];
        int outIdx = coords[1];
        int inOffset = outIdx * ${r};

        float sumValue = 0.0;

        for (int i = 0; i < ${a}; i += 4) {
          int inIdx = inOffset + i;
          vec4 values = vec4(
            getValue(batch, inIdx),
            getValue(batch, inIdx + 1),
            getValue(batch, inIdx + 2),
            getValue(batch, inIdx + 3)
          );

          ${l}
        }

        int inIdx = inOffset + ${a};
        if (${c === 1}) {
          vec4 values = vec4(getValue(batch, inIdx), 0.0, 0.0, 0.0);

          ${l}
        } else if (${c === 2}) {
          vec4 values = vec4(
            getValue(batch, inIdx),
            getValue(batch, inIdx + 1), 0.0, 0.0);

          ${l}
        } else if (${c === 3}) {
          vec4 values = vec4(
            getValue(batch, inIdx),
            getValue(batch, inIdx + 1),
            getValue(batch, inIdx + 2), 0.0);

          ${l}
        }
        setOutput(sumValue);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class r1 {
  constructor(e, t) {
    this.variableNames = ["x"];
    const { windowSize: r, batchSize: s, inSize: o, outSize: i } = e;
    this.outputShape = [s, i];
    let a = "0.0", c = "";
    t === "prod" ? a = "1.0" : t === "min" ? (a = "1.0 / 1e-20", c = "min") : t === "max" && (a = "-1.0 / 1e-20", c = "max");
    let l = `${t}(${t}(${t}(minMaxValue[0], minMaxValue[1]), minMaxValue[2]), minMaxValue[3])`;
    t === "sum" ? l = "sumValue" : t === "prod" ? l = "prodValue" : t === "all" ? l = "allValue" : t === "any" && (l = "anyValue");
    const u = Math.floor(r / 4) * 4, d = r % 4;
    let h = `
      if (${t === "sum"}) {
        sumValue += dot(values, ones);
      } else if (${t === "prod"}) {
        vec2 tmp = vec2(values[0], values[1]) * vec2(values[2], values[3]);
        prodValue *= tmp[0] * tmp[1];
      } else {
        minMaxValue = ${c}(values, minMaxValue);
        if (${t === "min"} || ${t === "max"}) {
          minMaxValue = ${c}(values, minMaxValue);
          bvec4 isNaN = isnan(values);
          if (isNaN.r || isNaN.g || isNaN.b || isNaN.a) {
            minMaxValue = vec4(NAN);
          }
        }
      }
    `, f = "vec4";
    t === "all" ? (a = "1.0", h = `
        bool reducedAllValue = all(values);
        float floatedReducedAllValue = float(reducedAllValue);
        allValue = float(allValue >= 1.0 && floatedReducedAllValue >= 1.0);
      `, f = "bvec4") : t === "any" && (a = "0.0", h = `
        bool reducedAnyValue = any(values);
        float floatedReducedAnyValue = float(reducedAnyValue);
        anyValue = float(anyValue >= 1.0 || floatedReducedAnyValue >= 1.0);
      `, f = "bvec4");
    let m = "";
    o % r > 0 && (m = `
        if (inIdx < 0 || inIdx >= ${o}) {
          return initializationValue;
        }
      `), this.userCode = `
      const float initializationValue = ${a};
      const vec4 ones = vec4(1.0, 1.0, 1.0, 1.0);

      float getValue(int batch, int inIdx) {
        ${m}
        return getX(batch, inIdx);
      }

      void main() {
        ivec2 coords = getOutputCoords();
        int batch = coords[0];
        int outIdx = coords[1];
        int inOffset = outIdx * ${r};

        vec4 minMaxValue = vec4(${a});
        float prodValue = 1.0;
        float sumValue = 0.0;
        float allValue = 1.0;
        float anyValue = 0.0;

        for (int i = 0; i < ${u}; i += 4) {
          int inIdx = inOffset + i;
          ${f} values = ${f}(
            getValue(batch, inIdx),
            getValue(batch, inIdx + 1),
            getValue(batch, inIdx + 2),
            getValue(batch, inIdx + 3)
          );

          ${h}
        }

        int inIdx = inOffset + ${u};
        if (${d === 1}) {
          ${f} values = ${f}(
            getValue(batch, inIdx),
            initializationValue,
            initializationValue,
            initializationValue
          );

          ${h}
        } else if (${d === 2}) {
          ${f} values = ${f}(
            getValue(batch, inIdx),
            getValue(batch, inIdx + 1),
            initializationValue,
            initializationValue
          );

          ${h}
        } else if (${d === 3}) {
          ${f} values = ${f}(
            getValue(batch, inIdx),
            getValue(batch, inIdx + 1),
            getValue(batch, inIdx + 2),
            initializationValue
          );

          ${h}
        }
        setOutput(${l});
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function s1(n) {
  const e = [];
  for (; e.length === 0 || e[e.length - 1].outSize !== 1; ) {
    const t = e.length ? e[e.length - 1].outSize : n[1], r = Mr(t);
    e.push({
      inSize: t,
      windowSize: r,
      outSize: Math.ceil(t / r)
    });
  }
  return e;
}
function tn(n, e, t, r) {
  const s = s1(n.shape);
  let o = n;
  for (let i = 0; i < s.length; i++) {
    const { inSize: a, windowSize: c, outSize: l } = s[i];
    let u, d;
    t === "mean" ? u = i === 0 ? new ai({ windowSize: c, inSize: a, batchSize: n.shape[0], outSize: l }, a) : new ai({ windowSize: c, inSize: a, batchSize: n.shape[0], outSize: l }) : u = new r1({ windowSize: c, inSize: a, batchSize: n.shape[0], outSize: l }, t), d = o, o = r.runWebGLProgram(u, [o], e), d.dataId !== n.dataId && r.disposeIntermediateTensorInfo(d);
  }
  return o;
}
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class o1 {
  constructor(e, t) {
    this.variableNames = ["A"];
    const r = new Array(e.length);
    for (let i = 0; i < r.length; i++)
      r[i] = e[t[i]];
    this.outputShape = r, this.rank = r.length;
    const s = K(this.rank), o = i1(t);
    this.userCode = `
    void main() {
      ${s} resRC = getOutputCoords();
      setOutput(getA(${o}));
    }
    `;
  }
}
function i1(n) {
  const e = n.length;
  if (e > 6)
    throw Error(`Transpose for rank ${e} is not yet supported`);
  const t = ["resRC.x", "resRC.y", "resRC.z", "resRC.w", "resRC.u", "resRC.v"], r = new Array(e);
  for (let s = 0; s < n.length; s++)
    r[n[s]] = t[s];
  return r.join();
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class a1 {
  constructor(e, t) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !0;
    const r = new Array(e.length);
    for (let u = 0; u < r.length; u++)
      r[u] = e[t[u]];
    if (this.outputShape = r, this.rank = r.length, this.rank > 6)
      throw Error(`Packed transpose for rank ${this.rank} is not yet supported.`);
    const s = K(this.rank), o = Hc("rc", this.rank), i = new Array(this.rank);
    for (let u = 0; u < t.length; u++)
      i[t[u]] = o[u];
    const a = `vec2(${i.slice(-2).join()})`, c = `++${o[this.rank - 1]} < ${r[this.rank - 1]}`, l = `getChannel(getA(${i.join()}), ${a})`;
    this.userCode = `
    void main() {
      ${s} rc = getOutputCoords();
      vec4 result = vec4(0.);
      result[0] = ${l};
      if(${c}) {
        result[1] = ${l};
      }
      --${o[this.rank - 1]};
      if(++${o[this.rank - 2]} < ${r[this.rank - 2]}) {
        result[2] = ${l};
        if(${c}) {
          result[3] = ${l};
        }
      }
      setOutput(result);
    }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Wr(n, e, t) {
  const r = E().getBool("WEBGL_PACK_ARRAY_OPERATIONS") ? new a1(n.shape, e) : new o1(n.shape, e);
  return t.runWebGLProgram(r, [n], n.dtype);
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function c1(n, e, t, r) {
  const s = e, o = n.shape.length, i = Re(s, n.shape);
  let a = i;
  const c = He(a, o), l = c != null;
  let u = n;
  l && (u = Wr(n, c, r), a = Xe(a.length, o)), tt("sum", a, o);
  const [d, h] = ht(u.shape, a);
  let f = d;
  t && (f = gt(d, i));
  const m = _(h), w = _(n.shape) / m, x = D({ inputs: { x: u }, attrs: { shape: [w, m] }, backend: r }), y = Ms(n.dtype), v = tn(x, y, "sum", r), I = D({ inputs: { x: v }, attrs: { shape: f }, backend: r });
  return r.disposeIntermediateTensorInfo(x), r.disposeIntermediateTensorInfo(v), l && r.disposeIntermediateTensorInfo(u), I;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Gr(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { axis: o, keepDims: i } = r;
  return c1(s, o, i, t);
}
const l1 = {
  kernelName: qi,
  backendName: "webgl",
  kernelFunc: Gr
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ie(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { perm: o } = r, i = t, a = s.shape.length, c = new Array(a);
  for (let u = 0; u < c.length; u++)
    c[u] = s.shape[o[u]];
  let l;
  if (i.shouldExecuteOnCPU([s])) {
    const d = i.texData.get(s.dataId).values, h = oo(d, s.shape, s.dtype, o, c);
    l = i.makeTensorInfo(c, s.dtype);
    const f = i.texData.get(l.dataId);
    f.values = h;
  } else
    l = Wr(s, o, i);
  return l;
}
const u1 = {
  kernelName: Eh,
  backendName: "webgl",
  kernelFunc: Ie
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Zc = 1e3;
function Nr({ a: n, b: e, transposeA: t, transposeB: r, backend: s, bias: o = null, preluActivationWeights: i = null, leakyreluAlpha: a = 0, activation: c = null }) {
  const l = n.shape.length, u = e.shape.length, d = t ? n.shape[l - 2] : n.shape[l - 1], h = r ? e.shape[u - 1] : e.shape[u - 2], f = t ? n.shape[l - 1] : n.shape[l - 2], m = r ? e.shape[u - 2] : e.shape[u - 1], C = n.shape.slice(0, -2), w = e.shape.slice(0, -2), x = _(C), y = _(w), I = ve(n.shape.slice(0, -2), e.shape.slice(0, -2)).concat([f, m]);
  O(d === h, () => `Error in matMul: inner shapes (${d}) and (${h}) of Tensors with shapes ${n.shape} and ${e.shape} and transposeA=${t} and transposeB=${r} must match.`);
  const T = t ? [x, d, f] : [x, f, d], A = r ? [y, m, h] : [y, h, m], F = D({ inputs: { x: n }, backend: s, attrs: { shape: T } }), k = D({ inputs: { x: e }, backend: s, attrs: { shape: A } }), U = [F, k], V = Math.max(x, y), G = t ? F.shape[1] : F.shape[2], j = o != null, be = i != null, ie = c === "leakyrelu", ce = c != null ? jn(c, !0) : null, Ne = j || be || ie || ce != null;
  let ke;
  if ((f === 1 || m === 1) && G > Zc && Ne === !1) {
    let nt = F, Ct = k;
    t && (nt = Ie({ inputs: { x: F }, backend: s, attrs: { perm: [0, 2, 1] } }), U.push(nt)), r && (Ct = Ie({ inputs: { x: k }, backend: s, attrs: { perm: [0, 2, 1] } }), U.push(Ct));
    const bt = m !== 1, nn = m === 1;
    let Pn = nt;
    bt && (Pn = D({
      inputs: { x: nt },
      backend: s,
      attrs: { shape: [V, G, 1] }
    }), U.push(Pn));
    const ae = m === 1 ? 2 : 1;
    let he = Ct;
    nn && (he = D({
      inputs: { x: Ct },
      backend: s,
      attrs: { shape: [V, 1, G] }
    }), U.push(he));
    const _n = ao({ inputs: { a: Pn, b: he }, backend: s });
    ke = Gr({ inputs: { x: _n }, backend: s, attrs: { axis: ae, keepDims: !0 } }), U.push(_n);
  } else {
    const nt = dt(n.dtype, e.dtype), Ct = new Qc(T, A, [V, f, m], t, r, j, ce, be, ie), bt = [F, k];
    if (o != null && bt.push(o), be && bt.push(i), ie) {
      const nn = s.makeTensorInfo([], "float32", vn(a, "float32"));
      bt.push(nn), U.push(nn);
    }
    ke = s.runWebGLProgram(Ct, bt, nt);
  }
  const le = D({ inputs: { x: ke }, backend: s, attrs: { shape: I } });
  U.push(ke);
  for (const nt of U)
    s.disposeIntermediateTensorInfo(nt);
  return le;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function d1(n) {
  const { inputs: e, backend: t, attrs: r } = n, { a: s, b: o, bias: i, preluActivationWeights: a } = e, { transposeA: c, transposeB: l, activation: u, leakyreluAlpha: d } = r;
  return Nr({
    a: s,
    b: o,
    transposeA: c,
    transposeB: l,
    backend: t,
    bias: i,
    preluActivationWeights: a,
    leakyreluAlpha: d,
    activation: u
  });
}
const h1 = {
  kernelName: Fh,
  backendName: "webgl",
  kernelFunc: d1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ci = "return abs(x);";
function f1(n) {
  const { inputs: e, backend: t } = n, { x: r } = e;
  if (t.shouldExecuteOnCPU([r]) && r.dtype !== "complex64") {
    const o = t.texData.get(r.dataId), i = Gc(o.values);
    return t.makeTensorInfo(r.shape, r.dtype, i);
  }
  let s;
  return E().getBool("WEBGL_PACK_UNARY_OPERATIONS") ? s = new St(r.shape, ci) : s = new ct(r.shape, ci), t.runWebGLProgram(s, [r], r.dtype);
}
const p1 = {
  kernelName: Ai,
  backendName: "webgl",
  kernelFunc: f1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const m1 = je + `
  if (abs(x) > 1.) {
    return NAN;
  }
  return acos(x);
`, g1 = H({ opSnippet: m1 }), x1 = {
  kernelName: Zl,
  backendName: "webgl",
  kernelFunc: g1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const w1 = je + `
  if (x < 1.0) return NAN;
return log(x + sqrt(x * x - 1.0));`, C1 = H({ opSnippet: w1 }), b1 = {
  kernelName: Jl,
  backendName: "webgl",
  kernelFunc: C1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const li = "return a + b;", y1 = we({
  opSnippet: li,
  packedOpSnippet: li,
  supportsComplex: !0,
  cpuKernelImpl: A0
}), $1 = {
  kernelName: Ps,
  backendName: "webgl",
  kernelFunc: y1
};
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class v1 {
  constructor(e, t) {
    this.outputShape = [], this.outputShape = e, this.variableNames = t.map((o, i) => `T${i}`);
    const r = [];
    this.variableNames.forEach((o) => {
      r.push(`float v${o} = get${o}AtOutCoords();`);
    });
    const s = this.variableNames.map((o) => `v${o}`).join(" + ");
    this.userCode = `
      void main() {
        ${r.join(`
        `)}

        float result = ${s};
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class I1 {
  constructor(e, t) {
    this.outputShape = [], this.packedInputs = !0, this.packedOutput = !0, this.outputShape = e, this.variableNames = t.map((o, i) => `T${i}`);
    const r = [];
    this.variableNames.forEach((o) => {
      r.push(`vec4 v${o} = get${o}AtOutCoords();`);
    });
    const s = this.variableNames.map((o) => `v${o}`).join(" + ");
    this.userCode = `
      void main() {
        ${r.join(`
        `)}

        vec4 result = ${s};
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function xr(n) {
  const { inputs: e, backend: t } = n, r = e;
  if (r.length === 1)
    return De({ inputs: { x: r[0] }, backend: t });
  if (r.length > E().get("WEBGL_MAX_TEXTURES_IN_SHADER")) {
    const c = Math.floor(r.length / 2), l = xr({ inputs: r.slice(0, c), backend: t }), u = xr({ inputs: r.slice(c), backend: t });
    return xr({ inputs: [l, u], backend: t });
  }
  const s = r.map((c) => c.dtype).reduce((c, l) => dt(c, l)), o = r.map((c) => c.shape), a = E().getBool("WEBGL_PACK") ? new I1(r[0].shape, o) : new v1(r[0].shape, o);
  return t.runWebGLProgram(a, r, s);
}
const S1 = {
  kernelName: eu,
  backendName: "webgl",
  kernelFunc: xr
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function E1(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { axis: o, keepDims: i } = r, a = s.shape.length, c = Re(o, s.shape);
  let l = c;
  const u = He(l, a);
  let d = s;
  u != null && (d = Ie({ inputs: { x: s }, backend: t, attrs: { perm: u } }), l = Xe(l.length, a)), tt("all", l, a);
  const [h, f] = ht(d.shape, l), m = _(f), C = D({ inputs: { x: d }, backend: t, attrs: { shape: [-1, m] } }), w = tn(C, C.dtype, "all", t);
  let x;
  if (i) {
    const y = gt(h, c);
    x = D({ inputs: { x: w }, backend: t, attrs: { shape: y } });
  } else
    x = D({ inputs: { x: w }, backend: t, attrs: { shape: h } });
  return t.disposeIntermediateTensorInfo(C), t.disposeIntermediateTensorInfo(w), u != null && t.disposeIntermediateTensorInfo(d), x;
}
const R1 = {
  kernelName: tu,
  backendName: "webgl",
  kernelFunc: E1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function T1(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { axis: o, keepDims: i } = r, a = s.shape.length, c = Re(o, s.shape);
  let l = c;
  const u = He(l, a);
  let d = s;
  u != null && (d = Ie({ inputs: { x: s }, backend: t, attrs: { perm: u } }), l = Xe(l.length, a)), tt("any", l, a);
  const [h, f] = ht(d.shape, l), m = _(f), C = D({ inputs: { x: d }, backend: t, attrs: { shape: [-1, m] } }), w = tn(C, C.dtype, "any", t);
  let x;
  if (i) {
    const y = gt(h, c);
    x = D({ inputs: { x: w }, backend: t, attrs: { shape: y } });
  } else
    x = D({ inputs: { x: w }, backend: t, attrs: { shape: h } });
  return t.disposeIntermediateTensorInfo(C), t.disposeIntermediateTensorInfo(w), u != null && t.disposeIntermediateTensorInfo(d), x;
}
const N1 = {
  kernelName: nu,
  backendName: "webgl",
  kernelFunc: T1
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class k1 {
  constructor(e, t, r) {
    this.variableNames = ["A"];
    const { windowSize: s, batchSize: o, outSize: i } = e;
    r || this.variableNames.push("bestIndicesA"), this.outputShape = [o, i];
    const a = t === "max" ? ">" : "<", c = r ? "inOffset + i;" : "round(getBestIndicesA(batch, inOffset + i));";
    this.userCode = `
      void main() {
        ivec2 coords = getOutputCoords();
        int batch = coords[0];
        int outIdx = coords[1];
        int inOffset = outIdx * ${s};

        int bestIndex = inOffset;
        float bestValue = getA(batch, bestIndex);

        for (int i = 0; i < ${s}; i++) {
          int inIdx = ${c};
          float candidate = getA(batch, inIdx);
          if (candidate ${a} bestValue) {
            bestValue = candidate;
            bestIndex = inIdx;
          }
        }
        setOutput(float(bestIndex));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class A1 {
  constructor(e, t, r, s) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !0, O(e.length > 2, () => `Packed arg${r.charAt(0).toUpperCase() + r.slice(1)} supports only inputs with rank above 2.`);
    const o = e[e.length - 1], i = Math.ceil(o / t);
    this.outputShape = e.slice(0, -1), i > 1 && this.outputShape.push(i), s || this.variableNames.push("bestIndicesA");
    const a = this.outputShape, c = a.length, l = K(c), u = $e("coords", c);
    let d, h;
    if (i === 1) {
      h = c + 1;
      const k = K(h);
      d = `
        ${k} sourceLocR = ${k}(${u.join()}, 0);
        ++${u[c - 1]};
        ${k} sourceLocG = ${k}(${u.join()}, 0);
        ++${u[c - 2]};
        ${k} sourceLocA = ${k}(${u.join()}, 0);
        --${u[c - 1]};
        ${k} sourceLocB = ${k}(${u.join()}, 0);
        --${u[c - 2]};`;
    } else
      h = c, d = `
        ${l} sourceLocR = coords;
        ++${u[c - 1]};
        ${l} sourceLocG = coords;
        ++${u[c - 2]};
        ${l} sourceLocA = coords;
        --${u[c - 1]};
        ${l} sourceLocB = coords;
        --${u[c - 2]};`;
    const f = ["x", "y", "z", "w", "u", "v"].slice(0, h), m = "." + f[h - 1], C = f.map((k) => "int " + k), w = $e("sourceLocR", h - 1).concat("inIdx.r"), x = $e("sourceLocG", h - 1).concat("inIdx.g"), y = $e("sourceLocB", h - 1).concat("inIdx.b"), v = $e("sourceLocA", h - 1).concat("inIdx.a"), I = r === "max" ? "greaterThan" : "lessThan", T = s ? "" : `
          inIdx = round(vec4(getBestIndicesAChannel(${w.join()}),
                             getBestIndicesAChannel(${x.join()}),
                             getBestIndicesAChannel(${y.join()}),
                             getBestIndicesAChannel(${v.join()})));`, A = `vec4(
            getAChannel(${w.join()}),
            hasNextCol ? getAChannel(${x.join()}) : 0.,
            hasNextRow ? getAChannel(${y.join()}) : 0.,
            hasNextRow && hasNextCol ? getAChannel(${v.join()}) : 0.)`, F = s ? "" : `
      float getBestIndicesAChannel(${C.join()}) {
        return getChannel(getBestIndicesA(${f.join()}),
                                          vec2(${f.slice(-2).join()}));
      }`;
    this.userCode = `
      float getAChannel(${C.join()}) {
        return getChannel(getA(${f.join()}),
                               vec2(${f.slice(-2).join()}));
      }
      ${F}
      void main() {
        ${l} coords = getOutputCoords();
        bool hasNextCol = ${u[c - 1]} < ${a[c - 1] - 1};
        bool hasNextRow = ${u[c - 2]} < ${a[c - 2] - 1};
        ${d}
        ivec4 srcIdx = ivec4(sourceLocR${m}, sourceLocG${m},
          sourceLocB${m}, sourceLocA${m}) * ${t};
        ivec4 inIdx = srcIdx;
        vec4 bestIndex = vec4(inIdx);
        vec4 bestValue = ${A};

        for (int i = 0; i < ${t}; i++) {
          inIdx = srcIdx;
          ${T}
          vec4 candidate = ${A};
          bvec4 nan = isnan(candidate);
          bvec4 replace = bvec4(
            vec4(${I}(candidate, bestValue)) * (vec4(1.0) - vec4(nan)));

          bestValue = vec4(replace.x  ? candidate.x : bestValue.x,
                           replace.y  ? candidate.y : bestValue.y,
                           replace.z  ? candidate.z : bestValue.z,
                           replace.w  ? candidate.w : bestValue.w);
          bestIndex = mix(bestIndex, vec4(inIdx), vec4(replace));
          srcIdx++;
        }
        setOutput(bestIndex);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Jc(n, e, t, r = null) {
  let s = e.shape[0], o = e.shape[1];
  r != null && (s = r.shape[0], o = r.shape[1]);
  const i = Mr(o), a = { windowSize: i, inSize: o, batchSize: s, outSize: Math.ceil(o / i) }, c = new k1(a, t, r == null), l = [e];
  r != null && l.push(r);
  const u = n.runWebGLProgram(c, l, "int32");
  if (u.shape[1] === 1)
    return u;
  const d = Jc(n, e, t, u);
  return n.disposeIntermediateTensorInfo(u), d;
}
function el(n, e, t, r = null) {
  const s = r != null ? r.shape : e.shape, o = s[s.length - 1], i = Mr(o), a = new A1(s, i, t, r == null), c = r == null ? [e] : [e, r], l = n.runWebGLProgram(a, c, "int32");
  if (l.shape.length === e.shape.length) {
    const u = el(n, e, t, l);
    return n.disposeIntermediateTensorInfo(l), u;
  }
  return l;
}
function tl(n, e, t, r) {
  const s = [t];
  if (tt("arg" + r.charAt(0).toUpperCase() + r.slice(1), s, e.shape.length), !E().getBool("WEBGL_PACK_REDUCE") || e.shape.length <= 2) {
    const o = [], i = n.texData.get(e.dataId), a = i !== null && i.isPacked;
    let c = e;
    a && (c = n.unpackTensor(e), o.push(c));
    const [l, u] = ht(c.shape, s), d = _(u), h = D({ inputs: { x: c }, backend: n, attrs: { shape: [-1, d] } });
    o.push(h);
    const f = Jc(n, h, r);
    o.push(f);
    const m = D({ inputs: { x: f }, backend: n, attrs: { shape: l } });
    return o.forEach((C) => n.disposeIntermediateTensorInfo(C)), m;
  }
  return el(n, e, r);
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function F1(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { axis: o } = r;
  let i = Re(o, s.shape);
  const a = He(i, s.shape.length);
  let c = s;
  const l = [];
  a != null && (c = Ie({ inputs: { x: s }, backend: t, attrs: { perm: a } }), l.push(c), i = Xe(i.length, c.shape.length)), tt("argMax", [i[0]], c.shape.length);
  const u = tl(t, c, i[0], "max");
  return l.forEach((d) => t.disposeIntermediateTensorInfo(d)), u;
}
const D1 = {
  kernelName: ru,
  backendName: "webgl",
  kernelFunc: F1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function O1(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { axis: o } = r;
  let i = Re(o, s.shape);
  const a = He(i, s.shape.length);
  let c = s;
  const l = [];
  a != null && (c = Ie({ inputs: { x: s }, backend: t, attrs: { perm: a } }), l.push(c), i = Xe(i.length, c.shape.length)), tt("argMin", [i[0]], c.shape.length);
  const u = tl(t, c, i[0], "min");
  return l.forEach((d) => t.disposeIntermediateTensorInfo(d)), u;
}
const P1 = {
  kernelName: su,
  backendName: "webgl",
  kernelFunc: O1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const _1 = je + `
  if (abs(x) > 1.) {
    return NAN;
  }
  return asin(x);
`, B1 = H({ opSnippet: _1 }), L1 = {
  kernelName: ou,
  backendName: "webgl",
  kernelFunc: B1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const M1 = je + "return log(x + sqrt(x * x + 1.0));", U1 = H({ opSnippet: M1 }), V1 = {
  kernelName: iu,
  backendName: "webgl",
  kernelFunc: U1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const W1 = je + `
  return atan(x);
`, G1 = H({ opSnippet: W1 }), z1 = {
  kernelName: au,
  backendName: "webgl",
  kernelFunc: G1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const H1 = io + `
  return atan(a, b);
`, X1 = `
  vec4 result = atan(a, b);
  bvec4 isNaNA = isnan(a);
  bvec4 isNaNB = isnan(b);
  bvec4 isNaN = bvec4(isNaNA.x || isNaNB.x, isNaNA.y || isNaNB.y, isNaNA.z || isNaNB.z, isNaNA.w || isNaNB.w);
  ` + en + `
  return result;
`, j1 = we({ opSnippet: H1, packedOpSnippet: X1 }), q1 = {
  kernelName: lu,
  backendName: "webgl",
  kernelFunc: j1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const K1 = je + `
  if ((x < -1.0) || (x > 1.0)) return NAN;
return (log(1.0 + x) - log(1.0 - x)) / 2.0;`, Y1 = H({ opSnippet: K1 }), Q1 = {
  kernelName: cu,
  backendName: "webgl",
  kernelFunc: Y1
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class qn {
  constructor(e, t, r, s = !1, o = !1) {
    if (this.variableNames = ["x"], t === "avg" && r)
      throw new Error("Cannot compute positions for average pool.");
    const i = e.filterWidth, a = e.strideHeight, c = e.strideWidth, l = e.dilationHeight, u = e.dilationWidth, d = e.effectiveFilterHeight, h = e.effectiveFilterWidth, f = e.padInfo.top, m = e.padInfo.left;
    this.outputShape = e.outShape;
    const C = t === "avg", w = `((batch  * ${e.inHeight} + xR) * ${e.inWidth} + xC) * ${e.inChannels} + d`, x = `(xR * ${e.inWidth} + xC) * ${e.inChannels} + d`;
    let y = "0.0";
    if (C || (y = "-1.0 / 1e-20"), r) {
      const k = ">=";
      this.userCode = `
        const ivec2 strides = ivec2(${a}, ${c});
        const ivec2 pads = ivec2(${f}, ${m});

        void main() {
          ivec4 coords = getOutputCoords();
          int batch = coords[0];
          int d = coords[3];

          ivec2 xRCCorner = coords.yz * strides - pads;
          int xRCorner = xRCCorner.x;
          int xCCorner = xRCCorner.y;

          // max/min x(?, ?, d) to get y(yR, yC, d).
          // ? = to be determined
          float minMaxValue = 0.0;
          float minMaxValueFound = 0.0;
          int minMaxPosition = 0;
          float avgValue = 0.0;

          for (int wR = 0; wR < ${d};
              wR += ${l}) {
            int xR = xRCorner + wR;

            if (xR < 0 || xR >= ${e.inHeight}) {
              continue;
            }

            for (int wC = 0; wC < ${h};
                wC += ${u}) {
              int xC = xCCorner + wC;

              if (xC < 0 || xC >= ${e.inWidth}) {
                continue;
              }

              float value = getX(batch, xR, xC, d);

              // If a min / max value has already been found, use it. If not,
              // use the current value.
              float currMinMaxValue = mix(
                  value, minMaxValue, minMaxValueFound);
              if (value ${k} currMinMaxValue) {
                minMaxValue = value;
                minMaxValueFound = 1.0;
                minMaxPosition = ${s ? o ? w : x : `wR * ${h} + wC`};
              }
            }
          }
          setOutput(float(minMaxPosition));
        }
      `;
      return;
    }
    const v = "max";
    let I = `${t}(${t}(${t}(minMaxValue[0], minMaxValue[1]), minMaxValue[2]), minMaxValue[3])`;
    t === "avg" && (I = "avgValue / max(count, 1.0)");
    const T = Math.floor(i / 4) * 4, A = i % 4, F = `
      if (${C}) {
        avgValue += dot(values, ones);
      } else {
        minMaxValue = ${v}(values, minMaxValue);
      }
    `;
    this.userCode = `
      const ivec2 strides = ivec2(${a}, ${c});
      const ivec2 pads = ivec2(${f}, ${m});
      const float initializationValue = ${y};
      const vec4 ones = vec4(1.0, 1.0, 1.0, 1.0);

      float count = 0.0;

      float getValue(int batch, int xR, int xC, int d) {
        if (xC < 0 || xC >= ${e.inWidth}) {
          return initializationValue;
        }
        count += 1.0;
        return getX(batch, xR, xC, d);
      }

      void main() {
        ivec4 coords = getOutputCoords();
        int batch = coords[0];
        int d = coords[3];

        ivec2 xRCCorner = coords.yz * strides - pads;
        int xRCorner = xRCCorner.x;
        int xCCorner = xRCCorner.y;

        // max/min x(?, ?, d) to get y(yR, yC, d).
        // ? = to be determined
        vec4 minMaxValue = vec4(${y});
        float avgValue = 0.0;
        count = 0.0;

        for (int wR = 0; wR < ${d};
            wR += ${l}) {
          int xR = xRCorner + wR;

          if (xR < 0 || xR >= ${e.inHeight}) {
            continue;
          }

          for (int wC = 0; wC < ${T}; wC += 4) {
            int xC = xCCorner + wC * ${u};

            vec4 values = vec4(
              getValue(batch, xR, xC, d),
              getValue(batch, xR, xC + ${u}, d),
              getValue(batch, xR, xC + 2 * ${u}, d),
              getValue(batch, xR, xC + 3 * ${u}, d)
            );

            ${F}
          }

          int xC = xCCorner + ${T};
          if (${A === 1}) {
            vec4 values = vec4(
              getValue(batch, xR, xC, d),
              initializationValue,
              initializationValue,
              initializationValue
            );

            ${F}
          } else if (${A === 2}) {
            vec4 values = vec4(
              getValue(batch, xR, xC, d),
              getValue(batch, xR, xC + ${u}, d),
              initializationValue,
              initializationValue
            );

            ${F}
          } else if (${A === 3}) {
            vec4 values = vec4(
              getValue(batch, xR, xC, d),
              getValue(batch, xR, xC + ${u}, d),
              getValue(batch, xR, xC + 2 * ${u}, d),
              initializationValue
            );

            ${F}
          }
        }
        setOutput(${I});
      }
    `;
  }
}
class co {
  constructor(e, t, r, s = !1, o = !1) {
    if (this.variableNames = ["x"], t === "avg" && r)
      throw new Error("Cannot compute positions for average pool.");
    const i = e.filterWidth, a = e.strideDepth, c = e.strideHeight, l = e.strideWidth, u = e.dilationDepth, d = e.dilationHeight, h = e.dilationWidth, f = e.effectiveFilterDepth, m = e.effectiveFilterHeight, C = e.effectiveFilterWidth, w = e.padInfo.front, x = e.padInfo.top, y = e.padInfo.left;
    this.outputShape = e.outShape;
    const v = t === "avg";
    let I = "0.0";
    if (v || (I = "-1.0 / 1e-20"), r) {
      const V = ">=";
      this.userCode = `
        const ivec3 strides =
            ivec3(${a}, ${c}, ${l});
        const ivec3 pads = ivec3(${w}, ${x}, ${y});

        void main() {
          ivec5 coords = getOutputCoords();
          int batch = coords.x;
          int ch = coords.u;

          ivec3 xCorner = ivec3(coords.y, coords.z, coords.w) * strides - pads;
          int xDCorner = xCorner.x;
          int xRCorner = xCorner.y;
          int xCCorner = xCorner.z;

          // max/min x(?, ?, ?, ch) to get y(yD, yR, yC, ch).
          // ? = to be determined
          float minMaxValue = 0.0;
          float minMaxValueFound = 0.0;
          int minMaxPosition = 0;

          for (int wD = 0; wD < ${f};
              wD += ${u}) {
            int xD = xDCorner + wD;

            if (xD < 0 || xD >= ${e.inDepth}) {
              continue;
            }

            for (int wR = 0; wR < ${m};
                wR += ${d}) {
              int xR = xRCorner + wR;

              if (xR < 0 || xR >= ${e.inHeight}) {
                continue;
              }

              for (int wC = 0; wC < ${C};
                  wC += ${h}) {
                int xC = xCCorner + wC;

                if (xC < 0 || xC >= ${e.inWidth}) {
                  continue;
                }

                float value = getX(batch, xD, xR, xC, ch);

                // If a min / max value has already been found, use it. If not,
                // use the current value.
                float currMinMaxValue = mix(
                    value, minMaxValue, minMaxValueFound);
                if (value ${V} currMinMaxValue) {
                  minMaxValue = value;
                  minMaxValueFound = 1.0;
                  minMaxPosition = ${s ? o ? `(((batch * ${e.inDepth} + xD) * ${e.inHeight} + xR) * ${e.inWidth} + xC) * ${e.inChannels} + ch` : `((xD * ${e.inHeight} + xR) * ${e.inWidth} + xC) * ${e.inChannels} + ch` : `wD * ${m} * ${C} +
                      wR * ${C} + wC`};
                }
              }
            }
          }
          setOutput(float(minMaxPosition));
        }
      `;
      return;
    }
    const T = "max";
    let A = `${t}(${t}(${t}(minMaxValue[0], minMaxValue[1]), minMaxValue[2]), minMaxValue[3])`;
    t === "avg" && (A = "avgValue / max(count, 1.0)");
    const F = Math.floor(i / 4) * 4, k = i % 4, U = `
      if (${v}) {
        avgValue += dot(values, ones);
      } else {
        minMaxValue = ${T}(values, minMaxValue);
      }
    `;
    this.userCode = `
      const ivec3 strides =
        ivec3(${a}, ${c}, ${l});
      const ivec3 pads = ivec3(${w}, ${x}, ${y});
      const float initializationValue = ${I};
      const vec4 ones = vec4(1.0, 1.0, 1.0, 1.0);

      float count = 0.0;

      float getValue(int batch, int xD, int xR, int xC, int ch) {
        if (xC < 0 || xC >= ${e.inWidth}) {
          return initializationValue;
        }
        count += 1.0;
        return getX(batch, xD, xR, xC, ch);
      }

      void main() {
        ivec5 coords = getOutputCoords();
        int batch = coords.x;
        int ch = coords.u;

        ivec3 xCorner = ivec3(coords.y, coords.z, coords.w) * strides - pads;
        int xDCorner = xCorner.x;
        int xRCorner = xCorner.y;
        int xCCorner = xCorner.z;

        // max/min x(?, ?, ?, d) to get y(yD, yR, yC, ch).
        // ? = to be determined
        vec4 minMaxValue = vec4(${I});
        float avgValue = 0.0;
        count = 0.0;

        for (int wD = 0; wD < ${f};
            wD += ${u}) {
          int xD = xDCorner + wD;

          if (xD < 0 || xD >= ${e.inDepth}) {
            continue;
          }

          for (int wR = 0; wR < ${m};
            wR += ${d}) {
            int xR = xRCorner + wR;

            if (xR < 0 || xR >= ${e.inHeight}) {
              continue;
            }

            for (int wC = 0; wC < ${F}; wC += 4) {
              int xC = xCCorner + wC * ${h};

              vec4 values = vec4(
                getValue(batch, xD, xR, xC, ch),
                getValue(batch, xD, xR, xC + ${h}, ch),
                getValue(batch, xD, xR, xC + 2 * ${h}, ch),
                getValue(batch, xD, xR, xC + 3 * ${h}, ch)
              );

              ${U}
            }

            int xC = xCCorner + ${F};
            if (${k === 1}) {
              vec4 values = vec4(
                getValue(batch, xD, xR, xC, ch),
                initializationValue,
                initializationValue,
                initializationValue
              );

              ${U}
            } else if (${k === 2}) {
              vec4 values = vec4(
                getValue(batch, xD, xR, xC, ch),
                getValue(batch, xD, xR, xC + ${h}, ch),
                initializationValue,
                initializationValue
              );

              ${U}
            } else if (${k === 3}) {
              vec4 values = vec4(
                getValue(batch, xD, xR, xC, ch),
                getValue(batch, xD, xR, xC + ${h}, ch),
                getValue(batch, xD, xR, xC + 2 * ${h}, ch),
                initializationValue
              );

              ${U}
            }
          }
        }
        setOutput(${A});
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Z1(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e;
  tr(s, "avgPool");
  const { filterSize: o, strides: i, pad: a, dimRoundingMode: c } = r, l = 1;
  O(Sn(i, l), () => `Error in avgPool: Either strides or dilations must be 1. Got strides ${i} and dilations '${l}'`);
  const u = In(s.shape, o, i, l, a, c);
  if (u.filterWidth === 1 && u.filterHeight === 1 && ge(u.inShape, u.outShape))
    return De({ inputs: { x: s }, backend: t });
  const d = new qn(u, "avg", !1);
  return t.runWebGLProgram(d, [s], "float32");
}
const J1 = {
  kernelName: uu,
  backendName: "webgl",
  kernelFunc: Z1
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function eC(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { filterSize: o, strides: i, pad: a, dimRoundingMode: c, dataFormat: l } = r, u = [1, 1, 1], d = Zn(s.shape, o, i, u, a, c, l), h = new co(d, "avg", !1);
  return t.runWebGLProgram(h, [s], "float32");
}
const tC = {
  kernelName: hu,
  backendName: "webgl",
  kernelFunc: eC
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class nC {
  constructor(e) {
    this.variableNames = ["dy"], this.outputShape = e.inShape;
    const t = e.filterHeight, r = e.filterWidth, s = e.strideHeight, o = e.strideWidth, i = e.dilationHeight, a = e.dilationWidth, c = e.effectiveFilterHeight, l = e.effectiveFilterWidth, u = c - 1 - e.padInfo.top, d = l - 1 - e.padInfo.left, h = 1 / (t * r);
    this.userCode = `
      const ivec2 pads = ivec2(${u}, ${d});
      const float avgMultiplier = float(${h});

      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int d = coords[3];

        ivec2 dyRCCorner = coords.yz - pads;
        int dyRCorner = dyRCCorner.x;
        int dyCCorner = dyRCCorner.y;

        // Convolve dy(?, ?, d) with pos mask(:, :, d) to get dx(xR, xC, d).
        // ? = to be determined. : = across all values in that axis.
        float dotProd = 0.0;
        for (int wR = 0; wR < ${c};
            wR += ${i}) {
          float dyR = float(dyRCorner + wR) / ${s}.0;

          if (dyR < 0.0 || dyR >= ${e.outHeight}.0 || fract(dyR) > 0.0) {
            continue;
          }
          int idyR = int(dyR);

          for (int wC = 0; wC < ${l};
            wC+= ${a}) {
            float dyC = float(dyCCorner + wC) / ${o}.0;

            if (dyC < 0.0 || dyC >= ${e.outWidth}.0 ||
                fract(dyC) > 0.0) {
              continue;
            }
            int idyC = int(dyC);

            float dyValue = getDy(b, idyR, idyC, d);

            dotProd += dyValue * avgMultiplier;
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
class rC {
  constructor(e) {
    this.variableNames = ["dy"], this.outputShape = e.inShape;
    const t = e.filterDepth, r = e.filterHeight, s = e.filterWidth, o = e.strideDepth, i = e.strideHeight, a = e.strideWidth, c = e.dilationDepth, l = e.dilationHeight, u = e.dilationWidth, d = e.effectiveFilterDepth, h = e.effectiveFilterHeight, f = e.effectiveFilterWidth, m = d - 1 - e.padInfo.front, C = h - 1 - e.padInfo.top, w = f - 1 - e.padInfo.left, x = 1 / (t * r * s);
    this.userCode = `
      const ivec3 pads = ivec3(${m}, ${C}, ${w});
      const float avgMultiplier = float(${x});

      void main() {
        ivec5 coords = getOutputCoords();
        int batch = coords.x;
        int ch = coords.u;

        ivec3 dyCorner = ivec3(coords.y, coords.z, coords.w) - pads;
        int dyDCorner = dyCorner.x;
        int dyRCorner = dyCorner.y;
        int dyCCorner = dyCorner.z;

        // Convolve dy(?, ?, ?, d) with pos mask(:, :, :, ch) to get
        // dx(xD, xR, xC, ch).
        // ? = to be determined. : = across all values in that axis.
        float dotProd = 0.0;

        for (int wD = 0; wD < ${d};
            wD += ${c}) {
          float dyD = float(dyDCorner + wD) / ${o}.0;

          if (dyD < 0.0 || dyD >= ${e.outDepth}.0 || fract(dyD) > 0.0) {
            continue;
          }
          int idyD = int(dyD);

          for (int wR = 0; wR < ${h};
              wR += ${l}) {
            float dyR = float(dyRCorner + wR) / ${i}.0;

            if (dyR < 0.0 || dyR >= ${e.outHeight}.0 ||
                fract(dyR) > 0.0) {
              continue;
            }
            int idyR = int(dyR);

            for (int wC = 0; wC < ${f};
                wC += ${u}) {
              float dyC = float(dyCCorner + wC) / ${a}.0;

              if (dyC < 0.0 || dyC >= ${e.outWidth}.0 ||
                  fract(dyC) > 0.0) {
                continue;
              }
              int idyC = int(dyC);

              float dyValue = getDy(batch, idyD, idyR, idyC, ch);

              dotProd += dyValue * avgMultiplier;
            }
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function sC(n) {
  const { inputs: e, backend: t, attrs: r } = n, { dy: s, input: o } = e, i = o, { filterSize: a, strides: c, pad: l, dimRoundingMode: u } = r, d = [1, 1, 1], h = Zn(i.shape, a, c, d, l, u), f = new rC(h);
  return t.runWebGLProgram(f, [s], i.dtype);
}
const oC = {
  kernelName: fu,
  backendName: "webgl",
  kernelFunc: sC
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function iC(n) {
  const { inputs: e, backend: t, attrs: r } = n, { dy: s, input: o } = e, i = o;
  tr([s, o], "avgPoolGrad");
  const { filterSize: a, strides: c, pad: l } = r, u = In(i.shape, a, c, 1, l), d = new nC(u);
  return t.runWebGLProgram(d, [s], i.dtype);
}
const aC = {
  kernelName: du,
  backendName: "webgl",
  kernelFunc: iC
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function cC(n) {
  const { inputs: e, backend: t, attrs: r } = n, { a: s, b: o } = e, { transposeA: i, transposeB: a } = r;
  return Nr({ a: s, b: o, transposeA: i, transposeB: a, backend: t });
}
const lC = {
  kernelName: pu,
  backendName: "webgl",
  kernelFunc: cC
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class uC {
  constructor(e, t, r, s, o, i) {
    this.outputShape = [], this.variableNames = ["x", "mean", "variance"], ve(e, t), ve(e, r);
    let a = "0.0";
    s != null && (ve(e, s), this.variableNames.push("offset"), a = "getOffsetAtOutCoords()");
    let c = "1.0";
    o != null && (ve(e, o), this.variableNames.push("scale"), c = "getScaleAtOutCoords()"), this.outputShape = e, this.userCode = `
      void main() {
        float x = getXAtOutCoords();
        float mean = getMeanAtOutCoords();
        float variance = getVarianceAtOutCoords();
        float offset = ${a};
        float scale = ${c};
        float inv = scale * inversesqrt(variance + float(${i}));
        setOutput(dot(vec3(x, -mean, offset), vec3(inv, inv, 1)));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class dC {
  constructor(e, t, r, s, o, i) {
    this.packedInputs = !0, this.packedOutput = !0, this.variableNames = ["x", "mean", "variance"], ve(e, t), ve(e, r);
    let a = "vec4(0.0)";
    s != null && (ve(e, s), this.variableNames.push("offset"), a = "getOffsetAtOutCoords()");
    let c = "vec4(1.0)";
    o != null && (ve(e, o), this.variableNames.push("scale"), c = "getScaleAtOutCoords()"), this.outputShape = e, this.userCode = `
      void main() {
        vec4 offset = ${a};
        vec4 scale = ${c};

        vec4 x = getXAtOutCoords();
        vec4 mean = getMeanAtOutCoords();
        vec4 variance = getVarianceAtOutCoords();

        vec4 inv = scale * inversesqrt(variance + vec4(${i}));

        setOutput((x - mean) * inv + offset);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const hC = ({ inputs: n, backend: e, attrs: t }) => {
  const { x: r, mean: s, variance: o, offset: i, scale: a } = n;
  O(s.shape.length === o.shape.length, () => "Batch normalization gradient requires mean and variance to have equal ranks."), O(i == null || s.shape.length === i.shape.length, () => "Batch normalization gradient requires mean and offset to have equal ranks."), O(a == null || s.shape.length === a.shape.length, () => "Batch normalization gradient requires mean and scale to have equal ranks.");
  let { varianceEpsilon: c } = t;
  c == null && (c = 1e-3);
  const l = [r, s, o];
  let u = null;
  i != null && (u = i.shape, l.push(i));
  let d = null;
  a != null && (d = a.shape, l.push(a));
  const h = E().getBool("WEBGL_PACK_NORMALIZATION") ? new dC(r.shape, s.shape, o.shape, u, d, c) : new uC(r.shape, s.shape, o.shape, u, d, c);
  return e.runWebGLProgram(h, l, l[0].dtype);
}, fC = {
  kernelName: Yu,
  backendName: "webgl",
  kernelFunc: hC
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class pC {
  constructor(e) {
    this.variableNames = ["source"], this.outputShape = e, this.rank = e.length;
    const t = K(this.rank);
    this.customUniforms = [{ name: "start", arrayIndex: this.rank, type: "int" }];
    const r = mC(this.rank);
    let s;
    const o = e.map((i, a) => `sourceLoc.${Ts[a]} = start[${a}] + coords.${Ts[a]};`);
    s = `
        ${t} sourceLoc;
        ${t} coords = getOutputCoords();
        ${o.join(`
`)}
      `, this.userCode = `
      void main() {
        ${s}
        setOutput(getSource(${r}));
      }
    `;
  }
}
const Ts = ["x", "y", "z", "w", "u", "v"];
function mC(n) {
  if (n === 1)
    return "sourceLoc";
  if (n <= 6)
    return Ts.slice(0, n).map((e) => "sourceLoc." + e).join(",");
  throw Error(`Slicing for rank ${n} is not yet supported`);
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class gC {
  constructor(e) {
    this.variableNames = ["source"], this.packedInputs = !0, this.packedOutput = !0, this.outputShape = e, this.rank = e.length, this.customUniforms = [{ name: "start", arrayIndex: this.rank, type: "int" }];
    const t = K(this.rank), r = $e("coords", this.rank), s = $e("sourceLoc", this.rank), o = this.rank === 1 ? "sourceLoc" : `vec2(${s.slice(-2).join()})`, i = `getChannel(getSource(${s.join()}), ${o})`, a = `
      result.x = ${i};
      if (++${r[this.rank - 1]} < ${e[this.rank - 1]}) {
        ++${s[this.rank - 1]};
        result.y = ${i};
        --${s[this.rank - 1]};
      }
    `, c = this.rank === 1 ? "" : `
      --${r[this.rank - 1]};
      if (++${r[this.rank - 2]} < ${e[this.rank - 2]}) {
        ++${s[this.rank - 2]};
        result.z = ${i};
        if (++${r[this.rank - 1]} < ${e[this.rank - 1]}) {
          ++${s[this.rank - 1]};
          result.w = ${i};
        }
      }
    `, l = this.rank <= 4 ? `sourceLoc = coords +
            ${t}(${e.map((u, d) => `start[${d}]`).join()});` : e.map((u, d) => `${s[d]} = ${r[d]} + start[${d}];`).join(`
`);
    this.userCode = `
      void main() {
        ${t} coords = getOutputCoords();
        ${t} sourceLoc;
        ${l}
        vec4 result = vec4(0.);
        ${a}
        ${c}
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function xC(n, e, t, r) {
  const s = r.texData.get(n.dataId), o = r.makeTensorInfo(t, n.dtype), i = r.texData.get(o.dataId);
  Object.assign(i, s), i.refCount = 1, i.shape = t, i.dtype = n.dtype;
  let a = Ys(e, me(n.shape));
  s.slice && (a += s.slice.flatOffset), i.slice = {
    flatOffset: a,
    // Point to the original dataId, which is used to do ref counting.
    origDataId: s.slice && s.slice.origDataId || n.dataId
  };
  const c = r.dataRefCount.get(i.slice.origDataId) || 1;
  return r.dataRefCount.set(i.slice.origDataId, c + 1), o;
}
function On(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { begin: o, size: i } = r, [a, c] = za(s, o, i);
  if (Oa(s, a, c), _(c) === 0)
    return t.makeTensorInfo(c, s.dtype, []);
  if (t.shouldExecuteOnCPU([s]) || s.dtype === "string") {
    const d = t.texData.get(s.dataId), h = lw(d.values, a, c, s.shape, s.dtype);
    return t.makeTensorInfo(c, s.dtype, h);
  }
  const { isPacked: l } = t.texData.get(s.dataId), u = Ks(s.shape, a, c);
  if (l || !u) {
    const d = E().getBool("WEBGL_PACK_ARRAY_OPERATIONS") ? new gC(c) : new pC(c), h = [a];
    return t.runWebGLProgram(d, [s], s.dtype, h);
  }
  return t.uploadToGPU(s.dataId), xC(s, a, c, t);
}
const wC = {
  kernelName: nh,
  backendName: "webgl",
  kernelFunc: On
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const CC = (n) => {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { blockShape: o, crops: i } = r;
  O(s.shape.length <= 4, () => "batchToSpaceND for rank > 4 with a WebGL backend not implemented yet");
  const a = o.reduce((y, v) => y * v), c = Zs(s.shape, o, a), l = Js(c.length, o.length), u = eo(s.shape, o, a), d = Za(i, o.length), h = Ja(u, i, o.length), f = [], m = D({ inputs: { x: s }, backend: t, attrs: { shape: c } }), C = Ie({ inputs: { x: m }, backend: t, attrs: { perm: l } }), w = D({
    inputs: { x: C },
    backend: t,
    attrs: { shape: u }
  }), x = On({
    inputs: { x: w },
    backend: t,
    attrs: { begin: d, size: h }
  });
  return f.push(m), f.push(C), f.push(w), f.forEach((y) => t.disposeIntermediateTensorInfo(y)), x;
}, bC = {
  kernelName: mu,
  backendName: "webgl",
  kernelFunc: CC
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function yC(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, weights: o } = e, { size: i } = r, a = t.readSync(s.dataId), c = t.readSync(o.dataId), l = Wc(a, c, o.dtype, o.shape, i);
  return t.makeTensorInfo([i], o.dtype, l);
}
const $C = {
  kernelName: gu,
  backendName: "webgl",
  kernelFunc: yC
};
/**
 * @license
 * Copyright 2023 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const vC = `
  int r = int(a.r) & int(b.r);
  int g = int(a.g) & int(b.g);
  int rb = int(a.b) & int(b.b);
  int ra = int(a.a) & int(b.a);
  return vec4(r, g, rb, ra);
`, IC = `
  return float(int(a.r) & int(b.r));
`;
function SC(n) {
  const { inputs: e, backend: t } = n, { a: r, b: s } = e, o = E().getBool("WEBGL_PACK_BINARY_OPERATIONS"), i = E().getNumber("WEBGL_VERSION");
  if (t.shouldExecuteOnCPU([r, s]) || i === 1) {
    const c = t.texData.get(r.dataId).values, l = t.texData.get(s.dataId).values, [u, d] = D0(r.shape, s.shape, c, l, r.dtype), h = t.makeTensorInfo(d, r.dtype), f = t.texData.get(h.dataId);
    return f.values = u, h;
  }
  let a;
  return o ? a = new Fn(vC, r.shape, s.shape, !1) : a = new Xt(IC, r.shape, s.shape), t.runWebGLProgram(a, [r, s], r.dtype);
}
const EC = {
  kernelName: xu,
  backendName: "webgl",
  kernelFunc: SC
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function RC(n) {
  const { inputs: e, backend: t } = n, { s0: r, s1: s } = e, o = t.readSync(r.dataId), i = t.readSync(s.dataId), a = ve(Array.from(o), Array.from(i));
  return t.makeTensorInfo([a.length], "int32", Int32Array.from(a));
}
const TC = {
  kernelName: wu,
  backendName: "webgl",
  kernelFunc: RC
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const NC = "return float(a != b);", nl = we({ opSnippet: NC, cpuKernelImpl: ew, dtype: "bool" }), kC = {
  kernelName: Nd,
  backendName: "webgl",
  kernelFunc: nl
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function rr(n) {
  const { inputs: e, backend: t } = n, { input: r } = e, s = t.texData.get(r.dataId);
  return De({ inputs: { x: s.complexTensorInfos.real }, backend: t });
}
const AC = {
  kernelName: Wd,
  backendName: "webgl",
  kernelFunc: rr
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const FC = "return float(int(x));";
function DC(n, e) {
  const t = new ct(n.shape, FC), r = e.runWebGLProgram(t, [n], "int32");
  return { dataId: r.dataId, shape: r.shape, dtype: r.dtype };
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ns(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { dtype: o } = r;
  if (o === "complex64") {
    if (s.dtype === "complex64")
      return De({ inputs: { x: s }, backend: t });
    const i = vs(s.shape), a = Ns({ inputs: { x: s }, backend: t, attrs: { dtype: "float32" } }), c = Nt({ inputs: { real: a, imag: i }, backend: t });
    return i.dispose(), t.disposeIntermediateTensorInfo(a), c;
  }
  if (s.dtype === "complex64") {
    const i = rr({ inputs: { input: s }, backend: t }), a = Ns({ inputs: { x: i }, backend: t, attrs: { dtype: o } });
    return t.disposeIntermediateTensorInfo(i), a;
  }
  if (!Bl(s.dtype, o)) {
    const i = De({ inputs: { x: s }, backend: t });
    return { dataId: i.dataId, shape: i.shape, dtype: o };
  }
  if (t.shouldExecuteOnCPU([s])) {
    const i = t.texData.get(s.dataId).values, [a, c, l] = O0(i, s.shape, s.dtype, o);
    return t.makeTensorInfo(a, c, l);
  }
  if (o === "int32")
    return DC(s, t);
  if (o === "bool") {
    const i = t.makeTensorInfo([], "bool", Ut("bool", 1)), c = nl({ inputs: { a: s, b: i }, backend: t });
    return t.disposeIntermediateTensorInfo(i), c;
  }
  throw new Error(`Error in Cast: failed to cast ${s.dtype} to ${o}`);
}
const OC = {
  kernelName: _s,
  backendName: "webgl",
  kernelFunc: Ns
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ui = "return ceil(x);", PC = H({ opSnippet: ui, packedOpSnippet: ui, cpuKernelImpl: P0 }), _C = {
  kernelName: Cu,
  backendName: "webgl",
  kernelFunc: PC
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class BC {
  constructor(e) {
    this.variableNames = ["A"], this.customUniforms = [
      { name: "minVal", type: "float" },
      { name: "maxVal", type: "float" }
    ], this.outputShape = e, this.userCode = `

      void main() {
        float value = getAAtOutCoords();
        if (isnan(value)) {
          setOutput(value);
          return;
        }

        setOutput(clamp(value, minVal, maxVal));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class LC {
  constructor(e) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !0, this.customUniforms = [
      { name: "minVal", type: "float" },
      { name: "maxVal", type: "float" }
    ], this.outputShape = e, this.userCode = `
      void main() {
        vec4 value = getAAtOutCoords();

        if (any(isnan(value))) {
          setOutput(value);
          return;
        }

        setOutput(clamp(value, vec4(minVal), vec4(maxVal)));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function MC(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { clipValueMin: o, clipValueMax: i } = r;
  let a;
  E().getBool("WEBGL_PACK_CLIP") ? a = new LC(s.shape) : a = new BC(s.shape);
  const c = [[o], [i]];
  return t.runWebGLProgram(a, [s], s.dtype, c);
}
const UC = {
  kernelName: bu,
  backendName: "webgl",
  kernelFunc: MC
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class VC {
  constructor(e) {
    this.variableNames = ["real", "imag"], this.outputShape = e, this.userCode = `
      void main() {
        float re = abs(getRealAtOutCoords());
        float im = abs(getImagAtOutCoords());
        float mx = max(re, im);

        // sadly the length function in glsl is not underflow-safe
        // (at least not on Intel GPUs). So the safe solution is
        // to ensure underflow-safety in all cases.
        setOutput(
          mx == 0.0 ? 0.0 : mx * length(vec2(1, min(re, im)/mx))
        );
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function di(n, e) {
  return {
    dataId: e.dataId,
    dtype: e.dtype,
    shape: n.shape
  };
}
function WC(n) {
  const { inputs: e, backend: t } = n, { x: r } = e, s = t.texData.get(r.dataId), o = new VC(r.shape), i = [
    di(r, s.complexTensorInfos.real),
    di(r, s.complexTensorInfos.imag)
  ];
  return t.runWebGLProgram(o, i, i[0].dtype);
}
const GC = {
  kernelName: Di,
  backendName: "webgl",
  kernelFunc: WC
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class zC {
  // Concats 2d tensors along axis=1. See comments in MathBackendWebGL.concat().
  constructor(e) {
    this.outputShape = [], this.outputShape = Ht(
      e,
      1
      /* axis */
    ), this.variableNames = e.map((i, a) => `T${a}`);
    const t = new Array(e.length - 1);
    t[0] = e[0][1];
    for (let i = 1; i < t.length; i++)
      t[i] = t[i - 1] + e[i][1];
    const r = [`if (yC < ${t[0]}) setOutput(getT0(yR, yC));`];
    for (let i = 1; i < t.length; i++) {
      const a = t[i - 1];
      r.push(`else if (yC < ${t[i]}) setOutput(getT${i}(yR, yC-${a}));`);
    }
    const s = t.length, o = t[t.length - 1];
    r.push(`else setOutput(getT${s}(yR, yC-${o}));`), this.userCode = `
      void main() {
        ivec2 coords = getOutputCoords();
        int yR = coords.x;
        int yC = coords.y;

        ${r.join(`
        `)}
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class HC {
  constructor(e, t) {
    this.packedInputs = !0, this.packedOutput = !0, this.outputShape = [], this.outputShape = Ht(e, t);
    const r = this.outputShape, s = r.length, o = K(s), i = $e("coords", s), a = ["x", "y", "z", "w", "u", "v"].slice(0, s);
    this.variableNames = e.map((C, w) => `T${w}`);
    const c = new Array(e.length - 1);
    c[0] = e[0][t];
    for (let C = 1; C < c.length; C++)
      c[C] = c[C - 1] + e[C][t];
    const l = a[t], u = a.slice(-2), d = a.join();
    let h = `if (${l} < ${c[0]}) {
        return getChannel(
            getT0(${d}), vec2(${u.join()}));
        }`;
    for (let C = 1; C < c.length; C++) {
      const w = c[C - 1];
      h += `
        if (${l} < ${c[C]}  && ${l} >= ${c[C - 1]}) {
          return getChannel(
            getT${C}(${pr(a, l, w)}),
            vec2(${pr(u, l, w)}));
        }`;
    }
    const f = c.length, m = c[c.length - 1];
    h += `
        return getChannel(
          getT${f}(${pr(a, l, m)}),
          vec2(${pr(u, l, m)}));`, this.userCode = `
      float getValue(${a.map((C) => "int " + C)}) {
        ${h}
      }

      void main() {
        ${o} coords = getOutputCoords();
        vec4 result = vec4(getValue(${i}), 0., 0., 0.);

        ${i[s - 1]} = ${i[s - 1]} + 1;
        if (${i[s - 1]} < ${r[s - 1]}) {
          result.g = getValue(${i});
        }

        ${i[s - 2]} = ${i[s - 2]} + 1;
        if (${i[s - 2]} < ${r[s - 2]}) {
          result.a = getValue(${i});
        }

        ${i[s - 1]} = ${i[s - 1]} - 1;
        if (${i[s - 2]} < ${r[s - 2]} &&
            ${i[s - 1]} < ${r[s - 1]}) {
          result.b = getValue(${i});
        }
        setOutput(result);
      }
    `;
  }
}
function pr(n, e, t) {
  const r = n.indexOf(e);
  return n.map((o, i) => i === r ? `${o} - ${t}` : o).join();
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function zr(n) {
  const { inputs: e, backend: t } = n, { input: r } = e, s = t.texData.get(r.dataId);
  return De({ inputs: { x: s.complexTensorInfos.imag }, backend: t });
}
const XC = {
  kernelName: nd,
  backendName: "webgl",
  kernelFunc: zr
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Gn(n, e, t) {
  const r = n[0].dtype;
  if (r === "complex64") {
    const f = n.map((y) => rr({ inputs: { input: y }, backend: t })), m = n.map((y) => zr({ inputs: { input: y }, backend: t })), C = Gn(f, e, t), w = Gn(m, e, t), x = Nt({ inputs: { real: C, imag: w }, backend: t });
    return f.forEach((y) => t.disposeIntermediateTensorInfo(y)), m.forEach((y) => t.disposeIntermediateTensorInfo(y)), t.disposeIntermediateTensorInfo(C), t.disposeIntermediateTensorInfo(w), x;
  }
  let s = t.shouldExecuteOnCPU(n);
  if (r === "string" && (s = !0), s) {
    const f = n.map((I) => {
      const A = [-1, _(I.shape.slice(e))];
      return D({ inputs: { x: I }, backend: t, attrs: { shape: A } });
    }), m = f.map((I) => ({ vals: t.readSync(I.dataId), shape: I.shape })), C = Ht(
      f.map((I) => I.shape),
      1
      /* axis */
    ), w = f[0].shape[0] === 1, x = _0(m, C, r, w), y = Ht(n.map((I) => I.shape), e), v = t.makeTensorInfo(y, r, x);
    return f.forEach((I) => t.disposeIntermediateTensorInfo(I)), v;
  }
  const o = n.filter((f) => _(f.shape) > 0), i = E().getBool("WEBGL_PACK_ARRAY_OPERATIONS") && o[0].shape.length > 1;
  if (o.length === 1) {
    const f = i ? new ct(n[0].shape, vt) : new St(n[0].shape, vt);
    return t.runWebGLProgram(f, n, r);
  }
  const a = E().getNumber("WEBGL_MAX_TEXTURES_IN_SHADER");
  if (o.length > a) {
    const f = [];
    for (let C = 0; C < o.length; C += a) {
      const w = o.slice(C, C + a);
      f.push(Gn(w, e, t));
    }
    const m = Gn(f, e, t);
    for (const C of f)
      t.disposeIntermediateTensorInfo(C);
    return m;
  }
  if (i) {
    const f = new HC(o.map((m) => m.shape), e);
    return t.runWebGLProgram(f, o, r);
  }
  const { tensors2D: c, outShape: l } = jC(o, e, t), u = new zC(c.map((f) => f.shape)), d = t.runWebGLProgram(u, c, r);
  c.forEach((f) => t.disposeIntermediateTensorInfo(f));
  const h = D({ inputs: { x: d }, attrs: { shape: l }, backend: t });
  return t.disposeIntermediateTensorInfo(d), h;
}
function jC(n, e, t) {
  const r = Ht(n.map((o) => o.shape), e);
  return { tensors2D: n.map((o) => D({
    inputs: { x: o },
    attrs: { shape: [-1, _(o.shape.slice(e))] },
    backend: t
  })), outShape: r };
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function rl(n) {
  const { inputs: e, backend: t, attrs: r } = n, { axis: s } = r, o = Re(s, e[0].shape)[0], i = e.map((l) => l.shape);
  Xa(i, o);
  const a = Ht(e.map((l) => l.shape), o);
  if (_(a) === 0)
    return t.makeTensorInfo(a, e[0].dtype, []);
  const c = e.filter((l) => _(l.shape) > 0);
  return c.length === 1 ? De({ inputs: { x: c[0] }, backend: t }) : Gn(c, o, t);
}
const qC = {
  kernelName: yu,
  backendName: "webgl",
  kernelFunc: rl
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class sl {
  constructor(e, t = !1, r = null, s = !1, o = !1) {
    this.variableNames = ["x", "W"], this.outputShape = e.outShape;
    const i = e.padInfo.top, a = e.padInfo.left, c = e.strideHeight, l = e.strideWidth, u = e.dilationHeight, d = e.dilationWidth, h = e.filterHeight, f = e.filterWidth, m = Math.floor(e.inChannels / 4) * 4, C = e.inChannels % 4, w = e.dataFormat === "channelsLast", x = w ? 1 : 2, y = w ? 2 : 3, v = w ? 3 : 1;
    let I = "", T = "";
    r && (s ? I = `float activation(float a) {
          float b = getPreluActivationWeightsAtOutCoords();
          ${r}
        }` : o ? I = `float activation(float a) {
          float b = getLeakyreluAlphaAtOutCoords();
          ${r}
        }` : I = `
          float activation(float x) {
            ${r}
          }
        `, T = "result = activation(result);");
    const A = t ? "result += getBiasAtOutCoords();" : "";
    t && this.variableNames.push("bias"), s && this.variableNames.push("preluActivationWeights"), o && this.variableNames.push("leakyreluAlpha"), this.userCode = `
      ${I}

      const ivec2 strides = ivec2(${c}, ${l});
      const ivec2 pads = ivec2(${i}, ${a});

      void main() {
        ivec4 coords = getOutputCoords();
        int batch = coords[0];
        int d2 = coords[${v}];

        ivec2 xRCCorner =
            ivec2(coords[${x}], coords[${y}]) * strides - pads;
        int xRCorner = xRCCorner.x;
        int xCCorner = xRCCorner.y;

        // Convolve x(?, ?, d1) with w(:, :, d1, d2) to get y(yR, yC, d2).
        // ? = to be determined. : = across all values in that axis.
        float dotProd = 0.0;
        for (int wR = 0; wR < ${h}; wR++) {
          int xR = xRCorner + wR * ${u};

          if (xR < 0 || xR >= ${e.inHeight}) {
            continue;
          }

          for (int wC = 0; wC < ${f}; wC++) {
            int xC = xCCorner + wC * ${d};

            if (xC < 0 || xC >= ${e.inWidth}) {
              continue;
            }

            for (int d1 = 0; d1 < ${m}; d1 += 4) {
              vec4 wValues = vec4(
                getW(wR, wC, d1, d2),
                getW(wR, wC, d1 + 1, d2),
                getW(wR, wC, d1 + 2, d2),
                getW(wR, wC, d1 + 3, d2)
              );

              if (${w}) {
                vec4 xValues = vec4(
                  getX(batch, xR, xC, d1),
                  getX(batch, xR, xC, d1 + 1),
                  getX(batch, xR, xC, d1 + 2),
                  getX(batch, xR, xC, d1 + 3)
                );
                dotProd += dot(xValues, wValues);
              } else {
                vec4 xValues = vec4(
                  getX(batch, d1, xR, xC),
                  getX(batch, d1 + 1, xR, xC),
                  getX(batch, d1 + 2, xR, xC),
                  getX(batch, d1 + 3, xR, xC)
                );
                dotProd += dot(xValues, wValues);
              }
            }

            if (${C === 1}) {

              if (${w}) {
                dotProd +=
                    getX(batch, xR, xC, ${m}) *
                    getW(wR, wC, ${m}, d2);
              } else {
                dotProd +=
                    getX(batch, ${m}, xR, xC) *
                    getW(wR, wC, ${m}, d2);
              }

            } else if (${C === 2}) {
              vec2 wValues = vec2(
                getW(wR, wC, ${m}, d2),
                getW(wR, wC, ${m} + 1, d2)
              );

              if (${w}) {
                vec2 xValues = vec2(
                  getX(batch, xR, xC, ${m}),
                  getX(batch, xR, xC, ${m} + 1)
                );
                dotProd += dot(xValues, wValues);
              } else {
                vec2 xValues = vec2(
                  getX(batch, ${m}, xR, xC),
                  getX(batch, ${m} + 1, xR, xC)
                );
                dotProd += dot(xValues, wValues);
              }

            } else if (${C === 3}) {
              vec3 wValues = vec3(
                getW(wR, wC, ${m}, d2),
                getW(wR, wC, ${m} + 1, d2),
                getW(wR, wC, ${m} + 2, d2)
              );

              if (${w}) {
                vec3 xValues = vec3(
                  getX(batch, xR, xC, ${m}),
                  getX(batch, xR, xC, ${m} + 1),
                  getX(batch, xR, xC, ${m} + 2)
                );
                dotProd += dot(xValues, wValues);
              } else {
                vec3 xValues = vec3(
                  getX(batch, ${m}, xR, xC),
                  getX(batch, ${m} + 1, xR, xC),
                  getX(batch, ${m} + 2, xR, xC)
                );
                dotProd += dot(xValues, wValues);
              }

            }
          }
        }

        float result = dotProd;
        ${A}
        ${T}
        setOutput(result);
      }
    `;
  }
}
class KC {
  constructor(e) {
    this.variableNames = ["x", "W"], this.outputShape = e.outShape;
    const t = e.padInfo.front, r = e.padInfo.top, s = e.padInfo.left, o = e.strideDepth, i = e.strideHeight, a = e.strideWidth, c = e.dilationDepth, l = e.dilationHeight, u = e.dilationWidth, d = e.filterDepth, h = e.filterHeight, f = e.filterWidth, m = Math.floor(e.inChannels / 4) * 4, C = e.inChannels % 4;
    this.userCode = `
      const ivec3 strides = ivec3(${o}, ${i}, ${a});
      const ivec3 pads = ivec3(${t}, ${r}, ${s});

      void main() {
        ivec5 coords = getOutputCoords();
        int batch = coords.x;
        int d2 = coords.u;

        ivec3 xFRCCorner = ivec3(coords.y, coords.z, coords.w) * strides - pads;
        int xFCorner = xFRCCorner.x;
        int xRCorner = xFRCCorner.y;
        int xCCorner = xFRCCorner.z;

        // Convolve x(?, ?, ?, d1) with w(:, :, :, d1, d2) to get
        // y(yF, yR, yC, d2). ? = to be determined. : = across all
        // values in that axis.
        float dotProd = 0.0;
        for (int wF = 0; wF < ${d}; wF++) {
          int xF = xFCorner + wF * ${c};

          if (xF < 0 || xF >= ${e.inDepth}) {
            continue;
          }

          for (int wR = 0; wR < ${h}; wR++) {
            int xR = xRCorner + wR * ${l};

            if (xR < 0 || xR >= ${e.inHeight}) {
              continue;
            }

            for (int wC = 0; wC < ${f}; wC++) {
              int xC = xCCorner + wC * ${u};

              if (xC < 0 || xC >= ${e.inWidth}) {
                continue;
              }

              for (int d1 = 0; d1 < ${m}; d1 += 4) {
                vec4 xValues = vec4(
                  getX(batch, xF, xR, xC, d1),
                  getX(batch, xF, xR, xC, d1 + 1),
                  getX(batch, xF, xR, xC, d1 + 2),
                  getX(batch, xF, xR, xC, d1 + 3)
                );
                vec4 wValues = vec4(
                  getW(wF, wR, wC, d1, d2),
                  getW(wF, wR, wC, d1 + 1, d2),
                  getW(wF, wR, wC, d1 + 2, d2),
                  getW(wF, wR, wC, d1 + 3, d2)
                );

                dotProd += dot(xValues, wValues);
              }

              if (${C === 1}) {
                dotProd +=
                  getX(batch, xF, xR, xC, ${m}) *
                  getW(wF, wR, wC, ${m}, d2);
              } else if (${C === 2}) {
                vec2 xValues = vec2(
                  getX(batch, xF, xR, xC, ${m}),
                  getX(batch, xF, xR, xC, ${m} + 1)
                );
                vec2 wValues = vec2(
                  getW(wF, wR, wC, ${m}, d2),
                  getW(wF, wR, wC, ${m} + 1, d2)
                );
                dotProd += dot(xValues, wValues);
              } else if (${C === 3}) {
                vec3 xValues = vec3(
                  getX(batch, xF, xR, xC, ${m}),
                  getX(batch, xF, xR, xC, ${m} + 1),
                  getX(batch, xF, xR, xC, ${m} + 2)
                );
                vec3 wValues = vec3(
                  getW(wF, wR, wC, ${m}, d2),
                  getW(wF, wR, wC, ${m} + 1, d2),
                  getW(wF, wR, wC, ${m} + 2, d2)
                );
                dotProd += dot(xValues, wValues);
              }
            }
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ol {
  constructor(e, t = !1, r = null, s = !1, o = !1) {
    this.variableNames = ["x", "W"], this.packedInputs = !0, this.packedOutput = !0, this.customUniforms = [
      { name: "pads", type: "ivec2" },
      { name: "strides", type: "ivec2" },
      { name: "dilations", type: "ivec2" },
      { name: "inDims", type: "ivec2" }
    ], this.outputShape = e.outShape, this.enableShapeUniforms = Ce(this.outputShape.length);
    const i = e.padInfo.left, a = e.strideWidth, c = e.dilationWidth, l = e.filterHeight, u = e.filterWidth, d = u;
    let h = `
       int xR; int xC; int xCOffset;
       vec4 wTexel; vec4 previous; vec4 final;`;
    for (let w = 0; w < u; w++)
      h += `
           vec4 xTexelC${w * 2};
           int xTexelC${w * 2}Ready;
           vec4 xTexelC${w * 2 + 1};
           int xTexelC${w * 2 + 1}Ready;
           vec4 xC${w};`;
    h += `
     for (int r = 0; r < ${l}; r++) {
      for (int d1 = 0; d1 < ${e.inChannels}; d1 += 2) {
       `;
    for (let w = 0; w < u; w++)
      h += `
           xTexelC${w * 2} = vec4(0.0);
           xTexelC${w * 2}Ready = 0;
           xTexelC${w * 2 + 1} = vec4(0.0);
           xTexelC${w * 2 + 1}Ready = 0;
           xC${w} = vec4(0.0);`;
    h += `
         xR = xRCorner + r * dilations[0];
         if (xR >=0 && xR < inDims[0]) {
       `;
    for (let w = 0; w < (d + 1) / 2; w++) {
      const x = w * 2;
      if (h += `
           xC = xCCorner + ${x * c};
           `, a === 1) {
        if (x < u && (i % 2 === 1 ? (h += `
                 xCOffset = xC + 1;
                 if (xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${x}Ready == 0) {
                   xTexelC${x} = getX(batch, xR, xCOffset, d1);

                   // Need to manually clear unused channels in case
                   // we're reading from recycled texture.
                   if (xCOffset + 1 >= inDims[1]) {
                     xTexelC${x}.zw = vec2(0.0);
                   }
                   xTexelC${x}Ready = 1;
                 }
               `, c === 1 && x > 0 ? h += `
                 xC${x} = vec4(xTexelC${x - 2}.zw, xTexelC${x}.xy);
                 ` : h += `
                   xCOffset = xC + 1 - 2;

                   if (xCOffset >= 0 && xCOffset < inDims[1]) {
                     previous = getX(batch, xR, xCOffset, d1);

                     // Need to manually clear unused channels in case
                     // we're reading from recycled texture.
                     if (xCOffset + 1 >= inDims[1]) {
                       previous.zw = vec2(0.0);
                     }

                     xC${x} = vec4(previous.zw, xTexelC${x}.xy);
                   } else {
                     xC${x} = vec4(0.0, 0.0, xTexelC${x}.xy);
                   }
                   `) : h += `
                 if (xC >= 0 && xC < inDims[1] && xTexelC${x}Ready == 0) {
                   xTexelC${x} = getX(batch, xR, xC, d1);
                   if (xC + 1 >= inDims[1]) {
                     xTexelC${x}.zw = vec2(0.0);
                   }
                   xTexelC${x}Ready = 1;
                 }

                 xC${x} = xTexelC${x};
                 `, x + 1 < u)) {
          const y = i % 2 === 0 ? As(c) : c;
          c % 2 === 0 && i % 2 === 1 || c % 2 !== 0 && i % 2 !== 1 ? (h += `
                   xCOffset = xC + imod(pads[1], 2) + ${y};

                   if (xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${x + 1}Ready == 0) {
                     xTexelC${x + 1} = getX(batch, xR, xCOffset, d1);

                     // Need to manually clear unused channels in case
                     // we're reading from recycled texture.
                     if (xCOffset + 1 >= inDims[1]) {
                       xTexelC${x + 1}.zw = vec2(0.0);
                     }
                     xTexelC${x + 1}Ready = 1;
                   }
                   `, c > 1 ? h += `
                     xCOffset -= 2;
                     if (xCOffset >= 0 && xCOffset < inDims[1]) {
                      previous = getX(batch, xR, xCOffset, d1);
                      xC${x + 1} = vec4(previous.zw, xTexelC${x + 1}.xy);
                     } else {
                      xC${x + 1} = vec4(0.0, 0.0, xTexelC${x + 1}.xy);
                     }
                     ` : h += `
                     xC${x + 1} = vec4(xTexelC${x}.zw, xTexelC${x + 1}.xy);
                     `) : y === 1 ? h += `
                     xC${x + 1} = xTexelC${x};
                     ` : h += `
                     xCOffset = xC + ${y};

                     if (xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${x + 1}Ready == 0) {
                       xTexelC${x + 1} = getX(batch, xR, xCOffset, d1);
                       if (xCOffset + 1 >= inDims[1]) {
                         xTexelC${x + 1}.zw = vec2(0.0);
                       }
                       xTexelC${x + 1}Ready = 1;
                     }

                     xC${x + 1} = xTexelC${x + 1};
                     `;
        }
      } else
        x < u && (i % 2 === 1 ? (h += `
                 xCOffset = xC + 1 - strides[1];
                 if(xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${x}Ready == 0) {
                   xTexelC${x} = getX(batch, xR, xCOffset, d1);
                   // Need to manually clear unused channels in case
                   // we're reading from recycled texture.
                   if (xCOffset + 1 >= inDims[1]) {
                     xTexelC${x}.zw = vec2(0.0);
                   }
                   xTexelC${x}Ready = 1;
                 }

                 if(xC + 1 >= 0 && xC + 1 < inDims[1] && xTexelC${x + 1}Ready == 0) {
                   xTexelC${x + 1} = getX(batch, xR, xC + 1, d1);
                   // Need to manually clear unused channels in case
                   // we're reading from recycled texture.
                   if (xC + 2 >= inDims[1]) {
                     xTexelC${x + 1}.zw = vec2(0.0);
                   }
                   xTexelC${x + 1}Ready = 1;
                 }

                 xC${x} = vec4(xTexelC${x}.zw, xTexelC${x + 1}.zw);
               `, x + 1 < u && (h += `
                   final = vec4(0.0);
                   xCOffset = xC + 1 + strides[1];
                   if(xCOffset >= 0 && xCOffset < inDims[1]) {
                     final = getX(batch, xR, xCOffset, d1);
                   }
                   xC${x + 1} = vec4(xTexelC${x + 1}.xy, final.xy);
                 `)) : (h += `
                 if(xC >= 0 && xC < inDims[1] && xTexelC${x}Ready == 0) {
                   xTexelC${x} = getX(batch, xR, xC, d1);
                   if (xC + 1 >= inDims[1]) {
                     xTexelC${x}.zw = vec2(0.0);
                   }
                   xTexelC${x}Ready = 1;
                 }

                 xCOffset = xC + strides[1];
                 if(xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${x + 1}Ready == 0) {
                   xTexelC${x + 1} = getX(batch, xR, xCOffset, d1);
                   if (xCOffset + 1 >= inDims[1]) {
                     xTexelC${x + 1}.zw = vec2(0.);
                   }
                   xTexelC${x + 1}Ready = 1;
                 }

                 xC${x} = vec4(
                   xTexelC${x}.xy, xTexelC${x + 1}.xy);
               `, x + 1 < u && (h += `
                   xC${x + 1} = vec4(xTexelC${x}.zw, xTexelC${x + 1}.zw);
                 `)));
      x < u && (h += `
             wTexel = getW(r, ${x}, d1, d2);
             dotProd += xC${x}.xxzz * vec4(wTexel.xy, wTexel.xy);
             if(d1 + 1 < ${e.inChannels}) {
               dotProd += xC${x}.yyww * vec4(wTexel.zw, wTexel.zw);
             }
           `, x + 1 < u && (h += `
               wTexel = getW(r, ${x + 1}, d1, d2);
               dotProd += xC${x + 1}.xxzz * vec4(wTexel.xy, wTexel.xy);
               if(d1 + 1 < ${e.inChannels}) {
                 dotProd += xC${x + 1}.yyww * vec4(wTexel.zw, wTexel.zw);
               }
             `));
    }
    h += `
     }
   `, h += `
     }
   `, h += `
     }
   `;
    let f = "", m = "";
    r && (s ? f = `vec4 activation(vec4 a) {
           vec4 b = getPreluActivationWeightsAtOutCoords();
           ${r}
         }` : o ? f = `vec4 activation(vec4 a) {
           vec4 b = getLeakyreluAlphaAtOutCoords();
           ${r}
         }` : f = `vec4 activation(vec4 x) {
           ${r}
         }`, m = "result = activation(result);");
    const C = t ? "result += getBiasAtOutCoords();" : "";
    t && this.variableNames.push("bias"), s && this.variableNames.push("preluActivationWeights"), o && this.variableNames.push("leakyreluAlpha"), this.userCode = `
       ${f}

       void main() {
         ivec4 coords = getOutputCoords();
         int batch = coords.x;
         ivec2 xRCCorner = coords.yz * strides - pads;
         int d2 = coords.w;
         int xRCorner = xRCCorner.x;
         int xCCorner = xRCCorner.y;

         //intialize dotProd with a small epsilon seems to reduce GPU accuracy loss.
         vec4 dotProd = vec4(0.000000000000001);

         ${h}

         vec4 result = dotProd - vec4(0.000000000000001);
         ${C}
         ${m}
         setOutput(result);
       }
     `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class YC {
  constructor(e, t) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !0, this.customUniforms = [
      { name: "inputShape", type: "ivec4" },
      { name: "pad", type: "ivec2" },
      { name: "stride", type: "ivec2" },
      { name: "dilation", type: "ivec2" },
      { name: "inChannels", type: "int" },
      { name: "itemsPerBlockRow", type: "int" },
      { name: "outWidth", type: "int" }
    ], this.outputShape = e, this.enableShapeUniforms = Ce(this.outputShape.length);
    const { dataFormat: r } = t, s = Se(), o = r === "channelsLast", i = o ? 1 : 2, a = o ? 2 : 3, c = this.enableShapeUniforms ? "if(blockIndex < outShape[2] && pos < outShape[1]) {" : `if(blockIndex < ${e[2]} && pos < ${e[1]}) {`;
    let l = "";
    for (let u = 0; u <= 1; u++)
      for (let d = 0; d <= 1; d++)
        l += `
          blockIndex = rc.z + ${d};
          pos = rc.y + ${u};

          ${c}
            offsetY = int(blockIndex / outWidth) * stride[0] - pad[0];
            d0 = offsetY + dilation[0] * (pos / itemsPerBlockRow);

            if(d0 < inputShape[${i}] && d0 >= 0) {
              // Use custom imod instead mod. On Intel GPU, mod may generate
              // unexpected value.
              // https://github.com/tensorflow/tfjs/issues/5447
              offsetX = imod(blockIndex, outWidth) * stride[1] - pad[1];
              d1 = offsetX + dilation[1] * (imod(pos, itemsPerBlockRow) /
                  inChannels);

              if(d1 < inputShape[${a}] && d1 >= 0) {

                ch = imod(pos, inChannels);

                if (${o}) {
                  innerDims = vec2(d1, ch);
                  result[${u * 2 + d}] = getChannel(
                    getA(rc.x, d0, int(innerDims.x),
                    int(innerDims.y)), innerDims);
                } else {
                  innerDims = vec2(d0, d1);
                  result[${u * 2 + d}] = getChannel(
                    getA(rc.x, ch, int(innerDims.x),
                    int(innerDims.y)), innerDims);
                }
              }
            }
          }
        `;
    this.userCode = `
      void main() {
        ivec3 rc = getOutputCoords();

        vec4 result = vec4(0);

        int blockIndex, pos, offsetY, d0, offsetX, d1, ch;
        vec2 innerDims;

        ${l}

        ${s.output} = result;
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function kr(n, e) {
  const t = n.length;
  return t >= 3 ? e ? [
    ...n.slice(0, -3),
    n[t - 3] * n[t - 2],
    n[t - 1]
    /* channel */
  ] : [
    ...n.slice(0, -3),
    n[t - 3],
    n[t - 2] * n[t - 1]
    /* height * width */
  ] : !e && t === 1 && n[0] > 1 ? [n[0], 1] : null;
}
function il({ x: n, filter: e, convInfo: t, backend: r, bias: s = null, preluActivationWeights: o = null, leakyreluAlpha: i = 0, activation: a = null }) {
  const c = n.shape, l = r.texData.get(n.dataId), u = t.inChannels, d = c[0] * c[1] * c[2], h = t.outChannels, f = t.dataFormat === "channelsLast", m = !1, C = !1;
  let w;
  const x = [];
  if (o != null) {
    const I = kr(o.shape, f);
    I != null && (o = D({
      inputs: { x: o },
      backend: r,
      attrs: { shape: I }
    }), x.push(o));
  }
  if (s != null) {
    const I = kr(s.shape, f);
    I != null && (s = D({ inputs: { x: s }, backend: r, attrs: { shape: I } }), x.push(s));
  }
  if (!((d === 1 || h === 1) && u > Zc) && l.isPacked && f && l.texture != null && c[2] % 2 !== 0 && ge(l.shape.slice(-3), c.slice(-3))) {
    const I = c[0] * c[1] * (c[2] + 1), T = {
      dataId: n.dataId,
      shape: [1, I, t.inChannels],
      dtype: n.dtype
    }, A = l.shape;
    l.shape = l.shape.slice(), l.shape[l.shape.length - 2]++, O(Rr(l.shape, T.shape), () => `packed reshape ${l.shape} to ${T.shape} isn't free`);
    const F = D({
      inputs: { x: e },
      backend: r,
      attrs: { shape: [1, t.inChannels, t.outChannels] }
    });
    x.push(F);
    const k = Nr({
      a: T,
      b: F,
      backend: r,
      transposeA: m,
      transposeB: C,
      bias: s,
      activation: a,
      preluActivationWeights: o,
      leakyreluAlpha: i
    }), U = r.texData.get(k.dataId);
    O(U.isPacked, () => "batchMatMul result is expected to be packed"), l.shape = A, U.shape = t.outShape, w = De({ inputs: { x: k }, backend: r }), w.shape = t.outShape, x.push(k);
  } else {
    const I = t.outHeight * t.outWidth, T = D({
      inputs: { x: n },
      backend: r,
      attrs: {
        shape: f ? [t.batchSize, I, t.inChannels] : [t.batchSize, t.inChannels, I]
      }
    }), A = D({
      inputs: { x: e },
      backend: r,
      attrs: { shape: [1, t.inChannels, t.outChannels] }
    }), F = Nr({
      a: f ? T : A,
      b: f ? A : T,
      transposeA: !f,
      transposeB: C,
      backend: r,
      bias: s,
      activation: a,
      preluActivationWeights: o,
      leakyreluAlpha: i
    });
    w = D({ inputs: { x: F }, backend: r, attrs: { shape: t.outShape } }), x.push(T), x.push(A), x.push(F);
  }
  for (const I of x)
    r.disposeIntermediateTensorInfo(I);
  return w;
}
function al({ x: n, filter: e, convInfo: t, backend: r, bias: s = null, preluActivationWeights: o = null, leakyreluAlpha: i = 0, activation: a = null }) {
  const { filterWidth: c, filterHeight: l, inChannels: u, outWidth: d, outHeight: h, dataFormat: f } = t, m = f === "channelsLast", C = c * l * u, w = h * d, x = [t.batchSize, C, w], y = !0, v = !1, I = [];
  if (o != null) {
    const le = kr(o.shape, m);
    le != null && (o = D({
      inputs: { x: o },
      backend: r,
      attrs: { shape: le }
    }), I.push(o));
  }
  if (s != null) {
    const le = kr(s.shape, m);
    le != null && (s = D({ inputs: { x: s }, backend: r, attrs: { shape: le } }), I.push(s));
  }
  const T = D({
    inputs: { x: e },
    backend: r,
    attrs: { shape: [1, C, _(e.shape) / C] }
  });
  I.push(T);
  const A = new YC(x, t), F = [
    n.shape,
    [t.padInfo.top, t.padInfo.left],
    [t.strideHeight, t.strideWidth],
    [t.dilationHeight, t.dilationWidth],
    [t.inChannels],
    [t.filterWidth * t.inChannels],
    [t.outWidth]
  ], k = r.runWebGLProgram(A, [n], "float32", F), U = D({ inputs: { x: k }, backend: r, attrs: { shape: x } });
  I.push(k), I.push(U);
  const V = s != null, G = o != null, j = a === "leakyrelu", be = a ? jn(a, !0) : null, ie = new Qc(m ? U.shape : T.shape, m ? T.shape : U.shape, m ? [t.batchSize, w, t.outChannels] : [t.batchSize, t.outChannels, w], y, v, V, be, G, j), ce = m ? [U, T] : [T, U];
  if (s && ce.push(s), G && ce.push(o), j) {
    const le = r.makeTensorInfo([], "float32", vn(i, "float32"));
    ce.push(le), I.push(le);
  }
  const Ne = r.runWebGLProgram(ie, ce, "float32"), ke = D({ inputs: { x: Ne }, backend: r, attrs: { shape: t.outShape } });
  I.push(Ne);
  for (const le of I)
    r.disposeIntermediateTensorInfo(le);
  return ke;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function QC(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, filter: o } = e, { strides: i, pad: a, dataFormat: c, dilations: l, dimRoundingMode: u } = r, d = En(c), h = et(s.shape, o.shape, i, l, a, u, !1, d);
  let f;
  if (h.filterHeight === 1 && h.filterWidth === 1 && h.dilationHeight === 1 && h.dilationWidth === 1 && h.strideHeight === 1 && h.strideWidth === 1 && (h.padInfo.type === "SAME" || h.padInfo.type === "VALID"))
    f = il({ x: s, filter: o, convInfo: h, backend: t });
  else if (h.strideWidth <= 2 && d === "channelsLast" && E().getBool("WEBGL_EXP_CONV")) {
    const C = new ol(h), w = [
      [h.padInfo.top, h.padInfo.left],
      [h.strideHeight, h.strideWidth],
      [h.dilationHeight, h.dilationWidth],
      [h.inHeight, h.inWidth]
    ];
    f = t.runWebGLProgram(C, [s, o], "float32", w);
  } else if (E().getBool("WEBGL_CONV_IM2COL"))
    f = al({ x: s, filter: o, convInfo: h, backend: t });
  else {
    const C = new sl(h);
    f = t.runWebGLProgram(C, [s, o], "float32");
  }
  const m = D({ inputs: { x: f }, backend: t, attrs: { shape: h.outShape } });
  return t.disposeIntermediateTensorInfo(f), m;
}
const ZC = {
  kernelName: $u,
  backendName: "webgl",
  kernelFunc: QC
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class JC {
  constructor(e) {
    this.variableNames = ["x", "dy"], this.outputShape = e.filterShape;
    const t = e.strideHeight, r = e.strideWidth, s = e.padInfo.top, o = e.padInfo.left, i = e.dataFormat === "channelsLast";
    this.userCode = `
      void main() {
        ivec4 coords = getOutputCoords();
        int wR = coords.x;
        int wC = coords.y;
        int d1 = coords.z;
        int d2 = coords.w;

        // Convolve x(?, ?, d1) with dy(:, :, d2) to get dw(wR, wC, d1, d2).
        // ? = to be determined. : = across all values in that axis.
        float dotProd = 0.0;

        for (int b = 0; b < ${e.batchSize}; b++) {
          for (int yR = 0; yR < ${e.outHeight}; yR++) {
            int xR = wR + yR * ${t} - ${s};

            if (xR < 0 || xR >= ${e.inHeight}) {
              continue;
            }

            for (int yC = 0; yC < ${e.outWidth}; yC++) {
              int xC = wC + yC * ${r} - ${o};

              if (xC < 0 || xC >= ${e.inWidth}) {
                continue;
              }

              ${i ? `float dyValue = getDy(b, yR, yC, d2);
              float xValue = getX(b, xR, xC, d1);
              dotProd += (xValue * dyValue);` : `float dyValue = getDy(b, d2, yR, yC);
              float xValue = getX(b, d1, xR, xC);
              dotProd += (xValue * dyValue);`}
            }
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
class eb {
  constructor(e) {
    this.variableNames = ["dy", "W"], this.outputShape = e.inShape;
    const t = e.filterHeight, r = e.filterWidth, s = e.strideHeight, o = e.strideWidth, i = e.dataFormat === "channelsLast", a = t - 1 - e.padInfo.top, c = r - 1 - e.padInfo.left, l = i ? 1 : 2, u = i ? 2 : 3, d = i ? 3 : 1;
    this.userCode = `
      const ivec2 pads = ivec2(${a}, ${c});

      void main() {
        ivec4 coords = getOutputCoords();
        int batch = coords[0];
        int d1 = coords[${d}];

        ivec2 dyCorner = ivec2(coords[${l}], coords[${u}]) - pads;
        int dyRCorner = dyCorner.x;
        int dyCCorner = dyCorner.y;

        // Convolve dy(?, ?, d2) with w(:, :, d1, d2) to compute dx(xR, xC, d1).
        // ? = to be determined. : = across all values in that axis.
        float dotProd = 0.0;
        for (int wR = 0; wR < ${t}; wR++) {
          float dyR = float(dyRCorner + wR) / ${s}.0;

          if (dyR < 0.0 || dyR >= ${e.outHeight}.0 || fract(dyR) > 0.0) {
            continue;
          }
          int idyR = int(dyR);

          int wRPerm = ${t} - 1 - wR;

          for (int wC = 0; wC < ${r}; wC++) {
            float dyC = float(dyCCorner + wC) / ${o}.0;

            if (dyC < 0.0 || dyC >= ${e.outWidth}.0 ||
                fract(dyC) > 0.0) {
              continue;
            }
            int idyC = int(dyC);

            int wCPerm = ${r} - 1 - wC;

            for (int d2 = 0; d2 < ${e.outChannels}; d2++) {

              if (${i}) {
                float xValue = getDy(batch, idyR, idyC, d2);
                float wValue = getW(wRPerm, wCPerm, d1, d2);
                dotProd += xValue * wValue;
              } else {
                float xValue = getDy(batch, d2, idyR, idyC);
                float wValue = getW(wRPerm, wCPerm, d1, d2);
                dotProd += xValue * wValue;
              }

            }
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
class tb {
  constructor(e) {
    this.variableNames = ["x", "dy"], this.outputShape = e.filterShape;
    const t = e.strideDepth, r = e.strideHeight, s = e.strideWidth, o = e.padInfo.front, i = e.padInfo.top, a = e.padInfo.left;
    this.userCode = `
      void main() {
        ivec5 coords = getOutputCoords();
        int wF = coords.x;
        int wR = coords.y;
        int wC = coords.z;
        int d1 = coords.w;
        int d2 = coords.u;

        float dotProd = 0.0;

        for (int b = 0; b < ${e.batchSize}; b++) {
          for (int yF = 0; yF < ${e.outDepth}; yF++) {
            int xF = wF + yF * ${t} - ${o};

            if (xF < 0 || xF >= ${e.inDepth}) {
              continue;
            }

            for (int yR = 0; yR < ${e.outHeight}; yR++) {
              int xR = wR + yR * ${r} - ${i};

              if (xR < 0 || xR >= ${e.inHeight}) {
                continue;
              }

              for (int yC = 0; yC < ${e.outWidth}; yC++) {
                int xC = wC + yC * ${s} - ${a};

                if (xC < 0 || xC >= ${e.inWidth}) {
                  continue;
                }

                float dyValue = getDy(b, yF, yR, yC, d2);
                float xValue = getX(b, xF, xR, xC, d1);
                dotProd += (xValue * dyValue);
              }
            }
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
class nb {
  constructor(e) {
    this.variableNames = ["dy", "W"], this.outputShape = e.inShape;
    const t = e.filterDepth, r = e.filterHeight, s = e.filterWidth, o = e.strideDepth, i = e.strideHeight, a = e.strideWidth, c = t - 1 - e.padInfo.front, l = r - 1 - e.padInfo.top, u = s - 1 - e.padInfo.left;
    this.userCode = `
      const ivec3 pads = ivec3(${c}, ${l}, ${u});

      void main() {
        ivec5 coords = getOutputCoords();
        int batch = coords.x;
        int d1 = coords.u;


        ivec3 dyCorner = ivec3(coords.y, coords.z, coords.w) - pads;
        int dyFCorner = dyCorner.x;
        int dyRCorner = dyCorner.y;
        int dyCCorner = dyCorner.z;

        float dotProd = 0.0;
        for (int wF = 0; wF < ${t}; wF++) {
          float dyF = float(dyFCorner + wF) / ${o}.0;

          if (dyF < 0.0 || dyF >= ${e.outDepth}.0 || fract(dyF) > 0.0) {
            continue;
          }
          int idyF = int(dyF);

          int wFPerm = ${t} - 1 - wF;

          for (int wR = 0; wR < ${r}; wR++) {
            float dyR = float(dyRCorner + wR) / ${i}.0;

            if (dyR < 0.0 || dyR >= ${e.outHeight}.0 ||
              fract(dyR) > 0.0) {
              continue;
            }
            int idyR = int(dyR);

            int wRPerm = ${r} - 1 - wR;

            for (int wC = 0; wC < ${s}; wC++) {
              float dyC = float(dyCCorner + wC) / ${a}.0;

              if (dyC < 0.0 || dyC >= ${e.outWidth}.0 ||
                  fract(dyC) > 0.0) {
                continue;
              }
              int idyC = int(dyC);

              int wCPerm = ${s} - 1 - wC;

              for (int d2 = 0; d2 < ${e.outChannels}; d2++) {
                float xValue = getDy(batch, idyF, idyR, idyC, d2);
                float wValue = getW(wFPerm, wRPerm, wCPerm, d1, d2);
                dotProd += xValue * wValue;
              }
            }
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function rb(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, dy: o } = e, { strides: i, pad: a, dataFormat: c, dimRoundingMode: l, filterShape: u } = r, d = En(c), h = et(s.shape, u, i, 1, a, l, !1, d), f = new JC(h);
  return t.runWebGLProgram(f, [s, o], "float32");
}
const sb = {
  kernelName: vu,
  backendName: "webgl",
  kernelFunc: rb
};
/**
 * @license
 * Copyright 2023 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ob {
  constructor(e) {
    this.variableNames = ["dy", "W"], this.packedInputs = !0, this.packedOutput = !0, this.customUniforms = [
      { name: "strides", type: "vec2" }
    ], this.outputShape = e.inShape, this.enableShapeUniforms = Ce(this.outputShape.length);
    const t = e.filterHeight, r = e.filterWidth, s = t - 1 - e.padInfo.top, o = r - 1 - e.padInfo.left;
    this.userCode = `
      const ivec2 pads = ivec2(${s}, ${o});

      void main() {
        ivec4 coords = getOutputCoords();
        int batch = coords[0];
        int d1 = coords[3];

        ivec2 dyCorner = ivec2(coords[1], coords[2]) - pads;
        int dyRCorner = dyCorner.x;
        int dyCCorner = dyCorner.y;

        vec4 result = vec4(0.);
        for (int wR = 0; wR < ${t}; wR++) {
          float dyR = float(dyRCorner + wR) / strides[0];
          if (dyR < 0.0 || dyR >= ${e.outHeight}.0 || fract(dyR) > 0.0) {
            continue;
          }
          int idyR = int(dyR);
          int wRPerm = ${t} - 1 - wR;

          for (int wC = 0; wC < ${r}; wC++) {
            int wCPerm = ${r} - 1 - wC;

            float dyC = float(dyCCorner + wC) / strides[1];
            bool idyCVal = (dyC >= 0.0) && (dyC < ${e.outWidth}.0)
              && (fract(dyC) == 0.0);
            int idyC = int(dyC);

            float dyC2 = float(dyCCorner + wC + 1) / strides[1];
            bool idyCVal2 = (dyC2 >= 0.0) && (dyC2 < ${e.outWidth}.0)
              && (fract(dyC2) == 0.0);
            int idyC2 = int(dyC2);

            if (idyCVal && idyCVal2) {
              for (int d2 = 0; d2 < ${e.outChannels}; d2 += 2) {
                vec4 wValue = getW(wRPerm, wCPerm, d1, d2);
                vec4 dySample = getDy(batch, idyR, idyC, d2);
                vec4 dySample2 = (idyC / 2 == idyC2 / 2) ?
                  dySample : getDy(batch, idyR, idyC2, d2);

                vec2 dyValue = mod(float(idyC), 2.) == 0. ?
                  dySample.xy : dySample.zw;
                result.xy += vec2(dot(dyValue, wValue.xy),
                  dot(dyValue, wValue.zw));

                dyValue = mod(float(idyC2), 2.) == 0. ?
                  dySample2.xy : dySample2.zw;
                result.zw += vec2(dot(dyValue, wValue.xy),
                  dot(dyValue, wValue.zw));
              }
            } else if (idyCVal) {
              for (int d2 = 0; d2 < ${e.outChannels}; d2 += 2) {
                vec4 wValue = getW(wRPerm, wCPerm, d1, d2);
                vec4 dySample = getDy(batch, idyR, idyC, d2);
                vec2 dyValue = mod(float(idyC), 2.) == 0. ?
                  dySample.xy : dySample.zw;
                result.xy += vec2(dot(dyValue, wValue.xy),
                  dot(dyValue, wValue.zw));
              }
            } else if (idyCVal2) {
              for (int d2 = 0; d2 < ${e.outChannels}; d2 += 2) {
                vec4 wValue = getW(wRPerm, wCPerm, d1, d2);
                vec4 dySample = getDy(batch, idyR, idyC2, d2);
                vec2 dyValue = mod(float(idyC2), 2.) == 0. ?
                  dySample.xy : dySample.zw;
                result.zw += vec2(dot(dyValue, wValue.xy),
                  dot(dyValue, wValue.zw));
              }
            }
          }
        }
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function ib(n) {
  const { inputs: e, backend: t, attrs: r } = n, { dy: s, filter: o } = e, { inputShape: i, strides: a, pad: c, dataFormat: l, dimRoundingMode: u } = r, d = En(l), h = et(i, o.shape, a, 1, c, u, !1, d);
  if (E().getBool("WEBGL_PACK") && d === "channelsLast") {
    const f = [
      [h.strideHeight, h.strideWidth]
    ], m = new ob(h);
    return t.runWebGLProgram(m, [s, o], "float32", f);
  } else {
    const f = new eb(h);
    return t.runWebGLProgram(f, [s, o], "float32");
  }
}
const ab = {
  kernelName: Iu,
  backendName: "webgl",
  kernelFunc: ib
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function cb(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, filter: o } = e, { strides: i, pad: a, dilations: c } = r, l = Jn(s.shape, o.shape, i, c, a), u = new KC(l);
  return t.runWebGLProgram(u, [s, o], "float32");
}
const lb = {
  kernelName: Su,
  backendName: "webgl",
  kernelFunc: cb
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function ub(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, dy: o } = e, { strides: i, pad: a, filterShape: c } = r, l = Jn(s.shape, c, i, 1, a), u = new tb(l);
  return t.runWebGLProgram(u, [s, o], "float32");
}
const db = {
  kernelName: Eu,
  backendName: "webgl",
  kernelFunc: ub
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function hb(n) {
  const { inputs: e, backend: t, attrs: r } = n, { dy: s, filter: o } = e, { pad: i, strides: a, inputShape: c } = r, l = Jn(c, o.shape, a, 1, i), u = new nb(l);
  return t.runWebGLProgram(u, [s, o], "float32");
}
const fb = {
  kernelName: Ru,
  backendName: "webgl",
  kernelFunc: hb
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const pb = Dn + `
  return cos(x);
`, mb = `
  vec4 result = cos(x);
  bvec4 isNaN = isnan(x);
  ${en}
  return result;
`, gb = H({ opSnippet: pb, packedOpSnippet: mb }), xb = {
  kernelName: Tu,
  backendName: "webgl",
  kernelFunc: gb
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const wb = `
  float e2x = exp(-x);
  return (e2x + 1.0 / e2x) / 2.0;
`, Cb = H({ opSnippet: wb }), bb = {
  kernelName: Nu,
  backendName: "webgl",
  kernelFunc: Cb
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class yb {
  constructor(e, t, r, s, o) {
    this.variableNames = ["Image", "Boxes", "BoxInd"], this.outputShape = [];
    const [i, a, c, l] = e, [u] = t, [d, h] = r;
    this.outputShape = [u, d, h, l];
    const f = s === "bilinear" ? 1 : 0, [m, C] = [`${a - 1}.0`, `${c - 1}.0`], [w, x, y] = d > 1 ? [
      `${(a - 1) / (d - 1)}`,
      "(y2-y1) * height_ratio",
      `y1*${m} + float(y)*(height_scale)`
    ] : [
      "0.0",
      "0.0",
      `0.5 * (y1+y2) * ${m}`
    ], [v, I, T] = h > 1 ? [
      `${(c - 1) / (h - 1)}`,
      "(x2-x1) * width_ratio",
      `x1*${C} + float(x)*(width_scale)`
    ] : [
      "0.0",
      "0.0",
      `0.5 * (x1+x2) * ${C}`
    ];
    this.userCode = `
      const float height_ratio = float(${w});
      const float width_ratio = float(${v});
      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int y = coords[1];
        int x = coords[2];
        int d = coords[3];

        // get box vals
        float y1 = getBoxes(b,0);
        float x1 = getBoxes(b,1);
        float y2 = getBoxes(b,2);
        float x2 = getBoxes(b,3);

        // get image in batch index
        int bInd = round(getBoxInd(b));
        if(bInd < 0 || bInd >= ${i}) {
          return;
        }

        float height_scale = ${x};
        float width_scale = ${I};

        float in_y = ${y};
        if( in_y < 0.0 || in_y > ${m} ) {
          setOutput(float(${o}));
          return;
        }
        float in_x = ${T};
        if( in_x < 0.0 || in_x > ${C} ) {
          setOutput(float(${o}));
          return;
        }

        vec2 sourceFracIndexCR = vec2(in_x,in_y);
        if(${f} == 1) {
          // Compute the four integer indices.
          ivec2 sourceFloorCR = ivec2(sourceFracIndexCR);
          ivec2 sourceCeilCR = ivec2(ceil(sourceFracIndexCR));

          float topLeft = getImage(b, sourceFloorCR.y, sourceFloorCR.x, d);
          float bottomLeft = getImage(b, sourceCeilCR.y, sourceFloorCR.x, d);
          float topRight = getImage(b, sourceFloorCR.y, sourceCeilCR.x, d);
          float bottomRight = getImage(b, sourceCeilCR.y, sourceCeilCR.x, d);

          vec2 fracCR = sourceFracIndexCR - vec2(sourceFloorCR);

          float top = topLeft + (topRight - topLeft) * fracCR.x;
          float bottom = bottomLeft + (bottomRight - bottomLeft) * fracCR.x;
          float newValue = top + (bottom - top) * fracCR.y;
          setOutput(newValue);
        } else {
          // Compute the coordinators of nearest neighbor point.
          ivec2 sourceNearestCR = ivec2(floor(
            sourceFracIndexCR + vec2(0.5,0.5)));
          float newValue = getImage(b, sourceNearestCR.y, sourceNearestCR.x, d);
          setOutput(newValue);
        }
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const $b = (n) => {
  const { inputs: e, backend: t, attrs: r } = n, { image: s, boxes: o, boxInd: i } = e, { cropSize: a, method: c, extrapolationValue: l } = r, u = new yb(s.shape, o.shape, a, c, l);
  return t.runWebGLProgram(u, [s, o, i], "float32");
}, vb = {
  kernelName: Fu,
  backendName: "webgl",
  kernelFunc: $b
};
var Kn;
(function(n) {
  n.Prod = "*", n.Sum = "+";
})(Kn || (Kn = {}));
class hi {
  constructor(e, t, r, s) {
    this.op = e, this.outputShape = t, this.variableNames = ["x"], this.customUniforms = [{ name: "index", type: "float" }];
    const o = this.outputShape.length, i = this.op === Kn.Prod ? "1.0" : "0.0", a = r ? i : `getX(${fi(o, "coords", this.op)})`, c = this.outputShape[this.outputShape.length - 1];
    let l = "", u = "";
    r ? (l = s ? `end != ${c - 1}` : "end != 0", u = s ? "end + 1" : "end - 1") : (l = s ? `end + pow2 < ${c}` : "end >= pow2", u = s ? "end + pow2" : "end - pow2"), this.userCode = `
      void main() {
        ${K(o)} coords = getOutputCoords();
        int end = ${pi(o, "coords", this.op)};
        float val = ${a};
        int pow2 = int(pow(2.0, index));
        if (${l}) {
          int idx = ${u};
          ${pi(o, "coords", this.op)} = idx;
          val ${this.op}= getX(${fi(o, "coords", this.op)});
        }
        setOutput(val);
      }
    `;
  }
}
function fi(n, e, t) {
  if (n === 1)
    return `${e}`;
  if (n === 2)
    return `${e}.x, ${e}.y`;
  if (n === 3)
    return `${e}.x, ${e}.y, ${e}.z`;
  if (n === 4)
    return `${e}.x, ${e}.y, ${e}.z, ${e}.w`;
  throw new Error(`Cumulative ${t} for rank ${n} is not yet supported`);
}
function pi(n, e, t) {
  if (n === 1)
    return `${e}`;
  if (n === 2)
    return `${e}.y`;
  if (n === 3)
    return `${e}.z`;
  if (n === 4)
    return `${e}.w`;
  throw new Error(`Cumulative ${t} for rank ${n} is not yet supported`);
}
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function cl(n, e, t, r, s, o) {
  const i = e.shape.length, a = He([r], i);
  let c = e;
  a != null && (c = Ie({ inputs: { x: e }, backend: t, attrs: { perm: a } }));
  const l = Xe(1, i)[0];
  if (l !== i - 1)
    throw new Error(`WebGL cumprod shader expects an inner-most axis=${e.shape.length - 1} but got axis=${r}`);
  const u = c.shape[l];
  let d = De({ inputs: { x: c }, backend: t });
  for (let h = 0; h <= Math.ceil(Math.log2(u)) - 1; h++) {
    const f = new hi(n, c.shape, !1, o), m = [[h]], C = d;
    d = t.runWebGLProgram(f, [d], d.dtype, m), t.disposeIntermediateTensorInfo(C);
  }
  if (s) {
    const h = new hi(n, c.shape, s, o), f = d;
    d = t.runWebGLProgram(h, [d], d.dtype), t.disposeIntermediateTensorInfo(f);
  }
  if (a != null) {
    const h = Xs(a), f = Ie({ inputs: { x: d }, backend: t, attrs: { perm: h } });
    return t.disposeIntermediateTensorInfo(d), t.disposeIntermediateTensorInfo(c), f;
  }
  return d;
}
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ib(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { axis: o, exclusive: i, reverse: a } = r;
  return cl(Kn.Prod, s, t, o, i, a);
}
const Sb = {
  kernelName: ku,
  backendName: "webgl",
  kernelFunc: Ib
};
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Eb(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { axis: o, exclusive: i, reverse: a } = r;
  return cl(Kn.Sum, s, t, o, i, a);
}
const Rb = {
  kernelName: Au,
  backendName: "webgl",
  kernelFunc: Eb
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Tb(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, weights: o } = e, { size: i, binaryOutput: a } = r;
  if (s.shape.length === 1) {
    const c = t.readSync(s.dataId), l = t.readSync(o.dataId), u = Wc(c, l, o.dtype, o.shape, i);
    return t.makeTensorInfo([i], o.dtype, u);
  } else if (s.shape.length === 2) {
    const c = t.bufferSync(s), l = t.bufferSync(o), u = F0(c, l, i, a);
    return t.makeTensorInfo(u.shape, o.dtype, u.values);
  }
  throw new Error(`Error in denseBincount: input must be at most rank 2, but got rank${s.shape.length}.`);
}
const Nb = {
  kernelName: Du,
  backendName: "webgl",
  kernelFunc: Tb
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class kb {
  constructor(e, t, r) {
    this.variableNames = ["x"], this.outputShape = [], this.outputShape = e, this.blockSize = t, this.dataFormat = r, this.userCode = `
    void main() {
      ivec4 coords = getOutputCoords();
      int b = coords[0];
      int h = ${this.getHeightCoordString()};
      int w = ${this.getWidthCoordString()};
      int d = ${this.getDepthCoordString()};

      int in_h = h / ${t};
      int offset_h = imod(h, ${t});
      int in_w = w / ${t};
      int offset_w = imod(w, ${t});
      int offset_d = (offset_h * ${t} + offset_w) *
        ${this.getOutputDepthSize()};
      int in_d = d + offset_d;

      float result = ${this.getInputSamplingString()};
      setOutput(result);
    }
  `;
  }
  getHeightCoordString() {
    return this.dataFormat === "NHWC" ? "coords[1]" : "coords[2]";
  }
  getWidthCoordString() {
    return this.dataFormat === "NHWC" ? "coords[2]" : "coords[3]";
  }
  getDepthCoordString() {
    return this.dataFormat === "NHWC" ? "coords[3]" : "coords[1]";
  }
  getOutputDepthSize() {
    return this.dataFormat === "NHWC" ? this.outputShape[3] : this.outputShape[1];
  }
  getInputSamplingString() {
    return this.dataFormat === "NHWC" ? "getX(b, in_h, in_w, in_d)" : "getX(b, in_d, in_h, in_w)";
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ab(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { blockSize: o, dataFormat: i } = r, a = s.shape[0], c = i === "NHWC" ? s.shape[1] : s.shape[2], l = i === "NHWC" ? s.shape[2] : s.shape[3], u = i === "NHWC" ? s.shape[3] : s.shape[1], d = c * o, h = l * o, f = u / (o * o), m = i === "NHWC" ? [a, d, h, f] : [a, f, d, h], C = new kb(m, o, i);
  return t.runWebGLProgram(C, [s], s.dtype);
}
const Fb = {
  kernelName: Ou,
  backendName: "webgl",
  kernelFunc: Ab
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ll {
  constructor(e, t = !1, r = null, s = !1, o = !1) {
    this.variableNames = ["x", "W"], this.customUniforms = [
      { name: "pads", type: "ivec2" },
      { name: "strides", type: "ivec2" },
      { name: "dilations", type: "ivec2" },
      { name: "inDims", type: "ivec2" }
    ], this.outputShape = e.outShape, this.enableShapeUniforms = Ce(this.outputShape.length);
    const i = e.filterHeight, a = e.filterWidth, c = e.outChannels / e.inChannels;
    let l = "", u = "";
    r && (s ? l = `float activation(float a) {
          float b = getPreluActivationWeightsAtOutCoords();
          ${r}
        }` : o ? l = `float activation(float a) {
          float b = getLeakyreluAlphaAtOutCoords();
          ${r}
        }` : l = `
          float activation(float x) {
            ${r}
          }
        `, u = "result = activation(result);");
    const d = t ? "result += getBiasAtOutCoords();" : "";
    t && this.variableNames.push("bias"), s && this.variableNames.push("preluActivationWeights"), o && this.variableNames.push("leakyreluAlpha"), this.userCode = `
      ${l}

      void main() {
        ivec4 coords = getOutputCoords();
        int batch = coords.x;
        ivec2 xRCCorner = coords.yz * strides - pads;
        int d2 = coords.w;
        int d1 = d2 / ${c};
        int q = d2 - d1 * ${c};

        int xRCorner = xRCCorner.x;
        int xCCorner = xRCCorner.y;

        // Convolve x(?, ?, d1) with w(:, :, d1, q) to get y(yR, yC, d2).
        // ? = to be determined. : = across all values in that axis.
        float dotProd = 0.0;
        // TO DO(dsmilkov): Flatten the two for loops and vec4 the operations.
        for (int wR = 0; wR < ${i}; wR++) {
          int xR = xRCorner + wR * dilations[0];

          if (xR < 0 || xR >= inDims[0]) {
            continue;
          }

          for (int wC = 0; wC < ${a}; wC++) {
            int xC = xCCorner + wC * dilations[1];

            if (xC < 0 || xC >= inDims[1]) {
              continue;
            }

            float xVal = getX(batch, xR, xC, d1);
            float wVal = getW(wR, wC, d1, q);
            dotProd += xVal * wVal;
          }
        }

        float result = dotProd;
        ${d}
        ${u}
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ul {
  constructor(e, t = !1, r = null, s = !1, o = !1) {
    this.variableNames = ["x", "W"], this.packedInputs = !0, this.packedOutput = !0, this.customUniforms = [
      { name: "pads", type: "ivec2" },
      { name: "strides", type: "ivec2" },
      { name: "dilations", type: "ivec2" },
      { name: "inDims", type: "ivec2" }
    ], this.outputShape = e.outShape, this.enableShapeUniforms = Ce(this.outputShape.length);
    const i = e.outChannels / e.inChannels, a = e.padInfo.left, c = e.strideWidth, l = e.dilationWidth, u = e.filterHeight, d = e.filterWidth, h = d;
    let f = `
      int xR; int xC; int xCOffset;
      vec4 wTexel; vec4 previous; vec4 final;`;
    for (let x = 0; x < d; x++)
      f += `
          vec4 xTexelC${x * 2};
          int xTexelC${x * 2}Ready;
          vec4 xTexelC${x * 2 + 1};
          int xTexelC${x * 2 + 1}Ready;
          vec4 xC${x};`;
    f += `
    for (int r = 0; r < ${u}; r++) {
      `;
    for (let x = 0; x < d; x++)
      f += `
          xTexelC${x * 2} = vec4(0.0);
          xTexelC${x * 2}Ready = 0;
          xTexelC${x * 2 + 1} = vec4(0.0);
          xTexelC${x * 2 + 1}Ready = 0;
          xC${x} = vec4(0.0);`;
    f += `
        xR = xRCorner + r * dilations[0];
        if (xR >=0 && xR < inDims[0]) {
      `;
    for (let x = 0; x < (h + 1) / 2; x++) {
      const y = x * 2;
      if (f += `
          xC = xCCorner + ${y * l};
          `, c === 1) {
        if (y < d && (a % 2 === 1 ? (f += `
                xCOffset = xC + 1;
                if (xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${y}Ready == 0) {
                  xTexelC${y} = getX(batch, xR, xCOffset, d1);

                  // Need to manually clear unused channels in case
                  // we're reading from recycled texture.
                  if (xCOffset + 1 >= inDims[1]) {
                    xTexelC${y}.zw = vec2(0.0);
                  }
                  xTexelC${y}Ready = 1;
                }
              `, l === 1 && y > 0 ? f += `
                xC${y} = vec4(xTexelC${y - 2}.zw, xTexelC${y}.xy);
                ` : f += `
                  xCOffset = xC + 1 - 2;

                  if (xCOffset >= 0 && xCOffset < inDims[1]) {
                    previous = getX(batch, xR, xCOffset, d1);

                    // Need to manually clear unused channels in case
                    // we're reading from recycled texture.
                    if (xCOffset + 1 >= inDims[1]) {
                      previous.zw = vec2(0.0);
                    }

                    xC${y} = vec4(previous.zw, xTexelC${y}.xy);
                  } else {
                    xC${y} = vec4(0.0, 0.0, xTexelC${y}.xy);
                  }
                  `) : f += `
                if (xC >= 0 && xC < inDims[1] && xTexelC${y}Ready == 0) {
                  xTexelC${y} = getX(batch, xR, xC, d1);
                  if (xC + 1 >= inDims[1]) {
                    xTexelC${y}.zw = vec2(0.0);
                  }
                  xTexelC${y}Ready = 1;
                }

                xC${y} = xTexelC${y};
                `, y + 1 < d)) {
          const v = a % 2 === 0 ? As(l) : l;
          l % 2 === 0 && a % 2 === 1 || l % 2 !== 0 && a % 2 !== 1 ? (f += `
                  xCOffset = xC + imod(pads[1], 2) + ${v};

                  if (xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${y + 1}Ready == 0) {
                    xTexelC${y + 1} = getX(batch, xR, xCOffset, d1);

                    // Need to manually clear unused channels in case
                    // we're reading from recycled texture.
                    if (xCOffset + 1 >= inDims[1]) {
                      xTexelC${y + 1}.zw = vec2(0.0);
                    }
                    xTexelC${y + 1}Ready = 1;
                  }
                  `, l > 1 ? f += `
                    xCOffset -= 2;
                    if (xCOffset >= 0 && xCOffset < inDims[1]) {
                     previous = getX(batch, xR, xCOffset, d1);
                     xC${y + 1} = vec4(previous.zw, xTexelC${y + 1}.xy);
                    } else {
                     xC${y + 1} = vec4(0.0, 0.0, xTexelC${y + 1}.xy);
                    }
                    ` : f += `
                    xC${y + 1} = vec4(xTexelC${y}.zw, xTexelC${y + 1}.xy);
                    `) : v === 1 ? f += `
                    xC${y + 1} = xTexelC${y};
                    ` : f += `
                    xCOffset = xC + ${v};

                    if (xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${y + 1}Ready == 0) {
                      xTexelC${y + 1} = getX(batch, xR, xCOffset, d1);
                      if (xCOffset + 1 >= inDims[1]) {
                        xTexelC${y + 1}.zw = vec2(0.0);
                      }
                      xTexelC${y + 1}Ready = 1;
                    }

                    xC${y + 1} = xTexelC${y + 1};
                    `;
        }
      } else
        y < d && (a % 2 === 1 ? (f += `
                xCOffset = xC + 1 - strides[1];
                if(xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${y}Ready == 0) {
                  xTexelC${y} = getX(batch, xR, xCOffset, d1);
                  // Need to manually clear unused channels in case
                  // we're reading from recycled texture.
                  if (xCOffset + 1 >= inDims[1]) {
                    xTexelC${y}.zw = vec2(0.0);
                  }
                  xTexelC${y}Ready = 1;
                }

                if(xC + 1 >= 0 && xC + 1 < inDims[1] && xTexelC${y + 1}Ready == 0) {
                  xTexelC${y + 1} = getX(batch, xR, xC + 1, d1);
                  // Need to manually clear unused channels in case
                  // we're reading from recycled texture.
                  if (xC + 2 >= inDims[1]) {
                    xTexelC${y + 1}.zw = vec2(0.0);
                  }
                  xTexelC${y + 1}Ready = 1;
                }

                xC${y} = vec4(xTexelC${y}.zw, xTexelC${y + 1}.zw);
              `, y + 1 < d && (f += `
                  final = vec4(0.0);
                  xCOffset = xC + 1 + strides[1];
                  if(xCOffset >= 0 && xCOffset < inDims[1]) {
                    final = getX(batch, xR, xCOffset, d1);
                  }
                  xC${y + 1} = vec4(xTexelC${y + 1}.xy, final.xy);
                `)) : (f += `
                if(xC >= 0 && xC < inDims[1] && xTexelC${y}Ready == 0) {
                  xTexelC${y} = getX(batch, xR, xC, d1);
                  if (xC + 1 >= inDims[1]) {
                    xTexelC${y}.zw = vec2(0.0);
                  }
                  xTexelC${y}Ready = 1;
                }

                xCOffset = xC + strides[1];
                if(xCOffset >= 0 && xCOffset < inDims[1] && xTexelC${y + 1}Ready == 0) {
                  xTexelC${y + 1} = getX(batch, xR, xCOffset, d1);
                  if (xCOffset + 1 >= inDims[1]) {
                    xTexelC${y + 1}.zw = vec2(0.);
                  }
                  xTexelC${y + 1}Ready = 1;
                }

                xC${y} = vec4(
                  xTexelC${y}.xy, xTexelC${y + 1}.xy);
              `, y + 1 < d && (f += `
                  xC${y + 1} = vec4(xTexelC${y}.zw, xTexelC${y + 1}.zw);
                `)));
      y < d && (f += `
            wTexel = getW(r, ${y}, d1, q);
            dotProd += xC${y} * vec4(wTexel.xz, wTexel.xz);
          `, y + 1 < d && (f += `
              wTexel = getW(r, ${y + 1}, d1, q);
              dotProd += xC${y + 1} * vec4(wTexel.xz, wTexel.xz);
            `));
    }
    f += `
    }
  `, f += `
      }
    `;
    let m = "", C = "";
    r && (s ? m = `vec4 activation(vec4 a) {
          vec4 b = getPreluActivationWeightsAtOutCoords();
          ${r}
        }` : o ? m = `vec4 activation(vec4 a) {
          vec4 b = getLeakyreluAlphaAtOutCoords();
          ${r}
        }` : m = `vec4 activation(vec4 x) {
          ${r}
        }`, C = "result = activation(result);");
    const w = t ? "result += getBiasAtOutCoords();" : "";
    t && this.variableNames.push("bias"), s && this.variableNames.push("preluActivationWeights"), o && this.variableNames.push("leakyreluAlpha"), this.userCode = `
      ${m}

      void main() {
        ivec4 coords = getOutputCoords();
        int batch = coords.x;
        ivec2 xRCCorner = coords.yz * strides - pads;
        int d2 = coords.w;
        int d1 = d2 / ${i};
        int q = d2 - d1 * ${i};
        int xRCorner = xRCCorner.x;
        int xCCorner = xRCCorner.y;

        //intialize dotProd with a small epsilon seems to reduce GPU accuracy loss.
        vec4 dotProd = vec4(0.000000000000001);

        ${f}

        vec4 result = dotProd - vec4(0.000000000000001);
        ${w}
        ${C}
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Db(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, filter: o } = e, { strides: i, pad: a, dilations: c, dimRoundingMode: l } = r;
  let u = c;
  u == null && (u = [1, 1]), O(Sn(i, u), () => `Error in depthwiseConv2d: Either strides or dilations must be 1. Got strides ${i} and dilations '${u}'`);
  const d = et(
    s.shape,
    o.shape,
    i,
    u,
    a,
    l,
    !0
    /* depthwise */
  );
  let h;
  E().getBool("WEBGL_PACK_DEPTHWISECONV") && d.strideWidth <= 2 && d.outChannels / d.inChannels === 1 ? h = new ul(d) : h = new ll(d);
  const f = [
    [d.padInfo.top, d.padInfo.left],
    [d.strideHeight, d.strideWidth],
    [d.dilationHeight, d.dilationWidth],
    [d.inHeight, d.inWidth]
  ];
  return t.runWebGLProgram(h, [s, o], "float32", f);
}
const Ob = {
  kernelName: Pu,
  backendName: "webgl",
  kernelFunc: Db
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Pb {
  constructor(e) {
    this.variableNames = ["x", "dy"], this.outputShape = e.filterShape;
    const t = e.strideHeight, r = e.strideWidth, s = e.padInfo.top, o = e.padInfo.left, i = e.outChannels / e.inChannels;
    this.userCode = `
      void main() {
        ivec4 coords = getOutputCoords();
        int wR = coords.x;
        int wC = coords.y;
        int d1 = coords.z;
        int dm = coords.w;
        int d2 = d1 * ${i} + dm;

        float dotProd = 0.0;

        // TO DO: Vec4 over the batch size
        for (int b = 0; b < ${e.batchSize}; b++) {
          for (int yR = 0; yR < ${e.outHeight}; yR++) {
            int xR = wR + yR * ${t} - ${s};

            if (xR < 0 || xR >= ${e.inHeight}) {
              continue;
            }

            for (int yC = 0; yC < ${e.outWidth}; yC++) {
              int xC = wC + yC * ${r} - ${o};

              if (xC < 0 || xC >= ${e.inWidth}) {
                continue;
              }

              float dyValue = getDy(b, yR, yC, d2);
              float xValue = getX(b, xR, xC, d1);
              dotProd += (xValue * dyValue);
            }
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
class _b {
  constructor(e) {
    this.variableNames = ["dy", "W"], this.outputShape = e.inShape;
    const t = e.filterHeight, r = e.filterWidth, s = e.strideHeight, o = e.strideWidth, i = t - 1 - e.padInfo.top, a = r - 1 - e.padInfo.left, c = e.outChannels / e.inChannels;
    this.userCode = `
      const ivec2 pads = ivec2(${i}, ${a});

      void main() {
        ivec4 coords = getOutputCoords();
        int batch = coords[0];
        int d1 = coords[3];
        ivec2 dyCorner = coords.yz - pads;
        int dyRCorner = dyCorner.x;
        int dyCCorner = dyCorner.y;

        float dotProd = 0.0;

        for (int wR = 0; wR < ${t}; wR++) {
          float dyR = float(dyRCorner + wR) / ${s}.0;

          if (dyR < 0.0 || dyR >= ${e.outHeight}.0 || fract(dyR) > 0.0) {
            continue;
          }
          int idyR = int(dyR);

          int wRPerm = ${t} - 1 - wR;

          for (int wC = 0; wC < ${r}; wC++) {
            float dyC = float(dyCCorner + wC) / ${o}.0;

            if (dyC < 0.0 || dyC >= ${e.outWidth}.0 ||
                fract(dyC) > 0.0) {
              continue;
            }
            int idyC = int(dyC);

            int wCPerm = ${r} - 1 - wC;

            // TO DO: Vec4 over the channelMul
            for (int dm = 0; dm < ${c}; dm++) {
              int d2 = d1 * ${c} + dm;
              float xValue = getDy(batch, idyR, idyC, d2);
              float wValue = getW(wRPerm, wCPerm, d1, dm);
              dotProd += xValue * wValue;
            }
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Bb(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, dy: o } = e, { strides: i, dilations: a, pad: c, dimRoundingMode: l, filterShape: u } = r, d = et(
    s.shape,
    u,
    i,
    a,
    c,
    l,
    !0
    /* depthwise */
  ), h = new Pb(d);
  return t.runWebGLProgram(h, [s, o], "float32");
}
const Lb = {
  kernelName: _u,
  backendName: "webgl",
  kernelFunc: Bb
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Mb(n) {
  const { inputs: e, backend: t, attrs: r } = n, { dy: s, filter: o } = e, { strides: i, dilations: a, pad: c, dimRoundingMode: l, inputShape: u } = r, d = et(
    u,
    o.shape,
    i,
    a,
    c,
    l,
    !0
    /* depthwise */
  ), h = new _b(d);
  return t.runWebGLProgram(h, [s, o], "float32");
}
const Ub = {
  kernelName: Bu,
  backendName: "webgl",
  kernelFunc: Mb
};
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Vb {
  constructor(e) {
    this.variableNames = ["X"], this.outputShape = [e, e], this.userCode = `
      void main() {
          ivec2 coords = getOutputCoords();
          float val = coords[0] == coords[1] ? getX(coords[0]) : 0.0;
          setOutput(val);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Wb(n) {
  const { inputs: e, backend: t } = n, { x: r } = e, s = [...r.shape, ...r.shape], o = _(r.shape), i = D({ inputs: { x: r }, backend: t, attrs: { shape: [o] } }), a = new Vb(o), c = t.runWebGLProgram(a, [i], i.dtype), l = D({ inputs: { x: c }, backend: t, attrs: { shape: s } });
  return t.disposeIntermediateTensorInfo(i), t.disposeIntermediateTensorInfo(c), l;
}
const Gb = {
  kernelName: Lu,
  backendName: "webgl",
  kernelFunc: Wb
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class zb {
  constructor(e) {
    this.variableNames = ["x", "W"], this.outputShape = e.outShape;
    const { inHeight: t, inWidth: r, padInfo: s, strideHeight: o, strideWidth: i, filterHeight: a, filterWidth: c, dilationHeight: l, dilationWidth: u } = e, { top: d, left: h } = s;
    this.userCode = `
      const ivec2 strides = ivec2(${o}, ${i});
      const ivec2 pads = ivec2(${d}, ${h});
      const float neg_infinity = -3.4e38;

      void main() {
        ivec4 coords = getOutputCoords();
        int batch = coords.x;
        int d1 = coords.w;
        ivec2 outTopLeftCorner =
            coords.yz * strides - pads;
        int hBeg = outTopLeftCorner.x;
        int wBeg = outTopLeftCorner.y;

        float curVal = neg_infinity;
        for (int h = 0; h < ${a}; h++) {
          int hIn = hBeg + h * ${l};

          if (hIn >= 0 && hIn < ${t}) {
            for (int w = 0; w < ${c}; w++) {
              int wIn = wBeg + w * ${u};

              if (wIn >= 0 && wIn < ${r}) {
                float xVal = getX(batch, hIn, wIn, d1);
                float wVal = getW(h, w, d1);

                float val = xVal + wVal;
                if (val > curVal) {
                  curVal = val;
                }
              }
            }
          }
        }

        float result = curVal;
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Hb(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, filter: o } = e, { strides: i, pad: a, dilations: c } = r, l = Ra(s.shape, o.shape, i, a, "NHWC", c);
  let u;
  const d = new zb(l);
  u = t.runWebGLProgram(d, [s, o], "float32");
  const h = D({ inputs: { x: u }, backend: t, attrs: { shape: l.outShape } });
  return t.disposeIntermediateTensorInfo(u), h;
}
const Xb = {
  kernelName: Mu,
  backendName: "webgl",
  kernelFunc: Hb
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function jb(n) {
  const { inputs: e, backend: t, attrs: r } = n, { equation: s } = r, o = e, { allDims: i, summedDims: a, idDims: c } = cc(s, o.length);
  uc(i.length, c, o);
  const { path: l, steps: u } = dc(a, c), d = u.length;
  let h = null, f = i.length;
  const m = [];
  for (let C = 0; C < d; ++C) {
    for (const w of u[C]) {
      const { permutationIndices: x, expandDims: y } = lc(f, c[w]);
      let v;
      hc(x) ? v = o[w] : (v = Ie({ inputs: { x: o[w] }, backend: t, attrs: { perm: x } }), m.push(v));
      const I = v.shape.slice();
      for (let T = 0; T < y.length; ++T)
        I.splice(y[T], 0, 1);
      ge(v.shape, I) || (v = D({ inputs: { x: v }, backend: t, attrs: { shape: I } }), m.push(v)), h === null ? h = v : (h = ao({ inputs: { a: v, b: h }, backend: t }), m.push(h));
    }
    C < d - 1 && (l[C] >= 0 && (h = Gr({
      inputs: { x: h },
      backend: t,
      attrs: {
        axis: l[C] - (i.length - f),
        keepDims: !1
      }
    }), m.push(h)), f--);
  }
  for (const C of m)
    C !== h && t.disposeIntermediateTensorInfo(C);
  return h;
}
const qb = {
  kernelName: Uu,
  backendName: "webgl",
  kernelFunc: jb
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Kb = "return (x >= 0.0) ? x : (exp(x) - 1.0);", Yb = `
  vec4 result;

  result.r = (x.r >= 0.0) ? x.r : (exp(x.r) - 1.0);
  result.g = (x.g >= 0.0) ? x.g : (exp(x.g) - 1.0);
  result.b = (x.b >= 0.0) ? x.b : (exp(x.b) - 1.0);
  result.a = (x.a >= 0.0) ? x.a : (exp(x.a) - 1.0);

  return result;
`, Qb = H({ opSnippet: Kb, packedOpSnippet: Yb }), Zb = {
  kernelName: Pi,
  backendName: "webgl",
  kernelFunc: Qb
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Jb = "return (b >= 0.0) ? a : a * (b + 1.0);", ey = `
  vec4 bGTEZero = vec4(greaterThanEqual(b, vec4(0.)));
  return (bGTEZero * a) + ((vec4(1.0) - bGTEZero) * (a * (b + vec4(1.0))));
`, ty = (n) => {
  const { inputs: e, backend: t } = n, { dy: r, y: s } = e, o = E().getBool("WEBGL_PACK_BINARY_OPERATIONS") ? new Fn(ey, r.shape, s.shape) : new Xt(Jb, r.shape, s.shape);
  return t.runWebGLProgram(o, [r, s], r.dtype);
}, ny = {
  kernelName: Vu,
  backendName: "webgl",
  kernelFunc: ty
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ry = `
  return vec4(equal(a, b));
`, sy = "return float(a == b);", oy = we({
  opSnippet: sy,
  packedOpSnippet: ry,
  dtype: "bool",
  cpuKernelImpl: B0
}), iy = {
  kernelName: Gu,
  backendName: "webgl",
  kernelFunc: oy
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ay = `
  // Error function is calculated approximately with elementary function.
  // See "Handbook of Mathematical Functions with Formulas,
  // Graphs, and Mathematical Tables", Abramowitz and Stegun.
  float p = ${nc};
  float a1 = ${rc};
  float a2 = ${sc};
  float a3 = ${oc};
  float a4 = ${ic};
  float a5 = ${ac};

  float sign = sign(x);
  x = abs(x);
  float t = 1.0 / (1.0 + p * x);
  return sign * (1.0 - (((((a5*t + a4)*t) + a3)*t + a2)*t + a1)*t*exp(-x*x));
`, cy = H({ opSnippet: ay }), ly = {
  kernelName: Wu,
  backendName: "webgl",
  kernelFunc: cy
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const uy = Dn + `
  return exp(x);
`, dy = `
  vec4 result = exp(x);
  bvec4 isNaN = isnan(x);
  result.r = isNaN.r ? x.r : result.r;
  result.g = isNaN.g ? x.g : result.g;
  result.b = isNaN.b ? x.b : result.b;
  result.a = isNaN.a ? x.a : result.a;

  return result;
`, dl = H({
  opSnippet: uy,
  packedOpSnippet: dy,
  cpuKernelImpl: L0,
  dtype: "float32"
}), hy = {
  kernelName: zu,
  backendName: "webgl",
  kernelFunc: dl
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function ks(n) {
  const { inputs: e, attrs: t, backend: r } = n, { dim: s } = t, { input: o } = e, i = o.shape.length, a = o.shape.slice();
  let c = s;
  return s < 0 && (O(-(i + 1) <= s, () => `Axis must be in the interval [${-(i + 1)}, ${i}]`), c = i + s + 1), a.splice(c, 0, 1), D({ inputs: { x: o }, backend: r, attrs: { shape: a } });
}
const fy = {
  kernelName: Hu,
  backendName: "webgl",
  kernelFunc: ks
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const mi = "return exp(x) - 1.0;", py = H({ opSnippet: mi, packedOpSnippet: mi, cpuKernelImpl: M0 }), my = {
  kernelName: Xu,
  backendName: "webgl",
  kernelFunc: py
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class gi {
  constructor(e, t, r) {
    this.variableNames = ["real", "imag"];
    const s = t[1];
    this.outputShape = t;
    const o = r ? `2.0 * ${Math.PI}` : `-2.0 * ${Math.PI}`, i = r ? `${s}.0` : "1.0";
    let a;
    if (e === "real")
      a = "return real * expR - imag * expI;";
    else if (e === "imag")
      a = "return real * expI + imag * expR;";
    else
      throw new Error(`FFT component must be either "real" or "imag", got ${e}.`);
    this.userCode = `
      const float exponentMultiplier = ${o};

      float unaryOpComplex(float real, float expR, float imag, float expI) {
        ${a}
      }

      float mulMatDFT(int batch, int index) {
        float indexRatio = float(index) / float(${s});
        float exponentMultiplierTimesIndexRatio =
            exponentMultiplier * indexRatio;

        float result = 0.0;

        for (int i = 0; i < ${s}; i++) {
          // x = (-2|2 * PI / N) * index * i;
          float x = exponentMultiplierTimesIndexRatio * float(i);
          float expR = cos(x);
          float expI = sin(x);
          float real = getReal(batch, i);
          float imag = getImag(batch, i);

          result +=
              unaryOpComplex(real, expR, imag, expI) / ${i};
        }

        return result;
      }

      void main() {
        ivec2 coords = getOutputCoords();
        setOutput(mulMatDFT(coords[0], coords[1]));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function hl(n, e, t) {
  const r = t.texData.get(n.dataId), s = _(n.shape), o = n.shape[n.shape.length - 1], i = s / o, a = D({ inputs: { x: n }, backend: t, attrs: { shape: [i, o] } }), c = a.shape, l = new gi("real", c, e), u = new gi("imag", c, e), d = [
    {
      dataId: r.complexTensorInfos.real.dataId,
      dtype: r.complexTensorInfos.real.dtype,
      shape: c
    },
    {
      dataId: r.complexTensorInfos.imag.dataId,
      dtype: r.complexTensorInfos.imag.dtype,
      shape: c
    }
  ], h = t.runWebGLProgram(l, d, "float32"), f = t.runWebGLProgram(u, d, "float32"), m = Nt({ inputs: { real: h, imag: f }, backend: t });
  t.disposeIntermediateTensorInfo(h), t.disposeIntermediateTensorInfo(f);
  const C = D({ inputs: { x: m }, backend: t, attrs: { shape: n.shape } });
  return t.disposeIntermediateTensorInfo(a), t.disposeIntermediateTensorInfo(m), C;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function gy(n) {
  const { inputs: e, backend: t } = n, { input: r } = e;
  return hl(r, !1, t);
}
const xy = {
  kernelName: ju,
  backendName: "webgl",
  kernelFunc: gy
};
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class wy {
  constructor(e, t) {
    this.outputShape = [], this.customUniforms = [{ name: "value", type: "float" }], this.variableNames = ["x"], this.outputShape = e, this.userCode = `
      void main() {
        // Input can be obtained from uniform value.
        setOutput(value);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function sr(n) {
  const { backend: e, attrs: t } = n, { shape: r, value: s } = t;
  let { dtype: o } = t;
  if (o = o || Yn(s), o === "string") {
    const i = de(o, _(r));
    return i.fill(s), e.makeTensorInfo(r, o, i);
  } else {
    const i = new wy(r, s), a = [[s]];
    return e.runWebGLProgram(i, [], o, a);
  }
}
const Cy = {
  kernelName: _i,
  backendName: "webgl",
  kernelFunc: sr
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class by {
  constructor(e) {
    this.variableNames = ["Image"], this.outputShape = [];
    const t = e[2];
    this.outputShape = e, this.userCode = `
        void main() {
          ivec4 coords = getOutputCoords();
          int x = coords[2];

          int coordX = ${t} - x - 1;
          float outputValue;
          if(coordX >= 0 && coordX < ${t}) {
            outputValue = getImage(coords[0], coords[1], coordX, coords[3]);
          } else {
            outputValue = getImage(coords[0], coords[1], coords[2], coords[3]);
          }
          setOutput(outputValue);
        }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const yy = {
  kernelName: qu,
  backendName: "webgl",
  kernelFunc: ({ inputs: n, backend: e }) => {
    const { image: t } = n, r = e, s = new by(t.shape);
    return r.runWebGLProgram(s, [t], t.dtype);
  }
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const xi = "return floor(x);", $y = H({ opSnippet: xi, packedOpSnippet: xi, cpuKernelImpl: U0 }), vy = {
  kernelName: Ku,
  backendName: "webgl",
  kernelFunc: $y
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Iy = `
  float s = sign(a) * sign(b);
  int ia = round(a);
  int ib = round(b);
  if (ib != 0) {
    // Windows (D3D) wants guaranteed non-zero int division at compile-time.
    return float(idiv(ia, ib, s));
  } else {
    return NAN;
  }
`, Sy = `
  ivec4 ia = round(a);
  ivec4 ib = round(b);
  bvec4 cond = notEqual(ib, ivec4(0));
  ivec4 result = ivec4(0);
  vec4 s = sign(a) * sign(b);

  // Windows (D3D) wants guaranteed non-zero int division at compile-time.
  if (cond[0]) {
    result[0] = idiv(ia[0], ib[0], s[0]);
  }
  if (cond[1]) {
    result[1] = idiv(ia[1], ib[1], s[1]);
  }
  if (cond[2]) {
    result[2] = idiv(ia[2], ib[2], s[2]);
  }
  if (cond[3]) {
    result[3] = idiv(ia[3], ib[3], s[3]);
  }
  return vec4(result);
`, Ey = we({ opSnippet: Iy, packedOpSnippet: Sy, dtype: "int32" }), Ry = {
  kernelName: Bi,
  backendName: "webgl",
  kernelFunc: Ey
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Ty {
  constructor(e) {
    this.variableNames = ["A"];
    const t = Se(), [r, s] = e;
    this.outputShape = e, this.userCode = `
      void main() {
        ivec3 coords = getOutputCoords();
        int texR = coords[0];
        int texC = coords[1];
        int depth = coords[2];
        vec2 uv = (vec2(texC, texR) + halfCR) / vec2(${s}.0, ${r}.0);

        vec4 values = ${t.texture2D}(A, uv);
        float value;
        if (depth == 0) {
          value = values.r;
        } else if (depth == 1) {
          value = values.g;
        } else if (depth == 2) {
          value = values.b;
        } else if (depth == 3) {
          value = values.a;
        }

        setOutput(floor(value * 255.0 + 0.5));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Ny {
  constructor(e) {
    this.variableNames = ["A"], this.packedInputs = !1, this.packedOutput = !0;
    const t = Se(), [r, s] = e;
    this.outputShape = e, this.userCode = `
      void main() {
        ivec3 coords = getOutputCoords();
        int texR = coords[0];
        int texC = coords[1];
        int depth = coords[2];

        vec4 result = vec4(0.);

        for(int row=0; row<=1; row++) {
          for(int col=0; col<=1; col++) {
            texC = coords[1] + row;
            depth = coords[2] + col;

            vec2 uv = (vec2(texC, texR) + halfCR) /
                       vec2(${s}.0, ${r}.0);
            vec4 values = ${t.texture2D}(A, uv);
            float value;
            if (depth == 0) {
              value = values.r;
            } else if (depth == 1) {
              value = values.g;
            } else if (depth == 2) {
              value = values.b;
            } else if (depth == 3) {
              value = values.a;
            }

            result[row * 2 + col] = floor(value * 255.0 + 0.5);
          }
        }

        ${t.output} = result;
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ky = {
  kernelName: kh,
  backendName: "webgl",
  kernelFunc: Ay
};
let an, os = E().getBool("CANVAS2D_WILL_READ_FREQUENTLY_FOR_GPU");
function Ay(n) {
  const { inputs: e, backend: t, attrs: r } = n;
  let { pixels: s } = e;
  const { numChannels: o } = r, i = typeof HTMLVideoElement < "u" && s instanceof HTMLVideoElement, a = typeof HTMLImageElement < "u" && s instanceof HTMLImageElement, [c, l] = i ? [
    s.videoWidth,
    s.videoHeight
  ] : [s.width, s.height], u = [l, c], d = [l, c, o];
  if (a || i) {
    const C = E().getBool("CANVAS2D_WILL_READ_FREQUENTLY_FOR_GPU");
    (an == null || C !== os) && (os = C, an = document.createElement("canvas").getContext("2d", { willReadFrequently: os })), an.canvas.width = c, an.canvas.height = l, an.drawImage(s, 0, 0, c, l), s = an.canvas;
  }
  const h = t.makeTensorInfo(u, "int32");
  t.texData.get(h.dataId).usage = Pe.PIXELS, t.gpgpu.uploadPixelDataToTexture(t.getTexture(h.dataId), s);
  const f = E().getBool("WEBGL_PACK") ? new Ny(d) : new Ty(d), m = t.runWebGLProgram(f, [h], "int32");
  return t.disposeData(h.dataId), m;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Fy(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, filter: o, bias: i, preluActivationWeights: a } = e, { strides: c, pad: l, dataFormat: u, dilations: d, dimRoundingMode: h, activation: f, leakyreluAlpha: m } = r, C = En(u), w = et(s.shape, o.shape, c, d, l, h, !1, C);
  let x;
  const y = [], v = i != null, I = a != null, T = f === "leakyrelu", A = () => {
    const k = [s, o], U = (V, G) => {
      if (G === "NCHW" && V.shape.length === 1 && V.shape[0] !== 1) {
        const j = D({
          inputs: { x: V },
          backend: t,
          attrs: { shape: [V.shape[0], 1, 1] }
        });
        return y.push(j), j;
      }
      return V;
    };
    if (v && k.push(U(i, u)), I && k.push(U(a, u)), T) {
      const V = t.makeTensorInfo([], "float32", vn(m, "float32"));
      k.push(V), y.push(V);
    }
    return k;
  };
  if (w.filterHeight === 1 && w.filterWidth === 1 && w.dilationHeight === 1 && w.dilationWidth === 1 && w.strideHeight === 1 && w.strideWidth === 1 && (w.padInfo.type === "SAME" || w.padInfo.type === "VALID"))
    x = il({
      x: s,
      filter: o,
      convInfo: w,
      backend: t,
      bias: i,
      activation: f,
      preluActivationWeights: a,
      leakyreluAlpha: m
    });
  else if (w.strideWidth <= 2 && C === "channelsLast" && E().getBool("WEBGL_EXP_CONV")) {
    const k = f ? jn(f, !0) : null, U = new ol(w, v, k, I, T), V = [
      [w.padInfo.top, w.padInfo.left],
      [w.strideHeight, w.strideWidth],
      [w.dilationHeight, w.dilationWidth],
      [w.inHeight, w.inWidth]
    ], G = A();
    x = t.runWebGLProgram(U, G, "float32", V);
  } else if (E().getBool("WEBGL_CONV_IM2COL"))
    x = al({
      x: s,
      filter: o,
      convInfo: w,
      backend: t,
      bias: i,
      activation: f,
      preluActivationWeights: a,
      leakyreluAlpha: m
    });
  else {
    const k = f ? jn(f, !1) : null, U = new sl(w, v, k, I, T), V = A();
    x = t.runWebGLProgram(U, V, "float32");
  }
  const F = D({ inputs: { x }, backend: t, attrs: { shape: w.outShape } });
  return y.push(x), y.forEach((k) => t.disposeIntermediateTensorInfo(k)), F;
}
const Dy = {
  kernelName: Dh,
  backendName: "webgl",
  kernelFunc: Fy
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Oy(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, filter: o, bias: i, preluActivationWeights: a } = e, { strides: c, pad: l, dilations: u, dimRoundingMode: d, activation: h, leakyreluAlpha: f } = r, m = [];
  let C = u;
  C == null && (C = [1, 1]), O(Sn(c, C), () => `Error in depthwiseConv2d: Either strides or dilations must be 1. Got strides ${c} and dilations '${C}'`);
  const w = et(
    s.shape,
    o.shape,
    c,
    C,
    l,
    d,
    !0
    /* depthwise */
  ), x = E().getBool("WEBGL_PACK_DEPTHWISECONV") && w.strideWidth <= 2 && w.outChannels / w.inChannels === 1, y = h ? jn(h, x) : null, v = [s, o], I = i != null, T = a != null, A = h === "leakyrelu";
  if (I && v.push(i), T && v.push(a), A) {
    const V = t.makeTensorInfo([], "float32", vn(f, "float32"));
    v.push(V), m.push(V);
  }
  let F;
  x ? F = new ul(w, I, y, T, A) : F = new ll(w, I, y, T, A);
  const k = [
    [w.padInfo.top, w.padInfo.left],
    [w.strideHeight, w.strideWidth],
    [w.dilationHeight, w.dilationWidth],
    [w.inHeight, w.inWidth]
  ], U = t.runWebGLProgram(F, v, "float32", k);
  return m.forEach((V) => t.disposeIntermediateTensorInfo(V)), U;
}
const Py = {
  kernelName: Oh,
  backendName: "webgl",
  kernelFunc: Oy
};
class _y {
  constructor(e, t, r, s) {
    this.sliceDim = e, this.strides = t, this.paramsShape = s, this.variableNames = ["x", "indices"], this.outputShape = r;
    const o = K(r.length);
    let i = `
    int index;`;
    for (let a = 0; a < this.sliceDim; a++)
      i += `
          index = round(getIndices(coords[0], ${a}));
          out_of_bounds = out_of_bounds || index < 0;
          out_of_bounds = out_of_bounds || index >= ${this.paramsShape[a]};
          flattenIndex += index * ${this.strides[a]};`;
    this.userCode = `
         void main() {
          ${o} coords = getOutputCoords();
          int flattenIndex = 0;
          bool out_of_bounds = false;

          ${i}

          setOutput(out_of_bounds ? 0.0 : getX(flattenIndex, coords[1]));
        }
      `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function By(n) {
  const { inputs: e, backend: t } = n, { params: r, indices: s } = e, o = s.shape, i = o[o.length - 1], a = _(r.shape), [c, l, u, d] = Da(r, s), h = D({ inputs: { x: s }, backend: t, attrs: { shape: [l, i] } }), f = D({
    inputs: { x: r },
    backend: t,
    attrs: { shape: [_(r.shape) / u, u] }
  });
  if (t.shouldExecuteOnCPU([r, s]) || r.dtype === "string") {
    const x = t.readSync(s.dataId), y = t.bufferSync(r), v = V0(x, y, r.dtype, l, i, u, d, r.shape, a);
    return t.makeTensorInfo(c, r.dtype, v.values);
  }
  const m = new _y(i, d, [l, u], r.shape), C = t.runWebGLProgram(m, [f, h], f.dtype), w = D({ inputs: { x: C }, backend: t, attrs: { shape: c } });
  return t.disposeIntermediateTensorInfo(h), t.disposeIntermediateTensorInfo(f), t.disposeIntermediateTensorInfo(C), w;
}
const Ly = {
  kernelName: Zu,
  backendName: "webgl",
  kernelFunc: By
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class My {
  constructor(e, t) {
    this.variableNames = ["A", "indices"], this.outputShape = t, this.rank = t.length;
    const r = K(this.rank), s = Uy(e);
    this.userCode = `
      void main() {
        ${r} resRC = getOutputCoords();
        int index = int(getIndices(resRC.x, resRC.z));
        float inBounds = (index >= 0) && (index < ${e[2]}) ? 1.0 : 0.0;
        setOutput(inBounds * getA(${s}));
      }
    `;
  }
}
function Uy(n, e) {
  const t = ["resRC.x", "resRC.y", "resRC.z", "resRC.w"], r = [];
  for (let s = 0; s < n.length; s++)
    s === 2 ? r.push("index") : r.push(`${t[s]}`);
  return r.join();
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function fl(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, indices: o } = e, { axis: i, batchDims: a } = r, c = Re(i, s.shape)[0];
  if (E().get("DEBUG")) {
    const y = t.readSync(o.dataId), v = s.shape[c];
    for (let I = 0; I < y.length; ++I) {
      const T = y[I];
      O(T <= v - 1 && T >= 0, () => `GatherV2: the index value ${T} is not in [0, ${v - 1}]`);
    }
  }
  const l = Rc(s, o, c, a), u = _(o.shape), d = [], h = D({
    inputs: { x: s },
    backend: t,
    attrs: {
      shape: [
        l.batchSize,
        l.outerSize,
        l.dimSize,
        l.sliceSize
      ]
    }
  }), f = D({
    inputs: { x: o },
    backend: t,
    attrs: { shape: [l.batchSize, u / l.batchSize] }
  });
  d.push(h), d.push(f);
  const m = [
    l.batchSize,
    l.outerSize,
    u / l.batchSize,
    l.sliceSize
  ];
  if (t.shouldExecuteOnCPU([s, o]) || s.dtype === "string") {
    const y = t.bufferSync(f), v = t.bufferSync(h), I = W0(v, y, m);
    return d.forEach((T) => t.disposeIntermediateTensorInfo(T)), t.makeTensorInfo(l.outputShape, I.dtype, I.values);
  }
  const C = new My(h.shape, m), w = t.runWebGLProgram(C, [h, f], h.dtype);
  d.push(w);
  const x = D({ inputs: { x: w }, backend: t, attrs: { shape: l.outputShape } });
  return d.forEach((y) => t.disposeIntermediateTensorInfo(y)), x;
}
const Vy = {
  kernelName: Qu,
  backendName: "webgl",
  kernelFunc: fl
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Wy = "return float(a > b);", Gy = `
  return vec4(greaterThan(a, b));
`, zy = we({
  opSnippet: Wy,
  packedOpSnippet: Gy,
  cpuKernelImpl: G0,
  dtype: "bool"
}), Hy = {
  kernelName: Ju,
  backendName: "webgl",
  kernelFunc: zy
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Xy = "return float(a >= b);", jy = `
  return vec4(greaterThanEqual(a, b));
`, qy = we({
  opSnippet: Xy,
  packedOpSnippet: jy,
  dtype: "bool",
  cpuKernelImpl: z0
}), Ky = {
  kernelName: ed,
  backendName: "webgl",
  kernelFunc: qy
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Yy(n) {
  const { inputs: e, backend: t } = n, { input: r } = e;
  return hl(r, !0, t);
}
const Qy = {
  kernelName: td,
  backendName: "webgl",
  kernelFunc: Yy
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Zy = "return float(!isnan(x) && !isinf(x));", Jy = H({ opSnippet: Zy, dtype: "bool" }), e$ = {
  kernelName: rd,
  backendName: "webgl",
  kernelFunc: Jy
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const t$ = "return float(isinf(x));", n$ = H({ opSnippet: t$, dtype: "bool" }), r$ = {
  kernelName: sd,
  backendName: "webgl",
  kernelFunc: n$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const s$ = "return float(isnan(x));", o$ = H({ opSnippet: s$, dtype: "bool" }), i$ = {
  kernelName: od,
  backendName: "webgl",
  kernelFunc: o$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const a$ = "return float(a < b);", c$ = `
  return vec4(lessThan(a, b));
`, l$ = we({
  opSnippet: a$,
  packedOpSnippet: c$,
  cpuKernelImpl: H0,
  dtype: "bool"
}), u$ = {
  kernelName: id,
  backendName: "webgl",
  kernelFunc: l$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const d$ = "return float(a <= b);", h$ = `
  return vec4(lessThanEqual(a, b));
`, f$ = we({
  opSnippet: d$,
  packedOpSnippet: h$,
  cpuKernelImpl: X0,
  dtype: "bool"
}), p$ = {
  kernelName: ad,
  backendName: "webgl",
  kernelFunc: f$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function m$(n) {
  const { backend: e, attrs: t } = n, { start: r, stop: s, num: o } = t, i = j0(r, s, o);
  return e.makeTensorInfo([i.length], "float32", i);
}
const g$ = {
  kernelName: cd,
  backendName: "webgl",
  kernelFunc: m$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const x$ = Dn + `
  return x < 0.0 ? 0./0. : log(x);
`, w$ = `
  vec4 result = log(x);
  bvec4 isNaN = isnan(x);
  result.r = isNaN.r ? x.r : (x.r < 0.0 ? 0./0. : result.r);
  result.g = isNaN.g ? x.g : (x.g < 0.0 ? 0./0. : result.g);
  result.b = isNaN.b ? x.b : (x.b < 0.0 ? 0./0. : result.b);
  result.a = isNaN.a ? x.a : (x.a < 0.0 ? 0./0. : result.a);
  return result;
`, C$ = H({ opSnippet: x$, packedOpSnippet: w$, cpuKernelImpl: q0 }), b$ = {
  kernelName: ld,
  backendName: "webgl",
  kernelFunc: C$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const y$ = Dn + `
  return log(1.0 + x);
`, $$ = H({ opSnippet: y$ }), v$ = {
  kernelName: ud,
  backendName: "webgl",
  kernelFunc: $$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const I$ = "return float(a >= 1.0 && b >= 1.0);", S$ = `
  return vec4(
    vec4(greaterThanEqual(a, vec4(1.0))) *
    vec4(greaterThanEqual(b, vec4(1.0))));
`, E$ = we({
  opSnippet: I$,
  packedOpSnippet: S$,
  dtype: "bool"
}), R$ = {
  kernelName: dd,
  backendName: "webgl",
  kernelFunc: E$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const T$ = "return float(!(x >= 1.0));", N$ = H({ opSnippet: T$ }), k$ = {
  kernelName: hd,
  backendName: "webgl",
  kernelFunc: N$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const A$ = "return float(a >= 1.0 || b >= 1.0);", F$ = `
  return min(
    vec4(greaterThanEqual(a, vec4(1.0))) +
    vec4(greaterThanEqual(b, vec4(1.0))),
    vec4(1.0));
`, D$ = we({ opSnippet: A$, packedOpSnippet: F$, dtype: "bool" }), O$ = {
  kernelName: fd,
  backendName: "webgl",
  kernelFunc: D$
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class P$ {
  constructor(e, t, r, s, o) {
    this.variableNames = ["x"], this.outputShape = [];
    const i = t, a = e[3] - 1;
    this.outputShape = e;
    let c;
    const l = `float(${r}) + float(${s}) * sum`;
    o === 0.5 ? c = `inversesqrt(${l})` : o === 1 ? c = `1.0/(${l})` : c = `exp(log(${l}) * float(-${o}));`, this.userCode = `
      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int r = coords[1];
        int c = coords[2];
        int d = coords[3];
        float x = getX(b, r, c, d);
        float sum = 0.0;
        for (int j = -${i}; j <= ${i}; j++) {
          int idx = d + j;
          if (idx >= 0 && idx <=  ${a}) {
            float z = getX(b, r, c, idx);
            sum += z * z;
          }
        }
        float val = x * ${c};
        setOutput(val);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class _$ {
  constructor(e, t, r, s, o) {
    this.variableNames = ["x"], this.outputShape = [], this.packedInputs = !0, this.packedOutput = !0;
    const i = t, a = e[3] - 1;
    this.outputShape = e;
    let c;
    const l = `float(${r}) + float(${s}) * sum`;
    o === 0.5 ? c = `inversesqrt(${l})` : o === 1 ? c = `1.0/(${l})` : c = `exp(log(${l}) * float(-${o}));`, this.userCode = `
      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords.x;
        int r = coords.y;
        int c = coords.z;
        int d = coords.w;

        bool hasNextCol = d < ${this.outputShape[3]};
        bool hasNextRow = c < ${this.outputShape[2]};

        vec4 sum = vec4(0.);
        vec4 xFragAtOutputCoords = getX(b, r, c, d);

        vec4 xAtOutputCoords = vec4(
          getChannel(xFragAtOutputCoords, vec2(c, d)),
          hasNextCol ?
            getChannel(xFragAtOutputCoords, vec2(c, d + 1)) : 0.0,
          hasNextRow ?
            getChannel(xFragAtOutputCoords , vec2(c + 1, d)) : 0.0,
          (hasNextRow && hasNextCol) ?
            getChannel(xFragAtOutputCoords, vec2(c + 1, d + 1)) : 0.0
        );

        int firstChannel = d - ${i};
        vec2 cache = vec2(0.);
        if(firstChannel >= 0){
          vec4 firstChannelFrag = getX(b, r, c, firstChannel);
          cache.x = getChannel(firstChannelFrag, vec2(c, firstChannel));
            if(hasNextRow){
              cache.y = getChannel(firstChannelFrag, vec2(c + 1, firstChannel));
            }
        }

        ivec2 depth = ivec2(d, d + 1);
        for (int j = - ${i}; j <= ${i}; j++) {
          ivec2 idx = depth + j;
          bvec2 aboveLowerBound = greaterThanEqual(idx, ivec2(0));
          bvec2 belowUpperBound = lessThanEqual(idx, ivec2(${a}));

          bool depthInRange = aboveLowerBound.x && belowUpperBound.x;
          bool depthPlusOneInRange = aboveLowerBound.y && belowUpperBound.y;

          if(depthInRange || depthPlusOneInRange){
            vec4 z = vec4(0.);
            vec4 xFragAtCurrentDepth;
            z.xz = cache.xy;
            if(depthPlusOneInRange && hasNextCol){
              xFragAtCurrentDepth = idx.y != d ?
                getX(b, r, c, idx.y) : xFragAtOutputCoords;
              z.y = getChannel(xFragAtCurrentDepth, vec2(c, idx.y));
              if(hasNextRow){
                z.w = getChannel(xFragAtCurrentDepth, vec2(c + 1, idx.y));
              }
            }
            cache.xy = z.yw;
            sum += z * z;
          }
        }
        vec4 result = xAtOutputCoords * ${c};
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const B$ = (n) => {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { depthRadius: o, bias: i, alpha: a, beta: c } = r, l = E().getBool("WEBGL_PACK_NORMALIZATION") ? new _$(s.shape, o, i, a, c) : new P$(s.shape, o, i, a, c);
  return t.runWebGLProgram(l, [s], s.dtype);
}, L$ = {
  kernelName: pd,
  backendName: "webgl",
  kernelFunc: B$
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class M$ {
  constructor(e, t, r, s, o) {
    this.variableNames = ["inputImage", "outputImage", "dy"], this.outputShape = [], this.outputShape = e, this.depth = e[3], this.depthRadius = t, this.bias = r, this.alpha = s, this.beta = o, this.userCode = `
      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int r = coords[1];
        int c = coords[2];

        float result = 0.0;
        for (int d = 0; d < ${this.depth}; ++d) {
          int depthBegin = int(max(0.0, float(d - ${t})));
          int depthEnd = int(min(float(${this.depth}),
              float(d + ${t} + 1)));

          const int MIN_DEPTH_BEGIN = 0;
          const int MAX_DEPTH_END = ${this.depth};

          float norm = 0.0;
          for (int k = MIN_DEPTH_BEGIN; k < MAX_DEPTH_END; ++k) {
            if (k < depthBegin){
              continue;
            }
            else if (k >= depthBegin && k < depthEnd) {
              norm += getInputImage(b, r, c, k) * getInputImage(b, r, c, k);
            }
            else {
              break;
            }
          }

          norm = float(${s}) * norm + float(${r});

          for(int k = MIN_DEPTH_BEGIN; k < MAX_DEPTH_END; ++k){
            if (k < depthBegin){
              continue;
            }
            else if (k >= depthBegin && k < depthEnd){
              float dyi = -2.0 * float(${s})
                * float(${o})
                * getInputImage(b, r, c, k) * getOutputImage(b, r, c, d)
                / norm;
              if (k == d) {
                dyi += pow(norm, -1.0 * ${o});
              }
              if (k == coords[3]) {
                dyi *= getDy(b, r, c, d);
                result += dyi;
              }
            }
            else {
              break;
            }
          }
      }
      setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const U$ = (n) => {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, y: o, dy: i } = e, { depthRadius: a, bias: c, alpha: l, beta: u } = r, d = new M$(s.shape, a, c, l, u);
  return t.runWebGLProgram(d, [s, o, i], s.dtype);
}, V$ = {
  kernelName: md,
  backendName: "webgl",
  kernelFunc: U$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function W$(n, e, t, r) {
  const s = _(e), i = _(n.shape) / s, a = D({ inputs: { x: n }, attrs: { shape: [i, s] }, backend: r }), c = tn(a, n.dtype, "max", r), l = D({ inputs: { x: c }, attrs: { shape: t }, backend: r });
  return r.disposeIntermediateTensorInfo(a), r.disposeIntermediateTensorInfo(c), l;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function pl(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { reductionIndices: o, keepDims: i } = r, a = s.shape.length, c = Re(o, s.shape);
  let l = c;
  const u = He(l, a), d = u != null, h = t.shouldExecuteOnCPU([s]);
  let f = s;
  if (d) {
    if (h) {
      const v = t.texData.get(f.dataId).values, I = new Array(a);
      for (let F = 0; F < I.length; F++)
        I[F] = s.shape[u[F]];
      const T = oo(v, s.shape, s.dtype, u, I);
      f = t.makeTensorInfo(I, s.dtype);
      const A = t.texData.get(f.dataId);
      A.values = T;
    } else
      f = Wr(s, u, t);
    l = Xe(l.length, a);
  }
  tt("max", l, a);
  const [m, C] = ht(f.shape, l);
  let w = m;
  i && (w = gt(m, c));
  let x;
  if (h) {
    const v = t.texData.get(f.dataId).values, I = K0(v, _(C), w, s.dtype);
    x = t.makeTensorInfo(w, s.dtype);
    const T = t.texData.get(x.dataId);
    T.values = I;
  } else
    x = W$(f, C, w, t);
  return d && t.disposeIntermediateTensorInfo(f), x;
}
const G$ = {
  kernelName: gd,
  backendName: "webgl",
  kernelFunc: pl
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const z$ = io + `
  return max(a, b);
`, H$ = `
  vec4 result = vec4(max(a, b));
  bvec4 isNaNA = isnan(a);
  bvec4 isNaNB = isnan(b);
  bvec4 isNaN = bvec4(isNaNA.x || isNaNB.x, isNaNA.y || isNaNB.y, isNaNA.z || isNaNB.z, isNaNA.w || isNaNB.w);
  ` + en + `
  return result;
`, X$ = we({
  opSnippet: z$,
  packedOpSnippet: H$,
  cpuKernelImpl: Y0
}), j$ = {
  kernelName: Mi,
  backendName: "webgl",
  kernelFunc: X$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function q$(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e;
  tr(s, "maxPool");
  const { filterSize: o, strides: i, pad: a, dimRoundingMode: c } = r, l = 1;
  O(Sn(i, l), () => `Error in maxPool: Either strides or dilations must be 1. Got strides ${i} and dilations '${l}'`);
  const u = In(s.shape, o, i, l, a, c);
  if (u.filterWidth === 1 && u.filterHeight === 1 && ge(u.inShape, u.outShape))
    return De({ inputs: { x: s }, backend: t });
  const d = new qn(u, "max", !1);
  return t.runWebGLProgram(d, [s], s.dtype);
}
const K$ = {
  kernelName: xd,
  backendName: "webgl",
  kernelFunc: q$
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Y$(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { filterSize: o, strides: i, pad: a, dataFormat: c, dimRoundingMode: l } = r, u = [1, 1, 1], d = Zn(s.shape, o, i, u, a, l, c), h = new co(d, "max", !1);
  return t.runWebGLProgram(h, [s], s.dtype);
}
const Q$ = {
  kernelName: Cd,
  backendName: "webgl",
  kernelFunc: Y$
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Z$ {
  constructor(e) {
    this.variableNames = ["dy", "maxPos"], this.outputShape = e.inShape;
    const t = e.strideHeight, r = e.strideWidth, s = e.dilationHeight, o = e.effectiveFilterHeight, i = e.effectiveFilterWidth, a = o - 1 - e.padInfo.top, c = i - 1 - e.padInfo.left, l = o * i - 1;
    this.userCode = `
      const ivec2 pads = ivec2(${a}, ${c});

      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int d = coords[3];

        ivec2 dyRCCorner = coords.yz - pads;
        int dyRCorner = dyRCCorner.x;
        int dyCCorner = dyRCCorner.y;

        // Convolve dy(?, ?, d) with pos mask(:, :, d) to get dx(xR, xC, d).
        // ? = to be determined. : = across all values in that axis.
        float dotProd = 0.0;
        for (int wR = 0; wR < ${o};
          wR += ${s}) {
          float dyR = float(dyRCorner + wR) / ${t}.0;

          if (dyR < 0.0 || dyR >= ${e.outHeight}.0 || fract(dyR) > 0.0) {
            continue;
          }
          int idyR = int(dyR);

          for (int wC = 0; wC < ${i}; wC++) {
            float dyC = float(dyCCorner + wC) / ${r}.0;

            if (dyC < 0.0 || dyC >= ${e.outWidth}.0 ||
                fract(dyC) > 0.0) {
              continue;
            }
            int idyC = int(dyC);

            float dyValue = getDy(b, idyR, idyC, d);
            int maxPosValue = ${l} - int(getMaxPos(b, idyR, idyC, d));

            // Get the current value, check it against the value from the
            // position matrix.
            int curPosValue = wR * ${i} + wC;
            float mask = float(maxPosValue == curPosValue ? 1.0 : 0.0);

            dotProd += dyValue * mask;
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
class J$ {
  constructor(e) {
    this.variableNames = ["dy", "maxPos"], this.outputShape = e.inShape;
    const t = e.strideDepth, r = e.strideHeight, s = e.strideWidth, o = e.dilationDepth, i = e.dilationHeight, a = e.dilationWidth, c = e.effectiveFilterDepth, l = e.effectiveFilterHeight, u = e.effectiveFilterWidth, d = c - 1 - e.padInfo.front, h = l - 1 - e.padInfo.top, f = u - 1 - e.padInfo.left, m = c * l * u - 1;
    this.userCode = `
      const ivec3 pads = ivec3(${d}, ${h}, ${f});

      void main() {
        ivec5 coords = getOutputCoords();
        int batch = coords.x;
        int ch = coords.u;

        ivec3 dyCorner = ivec3(coords.y, coords.z, coords.w) - pads;
        int dyDCorner = dyCorner.x;
        int dyRCorner = dyCorner.y;
        int dyCCorner = dyCorner.z;

        // Convolve dy(?, ?, ?, ch) with pos mask(:, :, :, d) to get
        // dx(xD, xR, xC, ch).
        // ? = to be determined. : = across all values in that axis.
        float dotProd = 0.0;

        for (int wD = 0; wD < ${c};
           wD += ${o}) {
          float dyD = float(dyDCorner + wD) / ${t}.0;

          if (dyD < 0.0 || dyD >= ${e.outDepth}.0 || fract(dyD) > 0.0) {
            continue;
          }
          int idyD = int(dyD);

          for (int wR = 0; wR < ${l};
              wR += ${i}) {
            float dyR = float(dyRCorner + wR) / ${r}.0;

            if (dyR < 0.0 || dyR >= ${e.outHeight}.0 ||
                fract(dyR) > 0.0) {
              continue;
            }
            int idyR = int(dyR);

            for (int wC = 0; wC < ${u};
                wC += ${a}) {
              float dyC = float(dyCCorner + wC) / ${s}.0;

              if (dyC < 0.0 || dyC >= ${e.outWidth}.0 ||
                  fract(dyC) > 0.0) {
                continue;
              }
              int idyC = int(dyC);

              float dyValue = getDy(batch, idyD, idyR, idyC, ch);
              int maxPosValue = ${m} -
                  int(getMaxPos(batch, idyD, idyR, idyC, ch));

              // Get the current value, check it against the value from the
              // position matrix.
              int curPosValue =
                  wD * ${l} * ${u} +
                  wR * ${u} + wC;
              float mask = float(maxPosValue == curPosValue ? 1.0 : 0.0);

              dotProd += dyValue * mask;
            }
          }
        }
        setOutput(dotProd);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function ev(n) {
  const { inputs: e, backend: t, attrs: r } = n, { dy: s, input: o } = e, i = o, { filterSize: a, strides: c, pad: l, dimRoundingMode: u } = r, d = [1, 1, 1], h = Zn(i.shape, a, c, d, l, u), f = new co(
    h,
    "max",
    !0
    /* get positions */
  ), m = t.runWebGLProgram(f, [i], i.dtype), C = new J$(h), w = t.runWebGLProgram(C, [s, m], i.dtype);
  return t.disposeIntermediateTensorInfo(m), w;
}
const tv = {
  kernelName: bd,
  backendName: "webgl",
  kernelFunc: ev
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function nv(n) {
  const { inputs: e, backend: t, attrs: r } = n, { dy: s, input: o, output: i } = e, a = o;
  tr([o, i], "maxPoolGrad");
  const { filterSize: c, strides: l, pad: u, dimRoundingMode: d } = r, h = In(a.shape, c, l, 1, u, d), f = !0, m = new qn(h, "max", f), C = t.runWebGLProgram(m, [a], a.dtype), w = new Z$(h), x = t.runWebGLProgram(w, [s, C], a.dtype);
  return t.disposeIntermediateTensorInfo(C), x;
}
const rv = {
  kernelName: wd,
  backendName: "webgl",
  kernelFunc: nv
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function sv(n, e, t, r) {
  let s = new qn(t, "max", !1);
  const o = r.runWebGLProgram(s, [n], "float32");
  s = new qn(t, "max", !0, !0, e);
  const i = r.runWebGLProgram(s, [n], "float32");
  return [o, i];
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const ov = {
  kernelName: yd,
  backendName: "webgl",
  kernelFunc: ({ inputs: n, attrs: e, backend: t }) => {
    const { x: r } = n, { filterSize: s, strides: o, pad: i, includeBatchInIndex: a } = e, c = t;
    O(r.shape.length === 4, () => `Error in maxPool: input must be rank 4 but got rank ${r.shape.length}.`);
    const l = [1, 1];
    O(Sn(o, l), () => `Error in maxPool: Either strides or dilations must be 1. Got strides ${o} and dilations '${l}'`);
    const u = In(r.shape, s, o, l, i), [d, h] = sv(r, a, u, c);
    return [d, h];
  }
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function iv(n, e, t, r) {
  const s = _(e), i = _(n.shape) / s, a = D({ inputs: { x: n }, attrs: { shape: [i, s] }, backend: r }), c = tn(a, "float32", "mean", r), l = D({ inputs: { x: c }, attrs: { shape: t }, backend: r });
  return r.disposeIntermediateTensorInfo(a), r.disposeIntermediateTensorInfo(c), l;
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const av = {
  kernelName: $d,
  backendName: "webgl",
  kernelFunc: ({ inputs: n, attrs: e, backend: t }) => {
    const { x: r } = n, { keepDims: s, axis: o } = e, i = t, a = r.shape.length, c = Re(o, r.shape);
    let l = c;
    const u = He(l, a), d = u != null, h = i.shouldExecuteOnCPU([r]), f = [];
    let m = r;
    if (d) {
      if (h) {
        const I = i.texData.get(m.dataId).values, T = new Array(a);
        for (let k = 0; k < T.length; k++)
          T[k] = r.shape[u[k]];
        const A = oo(I, r.shape, r.dtype, u, T);
        m = i.makeTensorInfo(T, r.dtype);
        const F = i.texData.get(m.dataId);
        F.values = A;
      } else
        m = Wr(r, u, i);
      f.push(m), l = Xe(l.length, a);
    }
    tt("sum", l, a);
    const [C, w] = ht(m.shape, l);
    let x = C;
    s && (x = gt(C, c));
    const y = iv(m, w, x, i);
    for (const v of f)
      i.disposeIntermediateTensorInfo(v);
    return y;
  }
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function cv(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { axis: o, keepDims: i } = r, a = s.shape.length, c = Re(o, s.shape);
  let l = c;
  const u = He(l, a);
  let d = s;
  u != null && (d = Ie({ inputs: { x: s }, backend: t, attrs: { perm: u } }), l = Xe(l.length, s.shape.length)), tt("min", l, a);
  const [h, f] = ht(d.shape, l), m = _(f), C = D({ inputs: { x: d }, backend: t, attrs: { shape: [-1, m] } }), w = tn(C, C.dtype, "min", t);
  let x;
  if (i) {
    const y = gt(h, c);
    x = D({ inputs: { x: w }, backend: t, attrs: { shape: y } });
  } else
    x = D({ inputs: { x: w }, backend: t, attrs: { shape: h } });
  return t.disposeIntermediateTensorInfo(C), t.disposeIntermediateTensorInfo(w), u != null && t.disposeIntermediateTensorInfo(d), x;
}
const lv = {
  kernelName: vd,
  backendName: "webgl",
  kernelFunc: cv
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const uv = io + `
  return min(a, b);
`, dv = `
  vec4 result = vec4(min(a, b));
  bvec4 isNaNA = isnan(a);
  bvec4 isNaNB = isnan(b);
  bvec4 isNaN = bvec4(isNaNA.x || isNaNB.x, isNaNA.y || isNaNB.y, isNaNA.z || isNaNB.z, isNaNA.w || isNaNB.w);
  ` + en + `
  return result;
`, hv = we({
  opSnippet: uv,
  packedOpSnippet: dv,
  cpuKernelImpl: Q0
}), fv = {
  kernelName: Id,
  backendName: "webgl",
  kernelFunc: hv
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class pv {
  constructor(e, t, r) {
    this.variableNames = ["x"], this.outputShape = t.map(
      (u, d) => u[0] + e[d] + u[1]
      /* afterPad */
    );
    const s = e.length, o = K(s), i = t.map((u) => u[0]).join(","), a = t.map((u, d) => u[0] + e[d]).join(","), c = ["coords[0]", "coords[1]", "coords[2]", "coords[3]"].slice(0, s), l = r === "reflect" ? 0 : 1;
    if (s === 1) {
      this.userCode = `
        int start = ${i};
        int end = ${a};

        void main() {
          int outC = getOutputCoords();
          if (outC < start) {
            outC = start * 2 - outC - ${l};
          } else if(outC >= end) {
            outC = (end - 1) * 2 - outC + ${l};
          }
          setOutput(getX(outC - start));
        }
      `;
      return;
    }
    this.userCode = `
      ${o} start = ${o}(${i});
      ${o} end = ${o}(${a});

      void main() {
        ${o} outC = getOutputCoords();
        for (int i = 0; i < ${s}; i++) {
          if (outC[i] < start[i]) {
            outC[i] = start[i] * 2 - outC[i] - ${l};
          } else if(outC[i] >= end[i]) {
            outC[i] = (end[i] - 1) * 2 - outC[i] + ${l};
          }
        }
        ${o} coords = outC - start;
        setOutput(getX(${c}));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class mv {
  constructor(e, t, r) {
    this.variableNames = ["x"], this.packedInputs = !0, this.packedOutput = !0, this.outputShape = t.map(
      (m, C) => m[0] + e[C] + m[1]
      /* afterPad */
    );
    const s = e.length, o = K(s), i = t.map((m) => m[0]).join(","), a = t.map((m, C) => m[0] + e[C]).join(","), c = $e("rc", s), l = $e("source", s), u = `${c[s - 1]} < ${this.outputShape[s - 1]}`, d = s === 1 ? "source" : `vec2(${l.slice(-2).join()})`, h = r === "reflect" ? 0 : 1;
    let f = "";
    if (s === 1) {
      const m = `
        ${o} source = rc;
        if (source < start) {
          source = start * 2 - source - ${h};
        } else if (source >= end) {
          source = (end - 1) * 2 - source + ${h};
        }
        source -= start;
      `;
      f = `
        ${o} rc = outputLoc;
        ${m}
        result[0] = getChannel(getX(${l.join()}), ${d});
        ${c[s - 1]} += 1;
        if(${u}) {
          ${m}
          result[1] = getChannel(getX(${l.join()}), ${d});
        }
      `;
    } else {
      const m = `
        ${o} source = rc;
        ${o} lt = ${o}(lessThan(source, start));
        ${o} gte = ${o}(greaterThanEqual(source, end));
        ${o} orig = 1 - (lt + gte);
        source = orig * source +
                lt * (start * 2 - source - ${h}) +
                gte * ((end - 1) * 2 - source + ${h});
        source -= start;
      `;
      f = `
        ${o} rc = outputLoc;
        ${m}
        result[0] = getChannel(getX(${l.join()}), ${d});
        ${c[s - 1]} += 1;
        if(${u}) {
          ${m}
          result[1] = getChannel(getX(${l.join()}), ${d});
        }
        rc = outputLoc;
        ${c[s - 2]} += 1;
        if(${c[s - 2]} < ${this.outputShape[s - 2]}) {
          ${m}
          result[2] = getChannel(getX(${l.join()}), ${d});
          ${c[s - 1]} += 1;
          if(${u}) {
            ${m}
            result[3] = getChannel(getX(${l.join()}), ${d});
          }
        }
      `;
    }
    this.userCode = `
      const ${o} start = ${o}(${i});
      const ${o} end = ${o}(${a});

      void main() {
        ${o} outputLoc = getOutputCoords();
        vec4 result = vec4(0.);
        ${f}
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const gv = ({ inputs: n, backend: e, attrs: t }) => {
  const { x: r } = n, { paddings: s, mode: o } = t, i = E().getBool("WEBGL_PACK_ARRAY_OPERATIONS") ? new mv(r.shape, s, o) : new pv(r.shape, s, o);
  return e.runWebGLProgram(i, [r], r.dtype);
}, xv = {
  kernelName: Sd,
  backendName: "webgl",
  kernelFunc: gv
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const wv = `if (b == 0.0) return NAN;
  return mod(a, b);`, Cv = `
  vec4 result = mod(a, b);
  bvec4 isNaN = equal(b, vec4(0.0));
  ` + en + `
  return result;
`, bv = we({
  opSnippet: wv,
  packedOpSnippet: Cv
}), yv = {
  kernelName: Ed,
  backendName: "webgl",
  kernelFunc: bv
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class $v {
  constructor(e, t, r) {
    this.variableNames = ["probs"], this.customUniforms = [{ name: "seed", type: "float" }], this.outputShape = [e, r], this.userCode = `
      void main() {
        ivec2 coords = getOutputCoords();
        int batch = coords[0];

        float r = random(seed);
        float cdf = 0.0;

        for (int i = 0; i < ${t - 1}; i++) {
          cdf += getProbs(batch, i);

          if (r < cdf) {
            setOutput(float(i));
            return;
          }
        }

        // If no other event happened, last event happened.
        setOutput(float(${t - 1}));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const vv = `
if (a == b) {
  return 1.0;
};
return a / b;`, Iv = `
  // vec4 one = vec4(equal(a, b));
  // return one + (vec4(1.0) - one) * a / b;
  vec4 result = a / b;
  if(a.x == b.x) {
    result.x = 1.;
  }
  if(a.y == b.y) {
    result.y = 1.;
  }
  if(a.z == b.z) {
    result.z = 1.;
  }
  if(a.w == b.w) {
    result.w = 1.;
  }

  return result;
`, ml = we({ opSnippet: vv, packedOpSnippet: Iv, checkOutOfBounds: !0 }), Sv = {
  kernelName: Oi,
  backendName: "webgl",
  kernelFunc: ml
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const wi = "return a - b;", gl = we({
  opSnippet: wi,
  packedOpSnippet: wi,
  supportsComplex: !0,
  cpuKernelImpl: ww
}), Ev = {
  kernelName: Ki,
  backendName: "webgl",
  kernelFunc: gl
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function xl(n) {
  const { inputs: e, backend: t, attrs: r } = n, { logits: s } = e, { dim: o } = r, i = Re([o], s.shape), a = pl({
    inputs: { x: s },
    backend: t,
    attrs: { reductionIndices: i, keepDims: !1 }
  }), c = gt(a.shape, i), l = D({ inputs: { x: a }, backend: t, attrs: { shape: c } }), u = gl({ inputs: { a: s, b: l }, backend: t }), d = dl({ inputs: { x: u }, backend: t }), h = Gr({ inputs: { x: d }, backend: t, attrs: { axis: i, keepDims: !1 } }), f = D({ inputs: { x: h }, backend: t, attrs: { shape: c } }), m = ml({ inputs: { a: d, b: f }, backend: t });
  return t.disposeIntermediateTensorInfo(a), t.disposeIntermediateTensorInfo(l), t.disposeIntermediateTensorInfo(u), t.disposeIntermediateTensorInfo(d), t.disposeIntermediateTensorInfo(h), t.disposeIntermediateTensorInfo(f), m;
}
const Rv = {
  kernelName: lh,
  backendName: "webgl",
  kernelFunc: xl
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Tv(n) {
  const { inputs: e, backend: t, attrs: r } = n, { logits: s } = e, { numSamples: o, seed: i, normalized: a } = r, c = a ? s : xl({ inputs: { logits: s }, backend: t, attrs: { dim: s.shape.length - 1 } }), l = c.shape[0], u = c.shape[1], d = new $v(l, u, o), h = [[i]], f = t.runWebGLProgram(d, [c], "int32", h);
  return a || t.disposeIntermediateTensorInfo(c), f;
}
const Nv = {
  kernelName: Rd,
  backendName: "webgl",
  kernelFunc: Tv
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const kv = je + `
  return -x;
`, Av = `
  vec4 result = -x;
  bvec4 isNaN = isnan(x);

  result.r = isNaN.r ? x.r : result.r;
  result.g = isNaN.g ? x.g : result.g;
  result.b = isNaN.b ? x.b : result.b;
  result.a = isNaN.a ? x.a : result.a;

  return result;
`;
function Fv(n) {
  const { inputs: e, backend: t } = n, { x: r } = e;
  if (t.shouldExecuteOnCPU([r])) {
    const o = t.texData.get(r.dataId), [i, a] = J0(o.values, r.shape, r.dtype);
    return t.makeTensorInfo(a, r.dtype, i);
  }
  let s;
  return E().getBool("WEBGL_PACK_UNARY_OPERATIONS") ? s = new St(r.shape, Av) : s = new ct(r.shape, kv), t.runWebGLProgram(s, [r], r.dtype);
}
const Dv = {
  kernelName: Td,
  backendName: "webgl",
  kernelFunc: Fv
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Ov = Hp;
function Pv(n) {
  Qe("tf.nonMaxSuppression() in webgl locks the UI thread. Call tf.nonMaxSuppressionAsync() instead");
  const { inputs: e, backend: t, attrs: r } = n, { boxes: s, scores: o } = e, { maxOutputSize: i, iouThreshold: a, scoreThreshold: c } = r, l = t.readSync(s.dataId), u = t.readSync(o.dataId), { selectedIndices: d } = Ov(l, u, i, a, c);
  return t.makeTensorInfo([d.length], "int32", new Int32Array(d));
}
const _v = {
  kernelName: kd,
  backendName: "webgl",
  kernelFunc: Pv
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Bv = Xp;
function Lv(n) {
  Qe("tf.nonMaxSuppression() in webgl locks the UI thread. Call tf.nonMaxSuppressionAsync() instead");
  const { inputs: e, backend: t, attrs: r } = n, { boxes: s, scores: o } = e, { maxOutputSize: i, iouThreshold: a, scoreThreshold: c, padToMaxOutputSize: l } = r, u = t.readSync(s.dataId), d = t.readSync(o.dataId), { selectedIndices: h, validOutputs: f } = Bv(u, d, i, a, c, l);
  return [
    t.makeTensorInfo([h.length], "int32", new Int32Array(h)),
    t.makeTensorInfo([], "int32", new Int32Array([f]))
  ];
}
const Mv = {
  kernelName: Ad,
  backendName: "webgl",
  kernelFunc: Lv
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Uv = jp;
function Vv(n) {
  Qe("tf.nonMaxSuppression() in webgl locks the UI thread. Call tf.nonMaxSuppressionAsync() instead");
  const { inputs: e, backend: t, attrs: r } = n, { boxes: s, scores: o } = e, { maxOutputSize: i, iouThreshold: a, scoreThreshold: c, softNmsSigma: l } = r, u = t.readSync(s.dataId), d = t.readSync(o.dataId), h = i, f = a, m = c, C = l, { selectedIndices: w, selectedScores: x } = Uv(u, d, h, f, m, C);
  return [
    t.makeTensorInfo([w.length], "int32", new Int32Array(w)),
    t.makeTensorInfo([x.length], "float32", new Float32Array(x))
  ];
}
const Wv = {
  kernelName: Fd,
  backendName: "webgl",
  kernelFunc: Vv
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Gv {
  constructor(e, t, r, s) {
    this.variableNames = ["indices"], this.outputShape = [e, t], this.userCode = `
      void main() {
        ivec2 coords = getOutputCoords();
        int index = round(getIndices(coords.x));
        setOutput(mix(float(${s}), float(${r}),
                      float(index == coords.y)));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const zv = (n) => {
  const { inputs: e, backend: t, attrs: r } = n, { indices: s } = e, { dtype: o, depth: i, onValue: a, offValue: c } = r, l = _(s.shape), u = new Gv(l, i, a, c), d = D({ inputs: { x: s }, backend: t, attrs: { shape: [l] } }), h = t.runWebGLProgram(u, [d], o);
  t.disposeIntermediateTensorInfo(d);
  const f = [...s.shape, i], m = D({ inputs: { x: h }, backend: t, attrs: { shape: f } });
  return t.disposeIntermediateTensorInfo(h), m;
}, Hv = {
  kernelName: Od,
  backendName: "webgl",
  kernelFunc: zv
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function Ar(n) {
  const { inputs: e, backend: t } = n, { x: r } = e;
  if (r.dtype === "complex64") {
    const s = rr({ inputs: { input: r }, backend: t }), o = Ar({ inputs: { x: s }, backend: t }), i = zr({ inputs: { input: r }, backend: t }), a = Ar({ inputs: { x: i }, backend: t }), c = Nt({ inputs: { real: o, imag: a }, backend: t });
    return t.disposeIntermediateTensorInfo(s), t.disposeIntermediateTensorInfo(o), t.disposeIntermediateTensorInfo(i), t.disposeIntermediateTensorInfo(a), c;
  } else
    return sr({
      attrs: {
        shape: r.shape,
        dtype: r.dtype,
        value: r.dtype === "string" ? "" : 0
      },
      backend: t
    });
}
const Xv = {
  kernelName: Qi,
  backendName: "webgl",
  kernelFunc: Ar
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function wl(n) {
  const { inputs: e, backend: t } = n, { x: r } = e;
  if (r.dtype === "string")
    throw new Error("onesLike is not supported under string dtype");
  if (r.dtype === "complex64") {
    const s = rr({ inputs: { input: r }, backend: t }), o = wl({ inputs: { x: s }, backend: t }), i = zr({ inputs: { input: r }, backend: t }), a = Ar({ inputs: { x: i }, backend: t }), c = Nt({ inputs: { real: o, imag: a }, backend: t });
    return t.disposeIntermediateTensorInfo(s), t.disposeIntermediateTensorInfo(o), t.disposeIntermediateTensorInfo(i), t.disposeIntermediateTensorInfo(a), c;
  } else
    return sr({ attrs: { shape: r.shape, dtype: r.dtype, value: 1 }, backend: t });
}
const jv = {
  kernelName: Dd,
  backendName: "webgl",
  kernelFunc: wl
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function qv(n) {
  const { inputs: e, backend: t, attrs: r } = n, { axis: s } = r;
  if (e.length === 1)
    return ks({ inputs: { input: e[0] }, backend: t, attrs: { dim: s } });
  const o = e[0].shape, i = e[0].dtype;
  e.forEach((u) => {
    vi(o, u.shape, "All tensors passed to stack must have matching shapes"), O(i === u.dtype, () => "All tensors passed to stack must have matching dtypes");
  });
  const a = [], c = e.map((u) => {
    const d = ks({ inputs: { input: u }, backend: t, attrs: { dim: s } });
    return a.push(d), d;
  }), l = rl({ inputs: c, backend: t, attrs: { axis: s } });
  return a.forEach((u) => t.disposeIntermediateTensorInfo(u)), l;
}
const Kv = {
  kernelName: Pd,
  backendName: "webgl",
  kernelFunc: qv
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Yv {
  constructor(e, t, r) {
    this.variableNames = ["x"], this.customUniforms = [{ name: "value", type: "float" }], this.outputShape = t.map(
      (l, u) => l[0] + e[u] + l[1]
      /* afterPad */
    );
    const s = e.length, o = K(s), i = t.map((l) => l[0]).join(","), a = t.map((l, u) => l[0] + e[u]).join(","), c = ["coords[0]", "coords[1]", "coords[2]", "coords[3]"].slice(0, s);
    if (s === 1) {
      this.userCode = `
        int start = ${i};
        int end = ${a};

        void main() {
          int outC = getOutputCoords();
          if (outC < start || outC >= end) {
            setOutput(value);
          } else {
            setOutput(getX(outC - start));
          }
        }
      `;
      return;
    }
    this.userCode = `
      ${o} start = ${o}(${i});
      ${o} end = ${o}(${a});

      void main() {
        ${o} outC = getOutputCoords();
        if (any(lessThan(outC, start)) || any(greaterThanEqual(outC, end))) {
          setOutput(value);
        } else {
          ${o} coords = outC - start;
          setOutput(getX(${c}));
        }
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class Qv {
  constructor(e, t, r) {
    this.variableNames = ["x"], this.packedInputs = !0, this.packedOutput = !0, this.customUniforms = [{ name: "value", type: "float" }], this.outputShape = t.map(
      (C, w) => C[0] + e[w] + C[1]
      /* afterPad */
    );
    const s = e.length, o = K(s), i = t.map((C) => C[0]).join(","), a = t.map((C, w) => C[0] + e[w]).join(","), c = $e("rc", s), l = $e("source", s), u = `${c[s - 1]} < ${this.outputShape[s - 1]}`, d = s === 1 ? "source" : `vec2(${l.slice(-2).join()})`, h = [
      `${o} rc = outputLoc;`,
      `${c[s - 1]} += 1;
       if(${u}) {
      `,
      s === 1 ? "" : `}
       rc = outputLoc;
       ${c[s - 2]} += 1;
       if(${c[s - 2]} < ${this.outputShape[s - 2]}) {`,
      s === 1 ? "" : `  ${c[s - 1]} += 1;
         if(${u}) {`
    ], f = s === 1 ? "rc < start || rc >= end" : "any(lessThan(rc, start)) || any(greaterThanEqual(rc, end))";
    let m = "";
    for (let C = 0, w = s === 1 ? 2 : 4; C < w; C++)
      m += `
        ${h[C]}
        if (${f}) {
          result[${C}] = float(value);
        } else {
          ${o} source = rc - start;
          result[${C}] = getChannel(getX(${l.join()}), ${d});
        }
      `;
    m += s === 1 ? "} " : "}}", this.userCode = `
      const ${o} start = ${o}(${i});
      const ${o} end = ${o}(${a});

      void main() {
        ${o} outputLoc = getOutputCoords();
        vec4 result = vec4(0.);
        ${m}
        setOutput(result);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Cl = (n) => {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { paddings: o, constantValue: i } = r;
  if (_(s.shape) === 0) {
    const l = o.map(
      (u, d) => u[0] + s.shape[d] + u[1]
      /* afterPad */
    );
    return sr({
      backend: t,
      attrs: { shape: l, value: i, dtype: s.dtype }
    });
  }
  const a = E().getBool("WEBGL_PACK_ARRAY_OPERATIONS") ? new Qv(s.shape, o, i) : new Yv(s.shape, o, i), c = [[i]];
  return t.runWebGLProgram(a, [s], s.dtype, c);
}, Zv = {
  kernelName: _d,
  backendName: "webgl",
  kernelFunc: Cl
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Jv = `
  if(a < 0.0 && floor(b) < b){
    return NAN;
  }
  if (b == 0.0) {
    return 1.0;
  }
  return (round(mod(b, 2.0)) != 1) ?
      pow(abs(a), b) : sign(a) * pow(abs(a), b);
`, eI = `
  // isModRound1 has 1 for components with round(mod(b, 2.0)) == 1, 0 otherwise.
  vec4 isModRound1 = vec4(equal(round(mod(b, 2.0)), ivec4(1)));
  vec4 multiplier = sign(a) * isModRound1 + (vec4(1.0) - isModRound1);
  vec4 result = multiplier * pow(abs(a), b);

  // Ensure that a^0 = 1, including 0^0 = 1 as this correspond to TF and JS
  bvec4 isExpZero = equal(b, vec4(0.0));
  result.r = isExpZero.r ? 1.0 : result.r;
  result.g = isExpZero.g ? 1.0 : result.g;
  result.b = isExpZero.b ? 1.0 : result.b;
  result.a = isExpZero.a ? 1.0 : result.a;

  bvec4 isNaN1 = lessThan(a, vec4(0.0));
  bvec4 isNaN2 = lessThan(floor(b), b);
  bvec4 isNaN = bvec4(isNaN1.x && isNaN2.x, isNaN1.y && isNaN2.y, isNaN1.z && isNaN2.z, isNaN1.w && isNaN2.w);
  ` + en + `
  return result;
`, tI = we({ opSnippet: Jv, packedOpSnippet: eI }), nI = {
  kernelName: Vi,
  backendName: "webgl",
  kernelFunc: tI
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function rI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { axis: o, keepDims: i } = r, a = s.shape.length, c = [], l = Re(o, s.shape);
  let u = l;
  const d = He(u, a);
  let h = s;
  d != null && (h = Ie({ inputs: { x: s }, backend: t, attrs: { perm: d } }), u = Xe(u.length, a), c.push(h)), tt("prod", u, a);
  let f;
  if (t.shouldExecuteOnCPU([h])) {
    const m = t.texData.get(h.dataId).values, { outVals: C, outShape: w, outDtype: x } = tw(h.shape, h.dtype, m, u);
    f = t.makeTensorInfo(w, x, C);
  } else {
    const [m, C] = ht(h.shape, u), w = _(C), x = D({ inputs: { x: h }, backend: t, attrs: { shape: [-1, w] } }), y = Ms(s.dtype), v = tn(x, y, "prod", t);
    f = D({ inputs: { x: v }, backend: t, attrs: { shape: m } }), c.push(x), c.push(v);
  }
  if (i) {
    c.push(f);
    const m = gt(f.shape, l);
    f = D({ inputs: { x: f }, backend: t, attrs: { shape: m } });
  }
  return c.forEach((m) => t.disposeIntermediateTensorInfo(m)), f;
}
const sI = {
  kernelName: Bd,
  backendName: "webgl",
  kernelFunc: rI
};
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function oI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { paramsNestedSplits: s, paramsDenseValues: o, indices: i } = e, { outputRaggedRank: a } = r, c = s.map((x) => t.readSync(x.dataId)), l = s.map((x) => x.shape), u = t.readSync(o.dataId), d = t.readSync(i.dataId), [h, f, m] = nw(c, l, u, o.shape, o.dtype, d, i.shape, a), C = h.map((x) => t.makeTensorInfo([x.length], "int32", x)), w = t.makeTensorInfo(m, o.dtype, f);
  return C.concat([w]);
}
const iI = {
  kernelName: Ld,
  backendName: "webgl",
  kernelFunc: oI
};
/**
 * @license
 * Copyright 2022 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function aI(n) {
  const { inputs: e, backend: t } = n, { starts: r, limits: s, deltas: o } = e, i = t.readSync(r.dataId), a = t.readSync(s.dataId), c = t.readSync(o.dataId), [l, u] = rw(i, r.shape, r.dtype, a, s.shape, c, o.shape), d = t.makeTensorInfo([l.length], "int32", l), h = t.makeTensorInfo([u.length], r.dtype, u);
  return [d, h];
}
const cI = {
  kernelName: Md,
  backendName: "webgl",
  kernelFunc: aI
};
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function lI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { shape: s, values: o, defaultValue: i, rowPartitionTensors: a } = e, { rowPartitionTypes: c } = r, l = t.readSync(s.dataId), u = t.readSync(o.dataId), d = t.readSync(i.dataId), h = a.map((w) => t.readSync(w.dataId)), f = a.map((w) => w.shape), [m, C] = sw(l, s.shape, u, o.shape, o.dtype, d, i.shape, h, f, c);
  return t.makeTensorInfo(m, o.dtype, C);
}
const uI = {
  kernelName: Ud,
  backendName: "webgl",
  kernelFunc: lI
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const bl = (n) => {
  const { backend: e, attrs: t } = n, { start: r, stop: s, step: o, dtype: i } = t, a = ow(r, s, o, i);
  return e.makeTensorInfo([a.length], i, a);
}, dI = {
  kernelName: Vd,
  backendName: "webgl",
  kernelFunc: bl
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const hI = "return 1.0 / x;", fI = H({ opSnippet: hI }), pI = {
  kernelName: Gd,
  backendName: "webgl",
  kernelFunc: fI
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const mI = je + `
  return (x < 0.0) ? 0.0 : x;
`, gI = `
  vec4 result = x * vec4(greaterThanEqual(x, vec4(0.0)));
  bvec4 isNaN = isnan(x);

  result.r = isNaN.r ? x.r : result.r;
  result.g = isNaN.g ? x.g : result.g;
  result.b = isNaN.b ? x.b : result.b;
  result.a = isNaN.a ? x.a : result.a;

  return result;
`, xI = H({ opSnippet: mI, packedOpSnippet: gI }), wI = {
  kernelName: Gi,
  backendName: "webgl",
  kernelFunc: xI
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const CI = je + `
  return (x < 0.0) ? 0.0 : min(6.0, x);
`, bI = `
  vec4 result = min(x, vec4(6.)) * vec4(greaterThanEqual(x, vec4(0.0)));
  bvec4 isNaN = isnan(x);

  result.r = isNaN.r ? x.r : result.r;
  result.g = isNaN.g ? x.g : result.g;
  result.b = isNaN.b ? x.b : result.b;
  result.a = isNaN.a ? x.a : result.a;

  return result;
`, yI = H({ opSnippet: CI, packedOpSnippet: bI }), $I = {
  kernelName: Hi,
  backendName: "webgl",
  kernelFunc: yI
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class vI {
  constructor(e, t, r, s, o) {
    this.variableNames = ["A"], this.outputShape = [];
    const [i, a, c, l] = e;
    this.outputShape = [i, t, r, l];
    const u = [
      s && t > 1 ? a - 1 : a,
      s && r > 1 ? c - 1 : c
    ], d = [
      s && t > 1 ? t - 1 : t,
      s && r > 1 ? r - 1 : r
    ];
    let h;
    o ? h = "(vec2(yRC) + vec2(0.5)) * effectiveInputOverOutputRatioRC - vec2(0.5)" : h = "vec2(yRC) * effectiveInputOverOutputRatioRC", this.userCode = `
      const vec2 effectiveInputOverOutputRatioRC = vec2(
          ${u[0] / d[0]},
          ${u[1] / d[1]});
      const vec2 inputShapeRC = vec2(${a}.0, ${c}.0);

      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int d = coords[3];
        ivec2 yRC = coords.yz;

        // Fractional source index.
        vec2 sourceFracIndexRC = ${h};

        // Compute the four integer indices.
        ivec2 sourceFloorRC = ivec2(max(sourceFracIndexRC, vec2(0.0)));
        ivec2 sourceCeilRC = ivec2(
          min(inputShapeRC - 1.0, ceil(sourceFracIndexRC)));

        float topLeft = getA(b, sourceFloorRC.x, sourceFloorRC.y, d);
        float bottomLeft = getA(b, sourceCeilRC.x, sourceFloorRC.y, d);
        float topRight = getA(b, sourceFloorRC.x, sourceCeilRC.y, d);
        float bottomRight = getA(b, sourceCeilRC.x, sourceCeilRC.y, d);

        vec2 fracRC = sourceFracIndexRC - vec2(sourceFloorRC);

        float top = topLeft + (topRight - topLeft) * fracRC.y;
        float bottom = bottomLeft + (bottomRight - bottomLeft) * fracRC.y;
        float newValue = top + (bottom - top) * fracRC.x;

        setOutput(newValue);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class II {
  constructor(e, t, r, s, o) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !0, this.outputShape = [];
    const [i, a, c, l] = e;
    this.outputShape = [i, t, r, l];
    const u = [
      s && t > 1 ? a - 1 : a,
      s && r > 1 ? c - 1 : c
    ], d = [
      s && t > 1 ? t - 1 : t,
      s && r > 1 ? r - 1 : r
    ];
    let h;
    o ? h = "(vec3(yRC) + vec3(0.5)) * effectiveInputOverOutputRatioRC - vec3(0.5)" : h = "vec3(yRC) * effectiveInputOverOutputRatioRC", this.userCode = `
      const vec3 effectiveInputOverOutputRatioRC = vec3(
          ${u[0] / d[0]},
          ${u[1] / d[1]},
          ${u[1] / d[1]});
      const vec3 inputShapeRC = vec3(${a}.0, ${c}.0,
                                     ${c}.0);

      float getAValue(int b, int r, int c, int d) {
        return getChannel(getA(b, r, c, d), vec2(c, d));
      }

      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int d = coords[3];
        // Calculate values for next column in yRC.z.
        ivec3 yRC = coords.yzz + ivec3(0, 0, 1);

        // Fractional source index.
        vec3 sourceFracIndexRC = ${h};

        // Compute the four integer indices.
        ivec3 sourceFloorRC = ivec3(max(sourceFracIndexRC, vec3(0.0)));
        ivec3 sourceCeilRC = ivec3(
          min(inputShapeRC - 1.0, ceil(sourceFracIndexRC)));

        // Should we calculate next column and row elements in 2x2 packed cell.
        bool hasNextCol = d < ${l - 1};
        bool hasNextRow = coords.z < ${r - 1};

        // In parallel, construct four corners for all four components in
        // packed 2x2 cell.
        vec4 topLeft = vec4(
          getAValue(b, sourceFloorRC.x, sourceFloorRC.y, d),
          hasNextCol ? getAValue(b, sourceFloorRC.x, sourceFloorRC.y, d + 1)
                     : 0.0,
          hasNextRow ? getAValue(b, sourceFloorRC.x, sourceFloorRC.z, d)
                     : 0.0,
          (hasNextRow && hasNextCol) ?
            getAValue(b, sourceFloorRC.x, sourceFloorRC.z, d + 1) : 0.0);

        vec4 bottomLeft = vec4(
          getAValue(b, sourceCeilRC.x, sourceFloorRC.y, d),
          hasNextCol ? getAValue(b, sourceCeilRC.x, sourceFloorRC.y, d + 1)
                     : 0.0,
          hasNextRow ? getAValue(b, sourceCeilRC.x, sourceFloorRC.z, d)
                     : 0.0,
          (hasNextRow && hasNextCol) ?
            getAValue(b, sourceCeilRC.x, sourceFloorRC.z, d + 1) : 0.0);

        vec4 topRight = vec4(
          getAValue(b, sourceFloorRC.x, sourceCeilRC.y, d),
          hasNextCol ? getAValue(b, sourceFloorRC.x, sourceCeilRC.y, d + 1)
                     : 0.0,
          hasNextRow ? getAValue(b, sourceFloorRC.x, sourceCeilRC.z, d)
                     : 0.0,
          (hasNextRow && hasNextCol) ?
            getAValue(b, sourceFloorRC.x, sourceCeilRC.z, d + 1) : 0.0);

        vec4 bottomRight = vec4(
          getAValue(b, sourceCeilRC.x, sourceCeilRC.y, d),
          hasNextCol ? getAValue(b, sourceCeilRC.x, sourceCeilRC.y, d + 1)
                     : 0.0,
          hasNextRow ? getAValue(b, sourceCeilRC.x, sourceCeilRC.z, d)
                     : 0.0,
          (hasNextRow && hasNextCol) ?
            getAValue(b, sourceCeilRC.x, sourceCeilRC.z, d + 1) : 0.0);

        vec3 fracRC = sourceFracIndexRC - vec3(sourceFloorRC);

        vec4 top = mix(topLeft, topRight, fracRC.yyzz);
        vec4 bottom = mix(bottomLeft, bottomRight, fracRC.yyzz);
        vec4 newValue = mix(top, bottom, fracRC.x);

        setOutput(newValue);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function SI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { images: s } = e, { alignCorners: o, halfPixelCenters: i, size: a } = r, [c, l] = a, u = E().getBool("WEBGL_PACK_IMAGE_OPERATIONS") ? new II(s.shape, c, l, o, i) : new vI(s.shape, c, l, o, i);
  return t.runWebGLProgram(u, [s], "float32");
}
const EI = {
  kernelName: Xd,
  backendName: "webgl",
  kernelFunc: SI
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class RI {
  constructor(e, t, r) {
    this.variableNames = ["dy"], this.outputShape = [], this.outputShape = t;
    const [, s, o] = t, [, i, a] = e, c = [
      r && i > 1 ? s - 1 : s,
      r && a > 1 ? o - 1 : o
    ], l = [
      r && i > 1 ? i - 1 : i,
      r && a > 1 ? a - 1 : a
    ], u = c[0] / l[0], d = c[1] / l[1], h = 1 / u, f = 1 / d, m = Math.ceil(h) * 2 + 2, C = Math.ceil(f) * 2 + 2;
    this.userCode = `
      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int d = coords[3];
        int r = coords[1];
        int c = coords[2];

        float accumulator = 0.0;

        const float heightScale = float(${u});
        const float widthScale = float(${d});

        const float invHeightScale = float(${h});
        const float invWidthScale = float(${f});

        const int winHeight = int(${m});
        const int winWidth = int(${C});

        // Compute bounds for where in dy we will look
        float startRLerp = floor(float(r) * invHeightScale);
        int startDyR = int(startRLerp - float(winHeight / 2));

        float startCLerp = floor(float(c) * invWidthScale);
        int startDyC = int(startCLerp - float(winWidth / 2));

        // Loop over dy
        for (int dyROffset = 0; dyROffset < winHeight; dyROffset++) {
          int dyR = dyROffset + startDyR;

          // Guard against the window exceeding the bounds of dy
          if (dyR < 0 || dyR >= ${i}) {
            continue;
          }

          for (int dyCOffset = 0; dyCOffset < winWidth; dyCOffset++) {
            int dyC = dyCOffset + startDyC;

            // Guard against the window exceeding the bounds of dy
            if (dyC < 0 || dyC >= ${a}) {
              continue;
            }

            float dxR = float(dyR) * heightScale;
            int topDxRIndex = int(floor(dxR));
            int bottomDxRIndex = int(min(ceil(dxR), ${s - 1}.0));
            float dxRLerp = dxR - float(topDxRIndex);
            float inverseDxRLerp = 1.0 - dxRLerp;

            float dxC = float(dyC) * widthScale;
            int leftDxCIndex = int(floor(dxC));
            int rightDxCIndex = int(min(ceil(dxC), ${o - 1}.0));
            float dxCLerp = dxC - float(leftDxCIndex);
            float inverseDxCLerp = 1.0 - dxCLerp;

            if (r == topDxRIndex && c == leftDxCIndex) {
              // topLeft
              accumulator +=
                getDy(b, dyR, dyC, d) * inverseDxRLerp * inverseDxCLerp;
            }

            if (r == topDxRIndex && c == rightDxCIndex) {
              // topRight
              accumulator += getDy(b, dyR, dyC, d) * inverseDxRLerp * dxCLerp;
            }

            if (r == bottomDxRIndex && c == leftDxCIndex) {
              // bottomLeft
              accumulator += getDy(b, dyR, dyC, d) * dxRLerp * inverseDxCLerp;
            }

            if (r == bottomDxRIndex && c == rightDxCIndex) {
              // bottomRight
              accumulator += getDy(b, dyR, dyC, d) * dxRLerp * dxCLerp;
            }
          }
        }
        // End loop over dy

        setOutput(accumulator);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function TI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { images: s, dy: o } = e, { alignCorners: i } = r, a = new RI(o.shape, s.shape, i);
  return t.runWebGLProgram(a, [o], o.dtype);
}
const NI = {
  kernelName: jd,
  backendName: "webgl",
  kernelFunc: TI
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class kI {
  constructor(e, t, r, s, o) {
    this.variableNames = ["A"], this.outputShape = [];
    const [i, a, c, l] = e;
    this.outputShape = [i, t, r, l];
    const u = [
      s && t > 1 ? a - 1 : a,
      s && r > 1 ? c - 1 : c
    ], d = [
      s && t > 1 ? t - 1 : t,
      s && r > 1 ? r - 1 : r
    ], h = s ? "0.5" : "0.0";
    let f;
    o ? f = "max((vec2(yRC) + vec2(0.5)) * effectiveInputOverOutputRatioRC, vec2(0.0))" : f = "vec2(yRC) * effectiveInputOverOutputRatioRC", this.userCode = `
      const vec2 effectiveInputOverOutputRatioRC = vec2(
          ${u[0] / d[0]},
          ${u[1] / d[1]});
      const vec2 inputShapeRC = vec2(${a}.0, ${c}.0);

      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int d = coords[3];
        ivec2 yRC = coords.yz;

        // Fractional source index.
        vec2 sourceFracIndexRC = ${f};

        // Compute the coordinators of nearest neighbor point.
        ivec2 sourceNearestRC = ivec2(
          min(inputShapeRC - 1.0, floor(sourceFracIndexRC + ${h})));
        float newValue = getA(b, sourceNearestRC.x, sourceNearestRC.y, d);

        setOutput(newValue);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class AI {
  constructor(e, t, r, s, o) {
    this.variableNames = ["A"], this.packedInputs = !0, this.packedOutput = !0, this.outputShape = [];
    const [i, a, c, l] = e;
    this.outputShape = [i, t, r, l];
    const u = [
      s && t > 1 ? a - 1 : a,
      s && r > 1 ? c - 1 : c
    ], d = [
      s && t > 1 ? t - 1 : t,
      s && r > 1 ? r - 1 : r
    ], h = s ? "0.5" : "0.0";
    let f;
    o ? f = "max((vec3(yRC) + vec3(0.5)) * effectiveInputOverOutputRatioRC, vec3(0.0))" : f = "vec3(yRC) * effectiveInputOverOutputRatioRC", this.userCode = `
      const vec3 effectiveInputOverOutputRatioRC = vec3(
          ${u[0] / d[0]},
          ${u[1] / d[1]},
          ${u[1] / d[1]});
      const vec3 inputShapeRC = vec3(${a}.0, ${c}.0,
                                     ${c}.0);

      float getAValue(int b, int r, int c, int d) {
        return getChannel(getA(b, r, c, d), vec2(c, d));
      }

      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int d = coords[3];
        // Calculate values for next column in yRC.z.
        ivec3 yRC = coords.yzz + ivec3(0, 0, 1);

        // Fractional source index.
        vec3 sourceFracIndexRC = ${f};

        // Compute the coordinators of nearest neighbor point.
        ivec3 sourceNearestRC = ivec3(
          min(inputShapeRC - 1.0, floor(sourceFracIndexRC + ${h})));

        // Should we calculate next column and row elements in 2x2 packed cell.
        bool hasNextCol = d < ${l - 1};
        bool hasNextRow = coords.z < ${r - 1};

        vec4 newValue = vec4(
          getAValue(b, sourceNearestRC.x, sourceNearestRC.y, d),
          hasNextCol ? getAValue(b, sourceNearestRC.x, sourceNearestRC.y, d + 1)
                     : 0.0,
          hasNextRow ? getAValue(b, sourceNearestRC.x, sourceNearestRC.z, d)
                     : 0.0,
          (hasNextRow && hasNextCol) ?
            getAValue(b, sourceNearestRC.x, sourceNearestRC.z, d + 1) : 0.0);

        setOutput(newValue);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function FI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { images: s } = e, { alignCorners: o, halfPixelCenters: i, size: a } = r, [c, l] = a, u = E().getBool("WEBGL_PACK_IMAGE_OPERATIONS") ? new AI(s.shape, c, l, o, i) : new kI(s.shape, c, l, o, i);
  return t.runWebGLProgram(u, [s], s.dtype);
}
const DI = {
  kernelName: zd,
  backendName: "webgl",
  kernelFunc: FI
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class OI {
  constructor(e, t, r) {
    this.variableNames = ["dy"], this.outputShape = [], this.outputShape = t;
    const [, s, o] = t, [, i, a] = e, c = [
      r && i > 1 ? s - 1 : s,
      r && a > 1 ? o - 1 : o
    ], l = [
      r && i > 1 ? i - 1 : i,
      r && a > 1 ? a - 1 : a
    ], u = c[0] / l[0], d = c[1] / l[1], h = 1 / u, f = 1 / d, m = Math.ceil(h) * 2 + 2, C = Math.ceil(f) * 2 + 2;
    this.userCode = `
      void main() {
        ivec4 coords = getOutputCoords();
        int b = coords[0];
        int d = coords[3];
        int r = coords[1];
        int c = coords[2];

        float accumulator = 0.0;

        const float heightScale = float(${u});
        const float widthScale = float(${d});

        const float invHeightScale = float(${h});
        const float invWidthScale = float(${f});

        const int winHeight = int(${m});
        const int winWidth = int(${C});

        // Compute bounds for where in dy we will look
        float startRLerp = floor(float(r) * invHeightScale);
        int startDyR = int(floor(startRLerp - float(winHeight / 2)));

        float startCLerp = floor(float(c) * invWidthScale);
        int startDyC = int(floor(startCLerp - float(winWidth / 2)));

        // Loop over dy
        for (int dyROffset = 0; dyROffset < winHeight; dyROffset++) {
          int dyR = dyROffset + startDyR;

          // Guard against the window exceeding the bounds of dy
          if (dyR < 0 || dyR >= ${i}) {
            continue;
          }

          for (int dyCOffset = 0; dyCOffset < winWidth; dyCOffset++) {
            int dyC = dyCOffset + startDyC;

            // Guard against the window exceeding the bounds of dy
            if (dyC < 0 || dyC >= ${a}) {
              continue;
            }

            float sourceFracRow =
              float(${c[0]}) *
                (float(dyR) / float(${l[0]}));

            float sourceFracCol =
                float(${c[1]}) *
                  (float(dyC) / float(${l[1]}));

            int sourceNearestRow = int(min(
                float(int(${s}) - 1),
                ${r} ? float(round(sourceFracRow)) :
                                  float(floor(sourceFracRow))));

            int sourceNearestCol = int(min(
                float(int(${o}) - 1),
                ${r} ? float(round(sourceFracCol)) :
                                  float(floor(sourceFracCol))));

            if (r == sourceNearestRow && c == sourceNearestCol) {
              accumulator += getDy(b, dyR, dyC, d);
            }
          }
        }
        // End loop over dy

        setOutput(accumulator);
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function PI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { images: s, dy: o } = e, { alignCorners: i } = r, a = new OI(o.shape, s.shape, i);
  return t.runWebGLProgram(a, [o], o.dtype);
}
const _I = {
  kernelName: Hd,
  backendName: "webgl",
  kernelFunc: PI
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class BI {
  constructor(e, t) {
    this.variableNames = ["x"];
    const r = e.length;
    if (r > 4)
      throw new Error(`WebGL backend: Reverse of rank-${r} tensor is not yet supported`);
    if (this.outputShape = e, r === 1) {
      this.userCode = `
        void main() {
          int coord = getOutputCoords();
          setOutput(getX(${e[0]} - coord - 1));
        }
      `;
      return;
    }
    const s = (a) => t.indexOf(a) !== -1 && e[a] !== 1 ? `${e[a]} - coords[${a}] - 1` : `coords[${a}]`, o = e.map((a, c) => s(c)).join(","), i = K(r);
    this.userCode = `
      void main() {
        ${i} coords = getOutputCoords();
        setOutput(getX(${o}));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class LI {
  constructor(e, t) {
    this.variableNames = ["x"], this.packedInputs = !0, this.packedOutput = !0;
    const r = e.length;
    if (r > 4)
      throw new Error(`WebGL backend: Reverse of rank-${r} tensor is not yet supported`);
    this.outputShape = e;
    const s = $e("rc", r), o = `${s[r - 1]} + 1 < ${this.outputShape[r - 1]}`, i = `${s[r - 2]} + 1 < ${this.outputShape[r - 2]}`, a = K(r);
    r === 1 ? this.userCode = `
        void main(){
          int rc = getOutputCoords();
          vec4 result = vec4(0.);
          result.r = getChannel(getX(${e[0]} - rc - 1),
            ${e[0]} - rc - 1);
          if(${o}){
              result.g = getChannel(getX(${e[0]} - (rc  + 1) - 1),
                ${e[0]} - (rc  + 1) - 1);
          }
          setOutput(result);
        }
      ` : this.userCode = `
        void main() {
          ${a} rc = getOutputCoords();
          vec4 result = vec4(0.);
          result.r = ${c(s.slice())};
          if(${o}){
            result.g = ${l(s.slice())};
          }
          if(${i}) {
            result.b = ${u(s.slice())};
            if(${o}) {
              result.a = ${d(s.slice())};
            }
          }
          setOutput(result);
        }
    `;
    function c(m) {
      return h(m);
    }
    function l(m) {
      return m[r - 1] = "(" + m[r - 1] + " + 1)", h(m);
    }
    function u(m) {
      return m[r - 2] = "(" + m[r - 2] + " + 1)", h(m);
    }
    function d(m) {
      return m[r - 1] = "(" + m[r - 1] + " + 1)", m[r - 2] = "(" + m[r - 2] + " + 1)", h(m);
    }
    function h(m) {
      const C = e.map((y, v) => f(v, m)), w = C.join(","), x = C.slice(-2).join(",");
      return `getChannel(getX(${w}), vec2(${x}))`;
    }
    function f(m, C) {
      return t.indexOf(m) !== -1 && e[m] !== 1 ? `${e[m]} - ${C[m]} - 1` : `${C[m]}`;
    }
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function MI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { dims: o } = r, i = s.shape.length, a = Re(o, s.shape);
  if (i === 0)
    return De({ inputs: { x: s }, backend: t });
  const c = E().getBool("WEBGL_PACK_ARRAY_OPERATIONS") ? new LI(s.shape, a) : new BI(s.shape, a);
  return t.runWebGLProgram(c, [s], s.dtype);
}
const UI = {
  kernelName: qd,
  backendName: "webgl",
  kernelFunc: MI
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class VI {
  constructor(e, t) {
    this.variableNames = ["Image"], this.outputShape = [], this.customUniforms = [{ name: "params", type: "vec4" }];
    const r = e[1], s = e[2];
    this.outputShape = e;
    let o = "";
    typeof t == "number" ? o = `float outputValue = ${t.toFixed(2)};` : o = `
        vec3 fill = vec3(${t.join(",")});
        float outputValue = fill[coords[3]];`, this.userCode = `
        void main() {
          ivec4 coords = getOutputCoords();
          int x = coords[2];
          int y = coords[1];
          float coordXFloat = (float(x) - params[0]) * params[3] -
            (float(y) - params[1]) * params[2];
          float coordYFloat = (float(x) - params[0]) * params[2] +
            (float(y) - params[1]) * params[3];
          int coordX = int(round(coordXFloat + params[0]));
          int coordY = int(round(coordYFloat + params[1]));
          ${o}
          if(coordX >= 0 && coordX < ${s} && coordY >= 0 && coordY < ${r}) {
            outputValue = getImage(coords[0], coordY, coordX, coords[3]);
          }
          setOutput(outputValue);
        }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const WI = {
  kernelName: Ah,
  backendName: "webgl",
  kernelFunc: ({ inputs: n, attrs: e, backend: t }) => {
    const { image: r } = n, { radians: s, fillValue: o, center: i } = e, a = t, c = new VI(r.shape, o), [l, u] = Qa(i, r.shape[1], r.shape[2]), d = [[l, u, Math.sin(s), Math.cos(s)]];
    return a.runWebGLProgram(c, [r], r.dtype, d);
  }
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const GI = `
  // OpenGL ES does not support round function.
  // The algorithm is based on banker's rounding.
  float base = floor(x);
  if ((x - base) < 0.5) {
    return floor(x);
  } else if ((x - base) > 0.5) {
    return ceil(x);
  } else {
    if (mod(base, 2.0) == 0.0) {
      return base;
    } else {
      return base + 1.0;
    }
  }
`, zI = H({ opSnippet: GI }), HI = {
  kernelName: Kd,
  backendName: "webgl",
  kernelFunc: zI
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const XI = "return inversesqrt(x);", jI = H({ opSnippet: XI, cpuKernelImpl: iw }), qI = {
  kernelName: Yd,
  backendName: "webgl",
  kernelFunc: jI
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class lo {
  constructor(e, t, r, s, o, i, a = !0, c = !1) {
    this.variableNames = ["updates", "indices", "defaultValue"], this.outputShape = i;
    const l = K(o.length), u = K(i.length);
    let d = "";
    r === 1 ? d = "i" : r === 2 && (d = "i, j");
    const h = `getIndices(${d})`;
    let f = "";
    s === 1 ? f = "i" : s === 2 && (f = "i, coords[1]");
    const m = `getUpdates(${f})`;
    let C = "";
    c && (C = "coords[0], coords[1]");
    const w = `getDefaultValue(${C})`, x = t > 1 ? "strides[j]" : "strides";
    this.userCode = `
        ${l} strides = ${l}(${o});

        void main() {
          ${u} coords = getOutputCoords();
          float sum = 0.0;
          bool found = false;
          for (int i = 0; i < ${e}; i++) {
            int flattenedIndex = 0;
            for (int j = 0; j < ${t}; j++) {
              int index = round(${h});
              flattenedIndex += index * ${x};
            }
            if (flattenedIndex == coords[0]) {
              sum += ${m};
              found = true;
            }
          }
          setOutput(mix(${w}, sum, float(found)));
        }
      `;
  }
}
/**
 * @license
 * Copyright 2023 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class KI {
  constructor(e, t, r, s, o, i, a = !0, c = !1) {
    this.variableNames = ["updates", "indices", "defaultValue"], this.packedInputs = !0, this.packedOutput = !0, this.outputShape = i;
    const l = K(o.length), u = K(i.length);
    let d = "";
    r === 1 ? d = "i" : r === 2 && (d = "i, j");
    const h = `getIndices(${d})`;
    let f = "";
    s === 1 ? f = "i" : s === 2 && (f = "i, coords[1]");
    const m = `getUpdates(${f})`;
    let C = "";
    c && (C = "coords[0], coords[1]");
    const w = `getDefaultValue(${C})`, x = t > 1 ? "strides[j]" : "strides", y = t > 1 ? "strides[j + 1]" : "strides";
    this.userCode = `
        ${l} strides = ${l}(${o});

        void main() {
          ${u} coords = getOutputCoords();
          vec4 sum = vec4(0.);
          vec4 found = vec4(0.);
          for (int i = 0; i < ${e}; i+=2) {
            ivec2 flattenedIndex = ivec2(0);
            for (int j = 0; j < ${t}; j+=2) {
              ivec4 index = round(${h});
              flattenedIndex += index.xz * ${x};
              if (j + 1 < ${t}) {
                flattenedIndex += index.yw * ${y};
              }
            }
            if (flattenedIndex[0] == coords[0] || flattenedIndex[1] == coords[0] ||
                flattenedIndex[0] == coords[0] + 1 || flattenedIndex[1] == coords[0] + 1) {
              vec4 updVals = ${m};
              if (flattenedIndex[0] == coords[0]) {
                sum.xy += updVals.xy;
                found.xy = vec2(1.);
              } else if (flattenedIndex[0] == coords[0] + 1) {
                sum.zw += updVals.xy;
                found.zw = vec2(1.);
              }
              if (flattenedIndex[1] == coords[0]) {
                sum.xy += updVals.zw;
                found.xy = vec2(1.);
              } else if (flattenedIndex[1] == coords[0] + 1) {
                sum.zw += updVals.zw;
                found.zw = vec2(1.);
              }
            }
          }
          setOutput(mix(${w}, sum, found));
        }
      `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function YI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { indices: s, updates: o } = e, { shape: i } = r, { sliceRank: a, numUpdates: c, sliceSize: l, strides: u, outputSize: d } = Lr(o, s, i), h = [d / l, l];
  if (d === 0)
    return t.makeTensorInfo(i, s.dtype);
  const f = D({ inputs: { x: s }, backend: t, attrs: { shape: [c, a] } }), m = D({ inputs: { x: o }, backend: t, attrs: { shape: [c, l] } }), C = t.makeTensorInfo([], "float32", new Float32Array([0]));
  let w;
  E().getBool("WEBGL_PACK") ? w = new KI(c, a, f.shape.length, m.shape.length, u, h) : w = new lo(c, a, f.shape.length, m.shape.length, u, h);
  const x = t.runWebGLProgram(w, [m, f, C], m.dtype), y = D({ inputs: { x }, backend: t, attrs: { shape: i } });
  return t.disposeIntermediateTensorInfo(f), t.disposeIntermediateTensorInfo(m), t.disposeIntermediateTensorInfo(x), t.disposeIntermediateTensorInfo(C), y;
}
const QI = {
  kernelName: Qd,
  backendName: "webgl",
  kernelFunc: YI
};
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class ZI {
  constructor(e, t, r, s) {
    this.variableNames = ["sortedSequence", "values"], this.customUniforms = [{ name: "numInputs", type: "int" }], this.outputShape = [e, r];
    const o = "while (left < right) {", i = `for (int i = 0; i < ${Math.ceil(Math.log2(t + 1))}; ++i) { if (left >= right) break;`, a = E().getNumber("WEBGL_VERSION") === 2 ? o : i, c = s === "left" ? "<" : "<=";
    this.userCode = `
       int findBound(int batch, float value) {
         int left = 0;
         int right = numInputs;
         int mid;
         ${a}
           mid = (left + right) / 2;
           if (getSortedSequence(batch, mid) ${c} value) {
             left = mid + 1;
           } else {
             right = mid;
           }
         }
         return right;
       }

       void main() {
         ivec2 coords = getOutputCoords();
         int batch = coords[0];
         int valueIndex = coords[1];

         float value = getValues(batch, valueIndex);

         setOutput(float(findBound(batch, value)));
       }
     `;
  }
}
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function JI(n) {
  const { inputs: e, backend: t, attrs: r } = n, { sortedSequence: s, values: o } = e, { side: i } = r, a = new ZI(s.shape[0], s.shape[1], o.shape[1], i), c = [[s.shape[1]]];
  return t.runWebGLProgram(a, [s, o], "int32", c);
}
const eS = {
  kernelName: Jd,
  backendName: "webgl",
  kernelFunc: JI
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class tS {
  constructor(e, t, r) {
    this.variableNames = ["c", "a", "b"], this.outputShape = t;
    let s, o;
    if (r > 4)
      throw Error(`Where for rank ${r} is not yet supported`);
    if (r === 1)
      o = "resRC", s = "resRC";
    else {
      const a = ["resRC.x", "resRC.y", "resRC.z", "resRC.w"], c = [], l = [];
      for (let u = 0; u < t.length; u++)
        l.push(`${a[u]}`), u < e && c.push(`${a[u]}`);
      s = c.join(), o = l.join();
    }
    const i = K(r);
    this.userCode = `
      void main() {
        ${i} resRC = getOutputCoords();
        float cVal = getC(${s});
        if (cVal >= 1.0) {
          setOutput(getA(${o}));
        } else {
          setOutput(getB(${o}));
        }
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function nS(n) {
  const { inputs: e, backend: t } = n, { condition: r, t: s, e: o } = e, i = new tS(r.shape.length, s.shape, s.shape.length);
  return t.runWebGLProgram(i, [r, s, o], dt(s.dtype, o.dtype));
}
const rS = {
  kernelName: eh,
  backendName: "webgl",
  kernelFunc: nS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const sS = `
  // Stable and Attracting Fixed Point (0, 1) for Normalized Weights.
  // see: https://arxiv.org/abs/1706.02515
  float scaleAlpha = ${ec};
  float scale = ${tc};
  return (x >= 0.0) ? scale * x : scaleAlpha * (exp(x) - 1.0);
`, oS = H({ opSnippet: sS }), iS = {
  kernelName: th,
  backendName: "webgl",
  kernelFunc: oS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const aS = Dn + `
  return 1.0 / (1.0 + exp(-1.0 * x));
`, cS = `
  vec4 result = 1.0 / (1.0 + exp(-1.0 * x));
  bvec4 isNaN = isnan(x);

  result.r = isNaN.r ? x.r : result.r;
  result.g = isNaN.g ? x.g : result.g;
  result.b = isNaN.b ? x.b : result.b;
  result.a = isNaN.a ? x.a : result.a;

  return result;
`, lS = H({
  opSnippet: aS,
  packedOpSnippet: cS,
  cpuKernelImpl: cw
}), uS = {
  kernelName: Xi,
  backendName: "webgl",
  kernelFunc: lS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const dS = `
  if (isnan(x)) { return 0.0; }
  return sign(x);
`, hS = H({ opSnippet: dS }), fS = {
  kernelName: oh,
  backendName: "webgl",
  kernelFunc: hS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const pS = Dn + `
  return sin(x);
`, mS = `
  vec4 result = sin(x);
  bvec4 isNaN = isnan(x);
  ${en}
  return result;
`, gS = H({ opSnippet: pS, packedOpSnippet: mS }), xS = {
  kernelName: rh,
  backendName: "webgl",
  kernelFunc: gS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const wS = `
  float e2x = exp(x);
  return (e2x - 1.0 / e2x) / 2.0;
`, CS = H({ opSnippet: wS }), bS = {
  kernelName: sh,
  backendName: "webgl",
  kernelFunc: CS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const yS = `
  float epsilon = 1.1920928955078125e-7;
  float threshold = log(epsilon) + 2.0;

  bool too_large = x > -threshold;
  bool too_small = x < threshold;

  float result;
  float exp_x = exp(x);

  if (too_large){
    result = x;
  }
  else if (too_small){
    result = exp_x;
  }
  else{
    result = log(exp_x + 1.0);
  }
  return result;
`, $S = H({ opSnippet: yS }), vS = {
  kernelName: ih,
  backendName: "webgl",
  kernelFunc: $S
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const IS = (n) => {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { blockShape: o, paddings: i } = r;
  O(s.shape.length <= 4, () => "spaceToBatchND for rank > 4 with a WebGL backend not implemented yet");
  const a = o.reduce((x, y) => x * y), c = [[0, 0]];
  c.push(...i);
  for (let x = 1 + o.length; x < s.shape.length; ++x)
    c.push([0, 0]);
  const l = [], u = Cl({
    inputs: { x: s },
    backend: t,
    attrs: { paddings: c, constantValue: 0 }
  }), d = Zs(u.shape, o, a, !1), h = Js(d.length, o.length, !1), f = eo(u.shape, o, a, !1), m = D({ inputs: { x: u }, backend: t, attrs: { shape: d } }), C = Ie({
    inputs: { x: m },
    backend: t,
    attrs: { perm: h }
  }), w = D({ inputs: { x: C }, backend: t, attrs: { shape: f } });
  return l.push(u), l.push(m), l.push(C), l.forEach((x) => t.disposeIntermediateTensorInfo(x)), w;
}, SS = {
  kernelName: ah,
  backendName: "webgl",
  kernelFunc: IS
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function ES(n) {
  const { inputs: e, backend: t } = n, { indices: r, values: s, denseShape: o, defaultValue: i } = e;
  if (o.shape.length !== 1)
    throw new Error(`Dense shape must be a vector, saw:
         ${o.shape}`);
  if (r.shape.length !== 2)
    throw new Error(`Indices must be a matrix, saw:
         ${r.shape}`);
  if (s.shape.length !== 1)
    throw new Error(`Values must be a vector, saw:
         ${s.shape}`);
  if (i.shape.length !== 0)
    throw new Error(`Default value must be a scalar, saw:
        ${i.shape}`);
  const a = t.readSync(r.dataId), c = t.readSync(s.dataId), l = t.readSync(o.dataId), u = t.readSync(i.dataId)[0], [d, h, f, m, C] = uw(a, r.shape, r.dtype, c, s.dtype, l, u);
  return [
    t.makeTensorInfo(h, r.dtype, d),
    t.makeTensorInfo([h[0]], s.dtype, f),
    t.makeTensorInfo([m.length], "bool", new Uint8Array(m.map((w) => Number(w)))),
    t.makeTensorInfo([C.length], r.dtype, new Int32Array(C))
  ];
}
const RS = {
  kernelName: uh,
  backendName: "webgl",
  kernelFunc: ES
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function TS(n) {
  const { inputs: e, backend: t } = n, { inputIndices: r, inputShape: s, newShape: o } = e;
  if (r.shape.length !== 2)
    throw new Error(`Input indices should be a matrix but received shape ${r.shape}`);
  if (s.shape.length !== 1)
    throw new Error(`Input shape should be a vector but received shape ${s.shape}`);
  if (o.shape.length !== 1)
    throw new Error(`Target shape should be a vector but received shape ${o.shape}`);
  const i = Array.from(t.readSync(s.dataId)), a = t.readSync(r.dataId), c = Array.from(t.readSync(o.dataId)), [l, u, d] = dw(a, r.shape, r.dtype, i, c);
  return [
    t.makeTensorInfo(u, r.dtype, l),
    t.makeTensorInfo([d.length], o.dtype, new Int32Array(d))
  ];
}
const NS = {
  kernelName: dh,
  backendName: "webgl",
  kernelFunc: TS
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function kS(n) {
  const { inputs: e, backend: t } = n, { data: r, indices: s, segmentIds: o } = e;
  if (r.shape.length < 1)
    throw new Error("Data should be at least 1 dimensional but received scalar");
  if (s.shape.length !== 1)
    throw new Error(`Indices should be a vector but received shape
              ${s.shape}`);
  if (o.shape.length !== 1)
    throw new Error(`Segment ids should be a vector but received shape
              ${o.shape}`);
  const i = t.readSync(r.dataId), a = t.readSync(s.dataId), c = t.readSync(o.dataId), [l, u] = zc(i, r.shape, r.dtype, a, c, !0);
  return t.makeTensorInfo(u, r.dtype, l);
}
const AS = {
  kernelName: hh,
  backendName: "webgl",
  kernelFunc: kS
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function FS(n) {
  const { inputs: e, backend: t } = n, { data: r, indices: s, segmentIds: o } = e;
  if (r.shape.length < 1)
    throw new Error("Data should be at least 1 dimensional but received scalar");
  if (s.shape.length !== 1)
    throw new Error(`Indices should be a vector but received shape
             ${s.shape}`);
  if (o.shape.length !== 1)
    throw new Error(`Segment ids should be a vector but received shape
             ${o.shape}`);
  const i = t.readSync(r.dataId), a = t.readSync(s.dataId), c = t.readSync(o.dataId), [l, u] = zc(i, r.shape, r.dtype, a, c);
  return t.makeTensorInfo(u, r.dtype, l);
}
const DS = {
  kernelName: fh,
  backendName: "webgl",
  kernelFunc: FS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function OS(n) {
  const { inputs: e, backend: t, attrs: r } = n, { sparseIndices: s, sparseValues: o, defaultValue: i } = e, { outputShape: a } = r, { sliceRank: c, numUpdates: l, sliceSize: u, strides: d, outputSize: h } = Lr(o, s, a), f = !1;
  if (o.dtype === "string") {
    const x = t.bufferSync(s), y = t.bufferSync(o), v = xn(t.readSync(i.dataId)[0]), I = aw(x, y, a, h, u, l, c, d, v, f);
    return t.makeTensorInfo(a, I.dtype, I.values);
  }
  const m = new lo(l, c, s.shape.length, o.shape.length, d, [h, 1], f), C = t.runWebGLProgram(m, [o, s, i], o.dtype), w = D({ inputs: { x: C }, backend: t, attrs: { shape: a } });
  return t.disposeIntermediateTensorInfo(C), w;
}
const PS = {
  kernelName: ph,
  backendName: "webgl",
  kernelFunc: OS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function _S(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { numOrSizeSplits: o, axis: i } = r, a = Re(i, s.shape)[0], c = fc(s, o, a), l = s.shape.length, u = new Array(l).fill(0), d = s.shape.slice();
  return c.map((h) => {
    const f = [...d];
    f[a] = h;
    const m = On({ inputs: { x: s }, backend: t, attrs: { begin: u, size: f } });
    return u[a] += h, m;
  });
}
const BS = {
  kernelName: ch,
  backendName: "webgl",
  kernelFunc: _S
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const Ci = "return sqrt(x);", LS = H({ opSnippet: Ci, packedOpSnippet: Ci, cpuKernelImpl: hw }), MS = {
  kernelName: ji,
  backendName: "webgl",
  kernelFunc: LS
};
/**
 * @license
 * Copyright 2019 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const US = "return x * x;", VS = H({ opSnippet: US }), WS = {
  kernelName: gh,
  backendName: "webgl",
  kernelFunc: VS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const bi = "return (a - b) * (a - b);", GS = we({ opSnippet: bi, packedOpSnippet: bi }), zS = {
  kernelName: mh,
  backendName: "webgl",
  kernelFunc: GS
};
/**
 * @license
 * Copyright 2023 Google LLC.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function HS(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e;
  if (s.dtype !== "string")
    throw new Error("Input must be of datatype string");
  const o = t.readSync(s.dataId), i = bn(o), a = fw(i, "string", r);
  return t.makeTensorInfo(s.shape, "string", a);
}
const XS = {
  kernelName: xh,
  backendName: "webgl",
  kernelFunc: HS
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function jS({ inputs: n, attrs: e, backend: t }) {
  const { x: r } = n, s = je + `
    return x > 0.0 ? 1.0 : float(${e.alpha});
  `, o = new ct(r.shape, s);
  return t.runWebGLProgram(o, [r], r.dtype);
}
const qS = {
  kernelName: Zi,
  backendName: "webgl",
  kernelFunc: jS
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class KS {
  constructor(e, t, r) {
    this.variableNames = ["x"], this.outputShape = r;
    const s = r.length, o = K(r.length), i = K(r.length);
    let a = "";
    if (s === 1)
      a = "coords * strides + begin";
    else {
      let c = 0;
      a = r.map((l, u) => (c++, r.length === 1 ? `coords * strides[${u}] + begin[${u}]` : `coords[${c - 1}] * strides[${u}] + begin[${u}]`)).join(",");
    }
    this.userCode = `
      ${o} begin = ${o}(${e});
      ${o} strides = ${o}(${t});

      void main() {
        ${i} coords = getOutputCoords();
        setOutput(getX(${a}));
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function YS(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { begin: o, end: i, strides: a, beginMask: c, endMask: l, ellipsisMask: u, newAxisMask: d, shrinkAxisMask: h } = r, { finalShapeSparse: f, finalShape: m, isIdentity: C, sliceDim0: w, isSimpleSlice: x, begin: y, end: v, strides: I } = Ha(s.shape, o, i, a, c, l, u, d, h);
  let T;
  if (C)
    T = D({ inputs: { x: s }, backend: t, attrs: { shape: m } });
  else if (w || x) {
    O(s.shape.length >= 1, () => `Input must have rank at least 1, got: ${s.shape.length}`);
    const F = Pa(y, v, I), k = On({ inputs: { x: s }, backend: t, attrs: { begin: y, size: F } });
    T = D({ inputs: { x: k }, backend: t, attrs: { shape: m } }), t.disposeIntermediateTensorInfo(k);
  } else if (t.shouldExecuteOnCPU([s])) {
    const k = t.readSync(s.dataId), U = xe(s.shape, s.dtype, k), V = pw(f, U, I, y);
    T = t.makeTensorInfo(m, s.dtype, V.values);
  } else {
    const k = new KS(y, I, f);
    T = t.runWebGLProgram(k, [s], s.dtype);
  }
  const A = D({ inputs: { x: T }, backend: t, attrs: { shape: m } });
  return t.disposeIntermediateTensorInfo(T), A;
}
const QS = {
  kernelName: wh,
  backendName: "webgl",
  kernelFunc: YS
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function ZS(n) {
  const { inputs: e, backend: t, attrs: r } = n, { separator: s, nGramWidths: o, leftPad: i, rightPad: a, padWidth: c, preserveShortSequences: l } = r, { data: u, dataSplits: d } = e, h = t.readSync(u.dataId), f = t.readSync(d.dataId), [m, C] = mw(h, f, s, o, i, a, c, l);
  return [
    t.makeTensorInfo([m.length], "string", m),
    t.makeTensorInfo(d.shape, "int32", C)
  ];
}
const JS = {
  kernelName: Ch,
  backendName: "webgl",
  kernelFunc: ZS
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function eE(n) {
  const { inputs: e, backend: t, attrs: r } = n, { skipEmpty: s } = r, { input: o, delimiter: i } = e;
  if (o.dtype !== "string")
    throw new Error("Input must be of datatype string");
  if (o.shape.length !== 1)
    throw new Error(`Input must be a vector, got shape: ${o.shape}`);
  if (i.shape.length !== 0)
    throw new Error(`Delimiter must be a scalar, got shape: ${i.shape}`);
  const a = t.readSync(o.dataId), c = t.readSync(i.dataId)[0], [l, u, d] = gw(a, c, s), h = u.length;
  return [
    t.makeTensorInfo([h, 2], "int32", l),
    t.makeTensorInfo([h], "string", u),
    t.makeTensorInfo([2], "int32", new Int32Array(d))
  ];
}
const tE = {
  kernelName: bh,
  backendName: "webgl",
  kernelFunc: eE
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function nE(n) {
  const { inputs: e, backend: t, attrs: r } = n, { numBuckets: s } = r, { input: o } = e;
  if (o.dtype !== "string")
    throw new Error("Input must be of datatype string");
  if (s <= 0)
    throw new Error("Number of buckets must be at least 1");
  const i = t.readSync(o.dataId), a = xw(i, s);
  return t.makeTensorInfo(o.shape, "int32", a);
}
const rE = {
  kernelName: yh,
  backendName: "webgl",
  kernelFunc: nE
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const sE = "return tan(x);", oE = H({ opSnippet: sE }), iE = {
  kernelName: $h,
  backendName: "webgl",
  kernelFunc: oE
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const aE = `
  float e2x = exp(-2.0 * abs(x));
  return sign(x) * (1.0 - e2x) / (1.0 + e2x);
`, cE = H({ opSnippet: aE }), lE = {
  kernelName: vh,
  backendName: "webgl",
  kernelFunc: cE
};
/**
 * @license
 * Copyright 2022 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function uE(n) {
  const { inputs: e, backend: t, attrs: r } = n, { tensor: s, indices: o, updates: i } = e, { sliceRank: a, numUpdates: c, sliceSize: l, strides: u, outputSize: d } = Lr(i, o, s.shape), h = [d / l, l];
  if (d === 0)
    return t.makeTensorInfo(s.shape, o.dtype);
  const f = D({ inputs: { x: o }, backend: t, attrs: { shape: [c, a] } }), m = D({ inputs: { x: i }, backend: t, attrs: { shape: [c, l] } }), C = D({ inputs: { x: s }, backend: t, attrs: { shape: h } }), w = new lo(c, a, f.shape.length, m.shape.length, u, h, !1, !0), x = t.runWebGLProgram(w, [m, f, C], C.dtype), y = D({ inputs: { x }, backend: t, attrs: { shape: s.shape } });
  return t.disposeIntermediateTensorInfo(f), t.disposeIntermediateTensorInfo(m), t.disposeIntermediateTensorInfo(C), t.disposeIntermediateTensorInfo(x), y;
}
const dE = {
  kernelName: Zd,
  backendName: "webgl",
  kernelFunc: uE
};
/**
 * @license
 * Copyright 2017 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class hE {
  constructor(e, t) {
    this.variableNames = ["A"];
    const r = new Array(e.length);
    for (let i = 0; i < r.length; i++)
      r[i] = e[i] * t[i];
    this.outputShape = r, this.rank = r.length;
    const s = K(this.rank), o = fE(e);
    this.userCode = `
      void main() {
        ${s} resRC = getOutputCoords();
        setOutput(getA(${o}));
      }
    `;
  }
}
function fE(n) {
  const e = n.length;
  if (e > 5)
    throw Error(`Tile for rank ${e} is not yet supported`);
  if (e === 1)
    return `imod(resRC, ${n[0]})`;
  const t = ["resRC.x", "resRC.y", "resRC.z", "resRC.w", "resRC.u"], r = [];
  for (let s = 0; s < n.length; s++)
    r.push(`imod(${t[s]}, ${n[s]})`);
  return r.join();
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function yl(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { reps: o } = r;
  if (s.dtype === "string" || s.shape.length > 5) {
    const c = t.readSync(s.dataId), l = s.dtype === "string" ? c.map((h) => xn(h)) : c, u = xe(s.shape, s.dtype, l), d = Cw(u, o);
    return t.makeTensorInfo(d.shape, d.dtype, d.values);
  }
  const i = new hE(s.shape, o);
  return t.runWebGLProgram(i, [s], s.dtype);
}
const pE = {
  kernelName: Yi,
  backendName: "webgl",
  kernelFunc: yl
};
class mE {
  /**
   * @param shape desired output shape (can be larger than input shape, output
   *                                    will be padded with -Infinity)
   */
  constructor(e) {
    this.variableNames = ["x", "indices"], this.customUniforms = [
      { name: "n", type: "int" },
      { name: "firstPass", type: "int" },
      { name: "negativeInf", type: "float" },
      { name: "dir", type: "int" },
      { name: "inc", type: "int" }
    ], this.outputShape = e, this.userCode = `
       void main() {
         ivec2 coords = getOutputCoords();
         int batch = coords[0];
         int elemIdx = coords[1];

         // We compare elements pair-wise within a group of size 2 * inc.
         // The comparing rule for each group alternates between ascending
         // and descending. Within each group, we compare each pair at
         // positions i and i+inc. To decide whether an element at position i
         // is x0 or x1, we mod it by 2 * inc, if the result is smaller than
         // inc, it is in the first half of the group, we denote it as x0,
         // otherwise we denote it as x1.
         // For example, as shown in the Bitonic top K paper referenced above,
         // Figure5(a) shows that element[1] is in the
         // second half of the group when group size is 2, but it is in the
         // first half of the group when group size is 4.

         bool isFirstInPair = imod(elemIdx, 2 * inc) < inc;
         int i = isFirstInPair ? elemIdx : elemIdx - inc;

         int i0 = firstPass == 1 ? i : int(getIndices(batch, i));
         int i1 = firstPass == 1 ? i + inc : int(getIndices(batch, i + inc));
         float x0 = i0 < n ? getX(batch, i0) : negativeInf;
         float x1 = i1 < n ? getX(batch, i1) : negativeInf;

         // Denotes which direction indices are in (ascending or descending).
         bool reverse = imod(elemIdx, 2 * dir) >= dir;
         bool isGreater = x0 > x1 || (x0 == x1 && i1 > i0);
         if (reverse == isGreater) { // Elements in opposite order of direction
           int iTemp = i0;
           i0 = i1;
           i1 = iTemp;
         }
         if (isFirstInPair) {
            setOutput(float(i0));
         } else {
            setOutput(float(i1));
         }
       }
     `;
  }
}
class gE {
  /**
   * @param shape desired output shape (must be half of the input size)
   */
  constructor(e) {
    this.variableNames = ["x", "indices"], this.customUniforms = [
      { name: "n", type: "int" },
      { name: "firstPass", type: "int" },
      { name: "k", type: "int" }
    ], this.outputShape = e, this.userCode = `
    void main() {
         // Takes max of indices (0, k), (1, k + 1), (2, k + 2) ...
         ivec2 coords = getOutputCoords();
         int batch = coords[0];
         int elemIdx = coords[1];

         // The output size is half of the previous size.
         // If the previous sequence is | | | | _ _ _ _  | | | |  _ _ _ _ (k=4),
         // we only need to output the indices at positions |, the indices at
         // positions _ can be thrown away, see Figure5(b) After Phase 2
         // (Merge phase) in the Bitonic Top K paper referenced above.
         // For example, the paper shows we only need to output the orange bars.
         // The output sequence should look like this | | | | | | | |.
         // Because the sequence is halved, to map the output index back
         // to the previous sequence to find the corresponding value,
         // we need to double the index. When we double the index,
         // we basically interpolate a position, so 2i looks like
         // | _ | _ | _ | _ | _ | _ | _. We move the | to the first k position
         // of each 2k positions by - elemIdx % k. E.g. for output at
         // index 4,5,6,7, we want to get the corresponding element at
         // original index 8,9,10,11, for output at index 8,9,10,11,
         // we want to get the corresponding element at original index
         // 16,17,18,19, so on and so forth.

         int i = elemIdx < k ? elemIdx : (elemIdx * 2 - imod(elemIdx, k));
         int i0 = firstPass == 1 ? i : int(getIndices(batch, i));
         int i1 = firstPass == 1 ? i + k : int(getIndices(batch, i + k));

         float x0 = getX(batch, i0);
         float x1 = i1 < n ? getX(batch, i1) : x0;

         setOutput(x0 >= x1 ? float(i0) : float(i1));
       }
     `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function kt(n, e) {
  e !== null && n.disposeIntermediateTensorInfo(e);
}
function yi(n) {
  let e = 1;
  for (; e < n; )
    e *= 2;
  return e;
}
function xE(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s } = e, { k: o, sorted: i } = r, a = E().getNumber("TOPK_LAST_DIM_CPU_HANDOFF_SIZE_THRESHOLD"), c = E().getNumber("TOPK_K_CPU_HANDOFF_THRESHOLD"), l = s.shape, u = l[l.length - 1];
  if (t.shouldExecuteOnCPU([s]) || u < a || o > c) {
    const V = t.readSync(s.dataId), [G, j] = bw(V, l, s.dtype, o, i);
    return [
      t.makeTensorInfo(G.shape, G.dtype, G.values),
      t.makeTensorInfo(j.shape, j.dtype, j.values)
    ];
  }
  if (o === 0)
    return l[l.length - 1] = 0, [
      t.makeTensorInfo(l, s.dtype, []),
      t.makeTensorInfo(l, "int32", [])
    ];
  if (u === 1)
    return [
      s,
      sr({ attrs: { shape: l, dtype: "int32", value: 0 }, backend: t })
    ];
  const d = t.texData.get(s.dataId), h = d !== null && d.isPacked, f = h ? t.unpackTensor(s) : s, C = _(l) / u, w = D({ inputs: { x: f }, attrs: { shape: [C, u] }, backend: t });
  h && kt(t, f);
  const x = yi(o), y = yi(u);
  let v = null;
  const I = () => v === null ? [w, w] : [w, v], T = (V, G, j) => {
    const be = I(), ie = new mE(j), Ne = [[u], [v === null ? 1 : 0], [Number.NEGATIVE_INFINITY], [V], [G]], ke = v;
    v = t.runWebGLProgram(ie, be, "int32", Ne), kt(t, ke);
  };
  for (let V = 1; V < x; V *= 2) {
    const G = V * 2;
    for (let j = V; j >= 1; j /= 2)
      T(G, j, [C, y]);
  }
  for (let V = y; V > x; V /= 2) {
    const G = I(), j = new gE([C, V / 2]), ie = [[u], [v === null ? 1 : 0], [x]], ce = v;
    v = t.runWebGLProgram(j, G, "int32", ie), kt(t, ce);
    const Ne = x / 2, ke = Ne * 2;
    for (let le = Ne; le >= 1; le /= 2)
      T(ke, le, v.shape);
  }
  let A = v;
  v = On({ inputs: { x: v }, backend: t, attrs: { begin: 0, size: [C, o] } }), kt(t, A);
  let F = fl({ inputs: { x: w, indices: v }, backend: t, attrs: { axis: 1, batchDims: 1 } });
  kt(t, w);
  const k = l.slice(0, -1);
  k.push(o), A = v, v = D({ inputs: { x: v }, attrs: { shape: k }, backend: t }), kt(t, A);
  const U = F;
  return F = D({ inputs: { x: F }, attrs: { shape: k }, backend: t }), kt(t, U), [F, v];
}
const wE = {
  kernelName: Ih,
  backendName: "webgl",
  kernelFunc: xE
};
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class CE {
  constructor(e, t, r, s, o, i) {
    this.variableNames = ["Image", "Transforms"], this.outputShape = i;
    const a = r === "nearest" ? 1 : 2;
    let c;
    switch (s) {
      case "constant":
        c = 1;
        break;
      case "reflect":
        c = 2;
        break;
      case "wrap":
        c = 3;
        break;
      case "nearest":
        c = 4;
        break;
      default:
        c = 1;
        break;
    }
    this.userCode = `
            float mapCoord(float outCoord, float len) {
              float inCoord = outCoord;
              if(${c} == 2) {
                if (inCoord < 0.0) {
                  if (len <= 1.0) {
                    inCoord = 0.0;
                  } else {
                    float sz2 = 2.0 * len;
                    if (inCoord < sz2) {
                      inCoord = sz2 * float(int(float(-inCoord / sz2))) +
                      inCoord;
                    }
                    inCoord = inCoord < -len ? inCoord + sz2 : -inCoord - 1.0;
                  }
                } else if (inCoord > len - 1.0) {
                  if (len <= 1.0) {
                    inCoord = 0.0;
                  } else {
                    float sz2 = 2.0 * len;
                    inCoord -= sz2 * float(int(float(inCoord / sz2)));
                    if (inCoord >= len) {
                      inCoord = sz2 - inCoord - 1.0;
                    }
                  }
                }
                return clamp(inCoord, 0.0, len - 1.0);
              } else if (${c} == 3) {
                if (inCoord < 0.0) {
                  if (len <= 1.0) {
                    inCoord = 0.0;
                  } else {
                    float sz = len - 1.0;
                    inCoord += len * (float(int(float(-inCoord / sz))) + 1.0);
                  }
                } else if (inCoord > len - 1.0) {
                  if (len <= 1.0) {
                    inCoord = 0.0;
                  } else {
                    float sz = len - 1.0;
                    inCoord -= len * float(int(float(inCoord / sz)));
                  }
                }
                return clamp(inCoord, 0.0, len - 1.0);
              } else if (${c} == 4) {
                return clamp(outCoord, 0.0, len - 1.0);
              } else {
                return outCoord;
              }
            }

            float readWithFillValue(int batch, int coordY, int coordX,
              int channel) {
              float outputValue;
              if (0 <= coordY && coordY < ${e} && 0 <= coordX && coordX < ${t}) {
                  outputValue = getImage(batch, coordY, coordX, channel);
              } else {
                outputValue = float(${o});
              }
              return outputValue;
            }

            void main() {
              ivec4 coords = getOutputCoords();
              float outputValue;
              int batch = coords[0];
              int x = coords[2];
              int y = coords[1];
              int channel = coords[3];
              float xf = float(x);
              float yf = float(y);
              float a1 = getTransforms(batch, 0);
              float a2 = getTransforms(batch, 1);
              float a3 = getTransforms(batch, 2);
              float b1 = getTransforms(batch, 3);
              float b2 = getTransforms(batch, 4);
              float b3 = getTransforms(batch, 5);
              float c1 = getTransforms(batch, 6);
              float c2 = getTransforms(batch, 7);
              float projection = c1 * xf + c2 * yf + 1.0;
              if (projection == 0.0) {
                outputValue = float(${o});
              } else {
                float inX = (a1 * xf + a2 * yf + a3) / projection;
                float inY = (b1 * xf + b2 * yf + b3) / projection;
                float mapX = mapCoord(inX, float(${t}));
                float mapY = mapCoord(inY, float(${e}));

                if (${a} == 1) {
                  int coordY = int(round(mapY));
                  int coordX = int(round(mapX));
                  outputValue = readWithFillValue(batch, coordY, coordX,
                    channel);
                } else {
                  float yFloor = floor(mapY);
                  float xFloor = floor(mapX);
                  float yCeil = yFloor + 1.0;
                  float xCeil = xFloor + 1.0;
                  float valueYFloor = (xCeil - mapX) *
                  readWithFillValue(batch, int(yFloor), int(xFloor), channel) +
                  (mapX - xFloor) *
                  readWithFillValue(batch, int(yFloor), int(xCeil), channel);
                  float valueYCeil = (xCeil - mapX) *
                  readWithFillValue(batch, int(yCeil), int(xFloor), channel) +
                  (mapX - xFloor) *
                  readWithFillValue(batch, int(yCeil), int(xCeil), channel);
                  outputValue = (yCeil - mapY) * valueYFloor +
                  (mapY - yFloor) * valueYCeil;
                }
              }
              setOutput(outputValue);
            }
        `;
  }
}
/**
 * @license
 * Copyright 2021 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function bE(n) {
  const { inputs: e, backend: t, attrs: r } = n, { image: s, transforms: o } = e, { interpolation: i, fillMode: a, fillValue: c, outputShape: l } = r, [u, d, h, f] = s.shape, [m, C] = l ?? [d, h], w = [
    u,
    m,
    C,
    f
  ], x = new CE(d, h, i, a, c, w);
  return t.runWebGLProgram(x, [s, o], "float32");
}
const yE = {
  kernelName: Sh,
  backendName: "webgl",
  kernelFunc: bE
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the License);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function $E(n) {
  const { inputs: e, attrs: t, backend: r } = n, { axis: s } = t, { x: o } = e;
  tr(o, "unique"), console.warn("WARNING: ", "UI might be locked temporarily as data is being downloaded");
  const i = r.readSync(o.dataId), { outputValues: a, outputShape: c, indices: l } = yw(i, s, o.shape, o.dtype);
  return [
    r.makeTensorInfo(c, o.dtype, a),
    r.makeTensorInfo([l.length], "int32", l)
  ];
}
const vE = {
  kernelName: Rh,
  backendName: "webgl",
  kernelFunc: $E
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function IE(n) {
  const { inputs: e, backend: t, attrs: r } = n, { value: s } = e;
  let { axis: o } = r;
  o < 0 && (o += s.shape.length);
  const i = s, a = i.shape.length, c = s.shape[o], l = new Array(a - 1);
  let u = 0;
  for (let C = 0; C < a; C++)
    C !== o && (l[u++] = i.shape[C]);
  const d = [], h = new Array(a).fill(0), f = i.shape.slice();
  f[o] = 1;
  const m = new Array(c);
  for (let C = 0; C < m.length; C++) {
    h[o] = C;
    const w = On({ inputs: { x: i }, backend: t, attrs: { begin: h, size: f } }), x = D({ inputs: { x: w }, backend: t, attrs: { shape: l } });
    m[C] = x, d.push(w);
  }
  return d.forEach((C) => t.disposeIntermediateTensorInfo(C)), m;
}
const SE = {
  kernelName: Th,
  backendName: "webgl",
  kernelFunc: IE
};
/**
 * @license
 * Copyright 2018 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
class EE {
  constructor(e, t) {
    this.variableNames = ["x", "segmentIds"];
    const r = e.windowSize, s = e.batchSize, o = e.inSize, i = e.numSegments, a = i * Math.ceil(o / r);
    this.outputShape = [s, a];
    const c = "0.0", l = "sumValue", u = Math.floor(r / 4) * 4, d = r % 4, h = `
        sumValue += dot(values, segFilter);
    `;
    let f = "";
    o % r > 0 && (f = `
        if (inIdx < 0 || inIdx >= ${o}) {
          return initializationValue;
        }
      `);
    let m = "";
    o % r > 0 && (m = `
        if (inIdx < 0 || inIdx >= ${o}) {
          return -1.0;
        }
      `), this.userCode = `
      const float initializationValue = ${c};

      float getValue(int batch, int inIdx) {
        ${f}
        return getX(batch, inIdx);
      }

      float getSegmentIdAtIndex(int inIdx) {
        ${m}
        return getSegmentIds(inIdx);
      }

      void main() {
        ivec2 coords = getOutputCoords();
        int batch = coords[0];
        int outIdx = coords[1];
        int inOffset = int(floor(float(outIdx) / float(
          ${i})) * float(${r}));
        int currentSeg = int(mod(float(outIdx), float(${i})));

        float sumValue = 0.0;

        for (int i = 0; i < ${u}; i += 4) {
          int inIdx = inOffset + i;
          vec4 values = vec4(
            getValue(batch, inIdx),
            getValue(batch, inIdx + 1),
            getValue(batch, inIdx + 2),
            getValue(batch, inIdx + 3)
          );

          vec4 segFilter = vec4(
            int(getSegmentIdAtIndex(inIdx)) == currentSeg ? 1 : 0,
            int(getSegmentIdAtIndex(inIdx + 1)) == currentSeg ? 1 : 0,
            int(getSegmentIdAtIndex(inIdx + 2)) == currentSeg ? 1 : 0,
            int(getSegmentIdAtIndex(inIdx + 3)) == currentSeg ? 1 : 0
          );

          ${h}
        }

        int inIdx = inOffset + ${u};
        if (${d === 1}) {
          vec4 values = vec4(
            getValue(batch, inIdx),
            initializationValue,
            initializationValue,
            initializationValue
          );

          int inIdxSeg = int(getSegmentIdAtIndex(inIdx));

          vec4 segFilter = vec4(
            int(getSegmentIdAtIndex(inIdx)) == currentSeg ? 1 : 0,
            0,
            0,
            0
          );

          ${h}
        } else if (${d === 2}) {
          vec4 values = vec4(
            getValue(batch, inIdx),
            getValue(batch, inIdx + 1),
            initializationValue,
            initializationValue
          );

          vec4 segFilter = vec4(
            int(getSegmentIdAtIndex(inIdx)) == currentSeg ? 1 : 0,
            int(getSegmentIdAtIndex(inIdx + 1)) == currentSeg ? 1 : 0,
              0,
              0
          );

          ${h}
        } else if (${d === 3}) {
          vec4 values = vec4(
            getValue(batch, inIdx),
            getValue(batch, inIdx + 1),
            getValue(batch, inIdx + 2),
            initializationValue
          );

          vec4 segFilter = vec4(
            int(getSegmentIdAtIndex(inIdx)) == currentSeg ? 1 : 0,
            int(getSegmentIdAtIndex(inIdx + 1)) == currentSeg ? 1 : 0,
            int(getSegmentIdAtIndex(inIdx + 2)) == currentSeg ? 1 : 0,
            0
          );

          ${h}
        }
        setOutput(${l});
      }
    `;
  }
}
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
function RE(n) {
  const { inputs: e, backend: t, attrs: r } = n, { x: s, segmentIds: o } = e, { numSegments: i } = r, a = s.shape.length, c = [];
  let l = 0;
  const u = He([l], a);
  let d = s;
  u != null && (d = Ie({ inputs: { x: s }, backend: t, attrs: { perm: u } }), c.push(d), l = Xe(1, a)[0]);
  const h = Ec(d.shape, l, i), f = _([d.shape[l]]), m = D({ inputs: { x: d }, backend: t, attrs: { shape: [-1, f] } });
  c.push(m);
  const C = Ms(s.dtype), w = (I, T, A, F, k) => {
    const U = I.shape[0], V = I.shape[1], G = Sc(V, k), j = { windowSize: G, inSize: V, batchSize: U, numSegments: k }, be = new EE(j, T), ie = t.compileAndRun(be, [I, A], F);
    if (c.push(ie), ie.shape[1] === k)
      return ie;
    const ce = bl({
      backend: t,
      attrs: { start: 0, stop: k, step: 1, dtype: "float32" }
    }), Ne = yl({
      inputs: { x: ce },
      backend: t,
      attrs: { reps: [V / G] }
    });
    return c.push(ce), c.push(Ne), w(ie, T, Ne, F, k);
  }, x = w(m, "unsortedSegmentSum", o, C, i), y = D({ inputs: { x }, backend: t, attrs: { shape: h } });
  let v = y;
  if (u != null) {
    c.push(y);
    const I = Xs(u);
    v = Ie({ inputs: { x: v }, backend: t, attrs: { perm: I } });
  }
  return c.forEach((I) => t.disposeIntermediateTensorInfo(I)), v;
}
const TE = {
  kernelName: Nh,
  backendName: "webgl",
  kernelFunc: RE
};
/**
 * @license
 * Copyright 2020 Google LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */
const NE = [
  h1,
  p1,
  x1,
  b1,
  $1,
  S1,
  R1,
  N1,
  D1,
  P1,
  L1,
  V1,
  z1,
  q1,
  Q1,
  J1,
  tC,
  oC,
  aC,
  lC,
  fC,
  bC,
  $C,
  EC,
  TC,
  OC,
  _C,
  UC,
  Kw,
  GC,
  qC,
  ZC,
  sb,
  ab,
  lb,
  db,
  fb,
  xb,
  bb,
  vb,
  Sb,
  Rb,
  Nb,
  Fb,
  Ob,
  Lb,
  Ub,
  Gb,
  Xb,
  qb,
  Zb,
  ny,
  iy,
  ly,
  hy,
  fy,
  my,
  xy,
  Cy,
  yy,
  vy,
  Ry,
  ky,
  Dy,
  Py,
  Ly,
  Vy,
  Hy,
  Ky,
  qw,
  Qy,
  XC,
  e$,
  r$,
  i$,
  Qw,
  u$,
  p$,
  g$,
  b$,
  v$,
  R$,
  k$,
  O$,
  L$,
  V$,
  G$,
  j$,
  K$,
  Q$,
  tv,
  rv,
  ov,
  av,
  lv,
  fv,
  xv,
  yv,
  Nv,
  e1,
  Dv,
  _v,
  Mv,
  Wv,
  kC,
  Hv,
  jv,
  Kv,
  Zv,
  nI,
  Jw,
  sI,
  iI,
  cI,
  uI,
  dI,
  AC,
  Sv,
  pI,
  wI,
  $I,
  n1,
  EI,
  NI,
  DI,
  _I,
  UI,
  WI,
  HI,
  qI,
  QI,
  eS,
  rS,
  iS,
  uS,
  fS,
  xS,
  bS,
  wC,
  Rv,
  vS,
  SS,
  RS,
  NS,
  AS,
  DS,
  PS,
  BS,
  MS,
  WS,
  zS,
  XS,
  qS,
  QS,
  JS,
  tE,
  rE,
  Ev,
  l1,
  iE,
  lE,
  dE,
  pE,
  wE,
  yE,
  u1,
  vE,
  SE,
  TE,
  Xv
];
for (const n of NE)
  Bh(n);
export {
  AE as B,
  _r as a,
  FE as d,
  DE as m,
  fn as p,
  PE as r,
  OE as s
};
