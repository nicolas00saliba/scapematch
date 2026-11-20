/*! @sentry/browser (Performance Monitoring) 11.0.0 (3e02c87) | https://github.com/getsentry/sentry-javascript */
var Sentry = (function (exports) {

  exports = window.Sentry || {};

  const GLOBAL_OBJ = globalThis;

  const SDK_VERSION = "11.0.0";

  function getMainCarrier() {
    getSentryCarrier(GLOBAL_OBJ);
    return GLOBAL_OBJ;
  }
  function getSentryCarrier(carrier) {
    const __SENTRY__ = carrier.__SENTRY__ = carrier.__SENTRY__ || {};
    __SENTRY__.version = __SENTRY__.version || SDK_VERSION;
    return __SENTRY__[SDK_VERSION] = __SENTRY__[SDK_VERSION] || {};
  }
  function getGlobalSingleton(name, creator, obj = GLOBAL_OBJ) {
    const __SENTRY__ = obj.__SENTRY__ = obj.__SENTRY__ || {};
    const carrier = __SENTRY__[SDK_VERSION] = __SENTRY__[SDK_VERSION] || {};
    return carrier[name] || (carrier[name] = creator());
  }

  const CONSOLE_LEVELS = [
    "debug",
    "info",
    "warn",
    "error",
    "log",
    "assert",
    "trace"
  ];
  const PREFIX = "Sentry Logger ";
  const originalConsoleMethods = {};
  function consoleSandbox(callback) {
    if (!("console" in GLOBAL_OBJ)) {
      return callback();
    }
    const console = GLOBAL_OBJ.console;
    const wrappedFuncs = {};
    const wrappedLevels = Object.keys(originalConsoleMethods);
    wrappedLevels.forEach((level) => {
      const originalConsoleMethod = originalConsoleMethods[level];
      wrappedFuncs[level] = console[level];
      console[level] = originalConsoleMethod;
    });
    try {
      return callback();
    } finally {
      wrappedLevels.forEach((level) => {
        console[level] = wrappedFuncs[level];
      });
    }
  }
  function enable() {
    _getLoggerSettings().enabled = true;
  }
  function disable() {
    _getLoggerSettings().enabled = false;
  }
  function isEnabled$1() {
    return _getLoggerSettings().enabled;
  }
  function log(...args) {
    _maybeLog("log", ...args);
  }
  function warn(...args) {
    _maybeLog("warn", ...args);
  }
  function error(...args) {
    _maybeLog("error", ...args);
  }
  function _maybeLog(level, ...args) {
    if (isEnabled$1()) {
      consoleSandbox(() => {
        GLOBAL_OBJ.console[level](`${PREFIX}[${level}]:`, ...args);
      });
    }
  }
  function _getLoggerSettings() {
    return getGlobalSingleton("loggerSettings", () => ({ enabled: false }));
  }
  const debug = {
    /** Enable logging. */
    enable,
    /** Disable logging. */
    disable,
    /** Check if logging is enabled. */
    isEnabled: isEnabled$1,
    /** Log a message. */
    log,
    /** Log a warning. */
    warn,
    /** Log an error. */
    error
  };

  const STACKTRACE_FRAME_LIMIT = 50;
  const UNKNOWN_FUNCTION = "?";
  const WEBPACK_ERROR_REGEXP = /\(error: (.*)\)/;
  const STRIP_FRAME_REGEXP = /captureMessage|captureException/;
  function createStackParser(...parsers) {
    const sortedParsers = parsers.sort((a, b) => a[0] - b[0]).map((p) => p[1]);
    return (stack, skipFirstLines = 0, framesToPop = 0) => {
      const frames = [];
      const lines = stack.split("\n");
      for (let i = skipFirstLines; i < lines.length; i++) {
        let line = lines[i];
        if (line.length > 1024) {
          line = line.slice(0, 1024);
        }
        const cleanedLine = WEBPACK_ERROR_REGEXP.test(line) ? line.replace(WEBPACK_ERROR_REGEXP, "$1") : line;
        if (cleanedLine.includes("Error: ")) {
          continue;
        }
        for (const parser of sortedParsers) {
          const frame = parser(cleanedLine);
          if (frame) {
            frames.push(frame);
            break;
          }
        }
        if (frames.length >= STACKTRACE_FRAME_LIMIT + framesToPop) {
          break;
        }
      }
      return stripSentryFramesAndReverse(frames.slice(framesToPop));
    };
  }
  function stackParserFromStackParserOptions(stackParser) {
    if (Array.isArray(stackParser)) {
      return createStackParser(...stackParser);
    }
    return stackParser;
  }
  function stripSentryFramesAndReverse(stack) {
    if (!stack.length) {
      return [];
    }
    const localStack = Array.from(stack);
    if (/sentryWrapped/.test(getLastStackFrame(localStack).function || "")) {
      localStack.pop();
    }
    localStack.reverse();
    if (STRIP_FRAME_REGEXP.test(getLastStackFrame(localStack).function || "")) {
      localStack.pop();
      if (STRIP_FRAME_REGEXP.test(getLastStackFrame(localStack).function || "")) {
        localStack.pop();
      }
    }
    return localStack.slice(0, STACKTRACE_FRAME_LIMIT).map((frame) => ({
      ...frame,
      filename: frame.filename || getLastStackFrame(localStack).filename,
      function: frame.function || UNKNOWN_FUNCTION
    }));
  }
  function getLastStackFrame(arr) {
    return arr[arr.length - 1] || {};
  }
  const defaultFunctionName = "<anonymous>";
  function getFunctionName(fn) {
    try {
      if (!fn || typeof fn !== "function") {
        return defaultFunctionName;
      }
      return fn.name || defaultFunctionName;
    } catch {
      return defaultFunctionName;
    }
  }
  function getFramesFromEvent(event) {
    const exception = event.exception;
    if (exception) {
      const frames = [];
      try {
        exception.values.forEach((value) => {
          if (value.stacktrace.frames) {
            frames.push(...value.stacktrace.frames);
          }
        });
        return frames;
      } catch {
        return void 0;
      }
    }
    return void 0;
  }

  const handlers$1 = {};
  const instrumented$1 = {};
  function addHandler$1(type, handler) {
    handlers$1[type] = handlers$1[type] || [];
    handlers$1[type].push(handler);
    return () => {
      const typeHandlers = handlers$1[type];
      if (typeHandlers) {
        const index = typeHandlers.indexOf(handler);
        if (index !== -1) {
          typeHandlers.splice(index, 1);
        }
      }
    };
  }
  function maybeInstrument(type, instrumentFn) {
    if (!instrumented$1[type]) {
      instrumented$1[type] = true;
      try {
        instrumentFn();
      } catch (e) {
        debug.error(`Error while instrumenting ${type}`, e);
      }
    }
  }
  function triggerHandlers$1(type, data) {
    const typeHandlers = type && handlers$1[type];
    if (!typeHandlers) {
      return;
    }
    for (const handler of typeHandlers) {
      try {
        handler(data);
      } catch (e) {
        debug.error(
          `Error while triggering instrumentation handler.
Type: ${type}
Name: ${getFunctionName(handler)}
Error:`,
          e
        );
      }
    }
  }

  let _oldOnErrorHandler = null;
  function addGlobalErrorInstrumentationHandler(handler) {
    const type = "error";
    addHandler$1(type, handler);
    maybeInstrument(type, instrumentError);
  }
  function instrumentError() {
    _oldOnErrorHandler = GLOBAL_OBJ.onerror;
    GLOBAL_OBJ.onerror = function(msg, url, line, column, error) {
      const handlerData = {
        column,
        error,
        line,
        msg,
        url
      };
      triggerHandlers$1("error", handlerData);
      if (_oldOnErrorHandler) {
        return _oldOnErrorHandler.apply(this, arguments);
      }
      return false;
    };
    GLOBAL_OBJ.onerror.__SENTRY_INSTRUMENTED__ = true;
  }

  let _oldOnUnhandledRejectionHandler = null;
  function addGlobalUnhandledRejectionInstrumentationHandler(handler) {
    const type = "unhandledrejection";
    addHandler$1(type, handler);
    maybeInstrument(type, instrumentUnhandledRejection);
  }
  function instrumentUnhandledRejection() {
    _oldOnUnhandledRejectionHandler = GLOBAL_OBJ.onunhandledrejection;
    GLOBAL_OBJ.onunhandledrejection = function(e) {
      const handlerData = e;
      triggerHandlers$1("unhandledrejection", handlerData);
      if (_oldOnUnhandledRejectionHandler) {
        return _oldOnUnhandledRejectionHandler.apply(this, arguments);
      }
      return true;
    };
    GLOBAL_OBJ.onunhandledrejection.__SENTRY_INSTRUMENTED__ = true;
  }

  const objectToString = Object.prototype.toString;
  function isError(wat) {
    switch (objectToString.call(wat)) {
      case "[object Error]":
      case "[object Exception]":
      case "[object DOMException]":
      case "[object WebAssembly.Exception]":
        return true;
      default:
        return isInstanceOf(wat, Error);
    }
  }
  function isBuiltin(wat, className) {
    return objectToString.call(wat) === `[object ${className}]`;
  }
  function isErrorEvent$1(wat) {
    return isBuiltin(wat, "ErrorEvent");
  }
  function isDOMError(wat) {
    return isBuiltin(wat, "DOMError");
  }
  function isDOMException(wat) {
    return isBuiltin(wat, "DOMException");
  }
  function isString(wat) {
    return isBuiltin(wat, "String");
  }
  function isParameterizedString(wat) {
    return typeof wat === "object" && wat !== null && "__sentry_template_string__" in wat && "__sentry_template_values__" in wat;
  }
  function isPrimitive(wat) {
    return wat === null || isParameterizedString(wat) || typeof wat !== "object" && typeof wat !== "function";
  }
  function isPlainObject(wat) {
    return isBuiltin(wat, "Object");
  }
  function isObjectLike(wat) {
    return typeof wat === "object" && wat !== null;
  }
  function isEvent(wat) {
    return typeof Event !== "undefined" && isInstanceOf(wat, Event);
  }
  function isRegExp(wat) {
    return isBuiltin(wat, "RegExp");
  }
  function isThenable(wat) {
    return Boolean(wat?.then && typeof wat.then === "function");
  }
  function isInstanceOf(wat, base) {
    try {
      return wat instanceof base;
    } catch {
      return false;
    }
  }
  function isRequest(request) {
    return typeof Request !== "undefined" && isInstanceOf(request, Request);
  }

  function fill(source, name, replacementFactory) {
    if (!(name in source)) {
      return;
    }
    const original = source[name];
    if (typeof original !== "function") {
      return;
    }
    const wrapped = replacementFactory(original);
    if (typeof wrapped === "function") {
      markFunctionWrapped(wrapped, original);
    }
    try {
      source[name] = wrapped;
    } catch {
      debug.log(`Failed to replace method "${name}" in object`, source);
    }
  }
  function addNonEnumerableProperty(obj, name, value) {
    try {
      Object.defineProperty(obj, name, {
        // enumerable: false, // the default, so we can save on bundle size by not explicitly setting it
        value,
        writable: true,
        configurable: true
      });
    } catch {
      debug.log(`Failed to add non-enumerable property "${String(name)}" to object`, obj);
    }
  }
  function markFunctionWrapped(wrapped, original) {
    try {
      const proto = original.prototype || {};
      wrapped.prototype = original.prototype = proto;
      addNonEnumerableProperty(wrapped, "__sentry_original__", original);
    } catch {
    }
  }
  function getOriginalFunction(func) {
    return func.__sentry_original__;
  }
  function convertToPlainObject(value) {
    if (isError(value)) {
      return {
        message: value.message,
        name: value.name,
        stack: value.stack,
        ...getOwnProperties(value)
      };
    }
    if (isEvent(value)) {
      const { type, target, currentTarget, detail } = value;
      return {
        type,
        target,
        currentTarget,
        ...detail ? { detail } : {},
        ...getOwnProperties(value)
      };
    }
    return value;
  }
  function getOwnProperties(obj) {
    if (isObjectLike(obj)) {
      return Object.fromEntries(Object.entries(obj));
    }
    return {};
  }
  function extractExceptionKeysForMessage(exception) {
    const keys = Object.keys(convertToPlainObject(exception));
    keys.sort();
    return !keys[0] ? "[object has no keys]" : keys.join(", ");
  }

  let RESOLVED_RUNNER;
  function withRandomSafeContext(cb) {
    if (RESOLVED_RUNNER !== void 0) {
      return RESOLVED_RUNNER ? RESOLVED_RUNNER(cb) : cb();
    }
    const sym = /* @__PURE__ */ Symbol.for("__SENTRY_SAFE_RANDOM_ID_WRAPPER__");
    const globalWithSymbol = GLOBAL_OBJ;
    if (sym in globalWithSymbol && typeof globalWithSymbol[sym] === "function") {
      RESOLVED_RUNNER = globalWithSymbol[sym];
      return RESOLVED_RUNNER(cb);
    }
    RESOLVED_RUNNER = null;
    return cb();
  }
  function safeMathRandom() {
    return withRandomSafeContext(() => Math.random());
  }
  function safeDateNow() {
    return withRandomSafeContext(() => Date.now());
  }

  const SENTRY_SKIP_NORMALIZATION = /* @__PURE__ */ Symbol.for("sentry.skipNormalization");
  const SENTRY_OVERRIDE_NORMALIZATION_DEPTH = /* @__PURE__ */ Symbol.for("sentry.overrideNormalizationDepth");
  function hasSkipNormalizationHint(value) {
    return Boolean(value[SENTRY_SKIP_NORMALIZATION]);
  }
  function getNormalizationDepthOverrideHint(value) {
    const v = value[SENTRY_OVERRIDE_NORMALIZATION_DEPTH];
    return typeof v === "number" ? v : void 0;
  }

  let stringifier;
  function setNormalizeStringifier(newStringifier) {
    stringifier = newStringifier;
  }
  function normalize(input, depth = 100, maxProperties = Infinity) {
    try {
      return visit("", input, depth, maxProperties);
    } catch (err) {
      return { ERROR: `**non-serializable** (${err})` };
    }
  }
  function normalizeToSize(object, depth = 3, maxSize = 100 * 1024) {
    const normalized = normalize(object, depth);
    if (jsonSize(normalized) > maxSize) {
      return normalizeToSize(object, depth - 1, maxSize);
    }
    return normalized;
  }
  function visit(key, value, depth = Infinity, maxProperties = Infinity, memo = memoBuilder()) {
    const [memoize, unmemoize] = memo;
    if (value == null || // this matches null and undefined -> eqeq not eqeqeq
    ["boolean", "string"].includes(typeof value) || typeof value === "number" && Number.isFinite(value)) {
      return value;
    }
    const stringified = stringifyValue(key, value);
    if (!stringified.startsWith("[object ")) {
      return stringified;
    }
    if (hasSkipNormalizationHint(value)) {
      return value;
    }
    const overrideDepth = getNormalizationDepthOverrideHint(value);
    const remainingDepth = overrideDepth !== void 0 ? overrideDepth : depth;
    if (remainingDepth === 0) {
      return stringified.replace("object ", "");
    }
    if (memoize(value)) {
      return "[Circular ~]";
    }
    const valueWithToJSON = value;
    if (valueWithToJSON && typeof valueWithToJSON.toJSON === "function") {
      try {
        const jsonValue = valueWithToJSON.toJSON();
        return visit("", jsonValue, remainingDepth - 1, maxProperties, memo);
      } catch {
      }
    }
    const normalized = Array.isArray(value) ? [] : {};
    let numAdded = 0;
    const visitable = convertToPlainObject(value);
    for (const visitKey in visitable) {
      if (!Object.prototype.hasOwnProperty.call(visitable, visitKey)) {
        continue;
      }
      if (numAdded >= maxProperties) {
        normalized[visitKey] = "[MaxProperties ~]";
        break;
      }
      const visitValue = visitable[visitKey];
      normalized[visitKey] = visit(visitKey, visitValue, remainingDepth - 1, maxProperties, memo);
      numAdded++;
    }
    unmemoize(value);
    return normalized;
  }
  function stringifyValue(key, value) {
    try {
      if (stringifier) {
        const stringified = stringifier(value);
        if (stringified) {
          return stringified;
        }
      }
      if (typeof global !== "undefined" && value === global) {
        return "[Global]";
      }
      if (typeof value === "number" && !Number.isFinite(value)) {
        return `[${value}]`;
      }
      if (typeof value === "function") {
        return `[Function: ${getFunctionName(value)}]`;
      }
      if (typeof value === "symbol") {
        return `[${String(value)}]`;
      }
      if (typeof value === "bigint") {
        return `[BigInt: ${String(value)}]`;
      }
      const objName = getConstructorName$1(value);
      return `[object ${objName}]`;
    } catch (err) {
      return `**non-serializable** (${err})`;
    }
  }
  function getConstructorName$1(value) {
    const prototype = Object.getPrototypeOf(value);
    return prototype?.constructor ? prototype.constructor.name : "null prototype";
  }
  function utf8Length(value) {
    return ~-encodeURI(value).split(/%..|./).length;
  }
  function jsonSize(value) {
    return utf8Length(JSON.stringify(value));
  }
  function memoBuilder() {
    const inner = /* @__PURE__ */ new WeakSet();
    function memoize(obj) {
      if (inner.has(obj)) {
        return true;
      }
      inner.add(obj);
      return false;
    }
    function unmemoize(obj) {
      inner.delete(obj);
    }
    return [memoize, unmemoize];
  }

  function truncate(str, max = 0) {
    if (typeof str !== "string" || max === 0) {
      return str;
    }
    return str.length <= max ? str : `${str.slice(0, max)}...`;
  }
  function safeJoin(input, delimiter) {
    if (!Array.isArray(input)) {
      return "";
    }
    const output = [];
    for (let i = 0; i < input.length; i++) {
      const value = input[i];
      if (isPrimitive(value)) {
        output.push(String(value));
      } else if (value instanceof Error) {
        output.push(value.message ? `${value.name}: ${value.message}` : value.name);
      } else {
        output.push(stringifyValue(void 0, value));
      }
    }
    return output.join(delimiter);
  }
  function isMatchingPattern(value, pattern, requireExactStringMatch = false) {
    if (!isString(value)) {
      return false;
    }
    if (isRegExp(pattern)) {
      return pattern.test(value);
    }
    if (isString(pattern)) {
      return requireExactStringMatch ? value === pattern : value.includes(pattern);
    }
    if (typeof pattern === "function") {
      return pattern(value);
    }
    return false;
  }
  function stringMatchesSomePattern(testString, patterns = [], requireExactStringMatch = false) {
    for (const pattern of patterns) {
      if (isMatchingPattern(testString, pattern, requireExactStringMatch)) {
        return true;
      }
    }
    return false;
  }

  function getCrypto() {
    const gbl = GLOBAL_OBJ;
    return gbl.crypto || gbl.msCrypto;
  }
  let emptyUuid;
  function getRandomByte() {
    return safeMathRandom() * 16;
  }
  function uuid4(crypto = getCrypto()) {
    try {
      if (crypto?.randomUUID) {
        return withRandomSafeContext(() => crypto.randomUUID()).replace(/-/g, "");
      }
    } catch {
    }
    if (!emptyUuid) {
      emptyUuid = "10000000100040008000" + 1e11;
    }
    return emptyUuid.replace(
      /[018]/g,
      (c) => (
        // eslint-disable-next-line no-bitwise
        (c ^ (getRandomByte() & 15) >> c / 4).toString(16)
      )
    );
  }
  function getFirstException(event) {
    return event.exception?.values?.[0];
  }
  function getEventDescription(event) {
    const { message, event_id: eventId } = event;
    if (message) {
      return message;
    }
    const firstException = getFirstException(event);
    if (firstException) {
      if (firstException.type && firstException.value) {
        return `${firstException.type}: ${firstException.value}`;
      }
      return firstException.type || firstException.value || eventId || "<unknown>";
    }
    return eventId || "<unknown>";
  }
  function addExceptionTypeValue(event, value, type) {
    const exception = event.exception = event.exception || {};
    const values = exception.values = exception.values || [];
    const firstException = values[0] = values[0] || {};
    if (!firstException.value) {
      firstException.value = value || "";
    }
    if (!firstException.type) {
      firstException.type = "Error";
    }
  }
  function addExceptionMechanism(event, newMechanism) {
    const firstException = getFirstException(event);
    if (!firstException) {
      return;
    }
    applyExceptionMechanism(firstException, newMechanism);
  }
  function addExceptionMechanismToCapturedException(event, newMechanism) {
    const exceptions = event.exception?.values;
    const capturedException = exceptions?.find((exception) => exception.mechanism?.exception_id === 0) ?? exceptions?.[0];
    if (!capturedException) {
      return;
    }
    applyExceptionMechanism(capturedException, newMechanism);
  }
  function applyExceptionMechanism(exception, newMechanism) {
    const defaultMechanism = { type: "generic", handled: true };
    const currentMechanism = exception.mechanism;
    exception.mechanism = { ...defaultMechanism, ...currentMechanism, ...newMechanism };
    if (newMechanism && "data" in newMechanism) {
      exception.mechanism.data = { ...currentMechanism?.data, ...newMechanism.data };
    }
  }
  function checkOrSetAlreadyCaught(exception) {
    if (isAlreadyCaptured(exception)) {
      return true;
    }
    try {
      addNonEnumerableProperty(exception, "__sentry_captured__", true);
    } catch {
    }
    return false;
  }
  function isAlreadyCaptured(exception) {
    try {
      return exception.__sentry_captured__;
    } catch {
    }
  }

  const ONE_SECOND_IN_MS = 1e3;
  function dateTimestampInSeconds() {
    return safeDateNow() / ONE_SECOND_IN_MS;
  }
  function createUnixTimestampInSecondsFunc() {
    const { performance } = GLOBAL_OBJ;
    if (!performance?.now || !performance.timeOrigin) {
      return dateTimestampInSeconds;
    }
    const timeOrigin = performance.timeOrigin;
    return () => {
      return (timeOrigin + withRandomSafeContext(() => performance.now())) / ONE_SECOND_IN_MS;
    };
  }
  let _cachedTimestampInSeconds;
  function timestampInSeconds() {
    const func = _cachedTimestampInSeconds ?? (_cachedTimestampInSeconds = createUnixTimestampInSecondsFunc());
    return func();
  }
  let cachedTimeOrigin = null;
  function getBrowserTimeOrigin() {
    const { performance } = GLOBAL_OBJ;
    if (!performance?.now) {
      return void 0;
    }
    const threshold = 3e5;
    const performanceNow = withRandomSafeContext(() => performance.now());
    const dateNow = safeDateNow();
    const timeOrigin = performance.timeOrigin;
    if (typeof timeOrigin === "number") {
      const timeOriginDelta = Math.abs(timeOrigin + performanceNow - dateNow);
      if (timeOriginDelta < threshold) {
        return timeOrigin;
      }
    }
    return dateNow - performanceNow;
  }
  function browserPerformanceTimeOrigin() {
    if (cachedTimeOrigin === null) {
      cachedTimeOrigin = getBrowserTimeOrigin();
    }
    return cachedTimeOrigin;
  }

  function makeSession(context) {
    const startingTime = timestampInSeconds();
    const session = {
      sid: uuid4(),
      init: true,
      timestamp: startingTime,
      started: startingTime,
      duration: 0,
      status: "ok",
      errors: 0,
      ignoreDuration: false,
      toJSON: () => sessionToJSON(session)
    };
    if (context) {
      updateSession(session, context);
    }
    return session;
  }
  function updateSession(session, context = {}) {
    if (context.user) {
      if (!session.ipAddress && context.user.ip_address) {
        session.ipAddress = context.user.ip_address;
      }
      if (!session.did && !context.did) {
        session.did = context.user.id || context.user.email || context.user.username;
      }
    }
    session.timestamp = context.timestamp || timestampInSeconds();
    if (context.abnormal_mechanism) {
      session.abnormal_mechanism = context.abnormal_mechanism;
    }
    if (context.ignoreDuration) {
      session.ignoreDuration = context.ignoreDuration;
    }
    if (context.sid) {
      session.sid = context.sid.length === 32 ? context.sid : uuid4();
    }
    if (context.init !== void 0) {
      session.init = context.init;
    }
    if (!session.did && context.did) {
      session.did = `${context.did}`;
    }
    if (typeof context.started === "number") {
      session.started = context.started;
    }
    if (session.ignoreDuration) {
      session.duration = void 0;
    } else if (typeof context.duration === "number") {
      session.duration = context.duration;
    } else {
      const duration = session.timestamp - session.started;
      session.duration = duration >= 0 ? duration : 0;
    }
    if (context.release) {
      session.release = context.release;
    }
    if (context.environment) {
      session.environment = context.environment;
    }
    if (!session.ipAddress && context.ipAddress) {
      session.ipAddress = context.ipAddress;
    }
    if (!session.userAgent && context.userAgent) {
      session.userAgent = context.userAgent;
    }
    if (typeof context.errors === "number") {
      session.errors = context.errors;
    }
    if (context.status) {
      session.status = context.status;
    }
  }
  function closeSession(session, status) {
    let context = {};
    if (session.status === "ok") {
      context = { status: "exited" };
    }
    updateSession(session, context);
  }
  function sessionToJSON(session) {
    return {
      sid: `${session.sid}`,
      init: session.init,
      // Make sure that sec is converted to ms for date constructor
      started: new Date(session.started * 1e3).toISOString(),
      timestamp: new Date(session.timestamp * 1e3).toISOString(),
      status: session.status,
      errors: session.errors,
      did: typeof session.did === "number" || typeof session.did === "string" ? `${session.did}` : void 0,
      duration: session.duration,
      abnormal_mechanism: session.abnormal_mechanism,
      attrs: {
        release: session.release,
        environment: session.environment,
        ip_address: session.ipAddress,
        user_agent: session.userAgent
      }
    };
  }

  function merge(initialObj, mergeObj, levels = 2) {
    if (!mergeObj || typeof mergeObj !== "object" || levels <= 0) {
      return mergeObj;
    }
    if (initialObj && Object.keys(mergeObj).length === 0) {
      return initialObj;
    }
    const output = { ...initialObj };
    for (const key in mergeObj) {
      if (Object.prototype.hasOwnProperty.call(mergeObj, key)) {
        output[key] = merge(output[key], mergeObj[key], levels - 1);
      }
    }
    return output;
  }

  function generateTraceId() {
    return uuid4();
  }
  function generateSpanId() {
    return uuid4().substring(16);
  }

  const DEFAULT_MAX_BREADCRUMBS = 100;
  class Scope {
    // NOTE: Any field which gets added here should get added not only to the constructor but also to the `clone` method.
    constructor() {
      this._notifyingListeners = false;
      this._scopeListeners = [];
      this._eventProcessors = [];
      this._breadcrumbs = [];
      this._attachments = [];
      this._user = {};
      this._tags = {};
      this._attributes = {};
      this._extra = {};
      this._contexts = {};
      this._sdkProcessingMetadata = {};
      addNonEnumerableProperty(this, "refs", {});
      this._propagationContext = {
        traceId: generateTraceId(),
        sampleRand: safeMathRandom()
      };
    }
    /**
     * Clone all data from this scope into a new scope.
     */
    clone() {
      const newScope = new Scope();
      newScope._breadcrumbs = [...this._breadcrumbs];
      newScope._tags = { ...this._tags };
      newScope._attributes = { ...this._attributes };
      newScope._extra = { ...this._extra };
      newScope._contexts = { ...this._contexts };
      if (this._contexts.flags) {
        newScope._contexts.flags = {
          values: [...this._contexts.flags.values]
        };
      }
      newScope._user = this._user;
      newScope._level = this._level;
      newScope._session = this._session;
      newScope._transactionName = this._transactionName;
      newScope._fingerprint = this._fingerprint;
      newScope._eventProcessors = [...this._eventProcessors];
      newScope._attachments = [...this._attachments];
      newScope._sdkProcessingMetadata = { ...this._sdkProcessingMetadata };
      newScope._propagationContext = { ...this._propagationContext };
      newScope._client = this._client;
      newScope._lastEventId = this._lastEventId;
      newScope._conversationId = this._conversationId;
      newScope.refs = { ...this.refs };
      return newScope;
    }
    /**
     * Update the client assigned to this scope.
     * Note that not every scope will have a client assigned - isolation scopes & the global scope will generally not have a client,
     * as well as manually created scopes.
     */
    setClient(client) {
      this._client = client;
    }
    /**
     * Set the ID of the last captured error event.
     * This is generally only captured on the isolation scope.
     */
    setLastEventId(lastEventId) {
      this._lastEventId = lastEventId;
    }
    /**
     * Get the client assigned to this scope.
     */
    getClient() {
      return this._client;
    }
    /**
     * Get the ID of the last captured error event.
     * This is generally only available on the isolation scope.
     */
    lastEventId() {
      return this._lastEventId;
    }
    /**
     * @inheritDoc
     */
    addScopeListener(callback) {
      this._scopeListeners.push(callback);
    }
    /**
     * Add an event processor that will be called before an event is sent.
     */
    addEventProcessor(callback) {
      this._eventProcessors.push(callback);
      return this;
    }
    /**
     * Set the user for this scope.
     * Set to `null` to unset the user.
     */
    setUser(user) {
      this._user = user || {
        email: void 0,
        id: void 0,
        ip_address: void 0,
        username: void 0
      };
      if (this._session) {
        updateSession(this._session, { user });
      }
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Get the user from this scope.
     */
    getUser() {
      return this._user;
    }
    /**
     * Set the conversation ID for this scope.
     * Set to `null` to unset the conversation ID.
     */
    setConversationId(conversationId) {
      this._conversationId = conversationId || void 0;
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Set an object that will be merged into existing tags on the scope,
     * and will be sent as tags data with the event.
     */
    setTags(tags) {
      this._tags = {
        ...this._tags,
        ...tags
      };
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Set a single tag that will be sent as tags data with the event.
     */
    setTag(key, value) {
      return this.setTags({ [key]: value });
    }
    /**
     * Sets attributes onto the scope.
     *
     * These attributes are applied to logs, metrics and streamed spans.
     *
     * Supported attribute value types are `string`, `number`, `boolean`, `string[]`, `number[]` and `boolean[]`.
     *
     * @param newAttributes - The attributes to set on the scope, as key-value pairs.
     *
     * @example
     * ```typescript
     * scope.setAttributes({
     *   is_admin: true,
     *   payment_selection: 'credit_card',
     *   render_duration: 150,
     * });
     * ```
     */
    setAttributes(newAttributes) {
      this._attributes = {
        ...this._attributes,
        ...newAttributes
      };
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Sets an attribute onto the scope.
     *
     * These attributes are applied to logs, metrics and streamed spans.
     *
     * Supported attribute value types are `string`, `number`, `boolean`, `string[]`, `number[]` and `boolean[]`.
     *
     * @param key - The attribute key.
     * @param value - The attribute value.
     *
     * @example
     * ```typescript
     * scope.setAttribute('is_admin', true);
     * scope.setAttribute('render_duration', 150);
     * ```
     */
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    setAttribute(key, value) {
      return this.setAttributes({ [key]: value });
    }
    /**
     * Removes the attribute with the given key from the scope.
     *
     * @param key - The attribute key.
     *
     * @example
     * ```typescript
     * scope.removeAttribute('is_admin');
     * ```
     */
    removeAttribute(key) {
      if (key in this._attributes) {
        delete this._attributes[key];
        this._notifyScopeListeners();
      }
      return this;
    }
    /**
     * Set an object that will be merged into existing extra on the scope,
     * and will be sent as extra data with the event.
     */
    setExtras(extras) {
      this._extra = {
        ...this._extra,
        ...extras
      };
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Set a single key:value extra entry that will be sent as extra data with the event.
     */
    setExtra(key, extra) {
      this._extra = { ...this._extra, [key]: extra };
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Sets the fingerprint on the scope to send with the events.
     * @param {string[]} fingerprint Fingerprint to group events in Sentry.
     */
    setFingerprint(fingerprint) {
      this._fingerprint = fingerprint;
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Sets the level on the scope for future events.
     */
    setLevel(level) {
      this._level = level;
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Sets the transaction name on the scope so that the name of e.g. taken server route or
     * the page location is attached to future events.
     *
     * IMPORTANT: Calling this function does NOT change the name of the currently active
     * root span. If you want to change the name of the active root span, use
     * `Sentry.updateSpanName(rootSpan, 'new name')` instead.
     *
     * By default, the SDK updates the scope's transaction name automatically on sensible
     * occasions, such as a page navigation or when handling a new request on the server.
     */
    setTransactionName(name) {
      this._transactionName = name;
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Sets context data with the given name.
     * Data passed as context will be normalized. You can also pass `null` to unset the context.
     * Note that context data will not be merged - calling `setContext` will overwrite an existing context with the same key.
     */
    setContext(key, context) {
      if (context === null) {
        delete this._contexts[key];
      } else {
        this._contexts[key] = context;
      }
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Set the session for the scope.
     */
    setSession(session) {
      if (!session) {
        delete this._session;
      } else {
        this._session = session;
      }
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Get the session from the scope.
     */
    getSession() {
      return this._session;
    }
    /**
     * Updates the scope with provided data. Can work in three variations:
     * - plain object containing updatable attributes
     * - Scope instance that'll extract the attributes from
     * - callback function that'll receive the current scope as an argument and allow for modifications
     */
    update(captureContext) {
      if (!captureContext) {
        return this;
      }
      const scopeToMerge = typeof captureContext === "function" ? captureContext(this) : captureContext;
      const scopeInstance = scopeToMerge instanceof Scope ? scopeToMerge.getScopeData() : isPlainObject(scopeToMerge) ? captureContext : void 0;
      const {
        tags,
        attributes,
        extra,
        user,
        contexts,
        level,
        fingerprint = [],
        propagationContext,
        conversationId
      } = scopeInstance || {};
      this._tags = { ...this._tags, ...tags };
      this._attributes = { ...this._attributes, ...attributes };
      this._extra = { ...this._extra, ...extra };
      this._contexts = { ...this._contexts, ...contexts };
      if (user && Object.keys(user).length) {
        this._user = user;
      }
      if (level) {
        this._level = level;
      }
      if (fingerprint.length) {
        this._fingerprint = fingerprint;
      }
      if (propagationContext) {
        this._propagationContext = propagationContext;
      }
      if (conversationId) {
        this._conversationId = conversationId;
      }
      return this;
    }
    /**
     * Adds a breadcrumb to the scope.
     * By default, the last 100 breadcrumbs are kept.
     */
    addBreadcrumb(breadcrumb, maxBreadcrumbs) {
      const maxCrumbs = typeof maxBreadcrumbs === "number" ? maxBreadcrumbs : DEFAULT_MAX_BREADCRUMBS;
      if (maxCrumbs <= 0) {
        return this;
      }
      const mergedBreadcrumb = {
        timestamp: dateTimestampInSeconds(),
        ...breadcrumb,
        // Breadcrumb messages can theoretically be infinitely large and they're held in memory so we truncate them not to leak (too much) memory
        message: breadcrumb.message ? truncate(breadcrumb.message, 2048) : breadcrumb.message
      };
      this._breadcrumbs.push(mergedBreadcrumb);
      if (this._breadcrumbs.length > maxCrumbs) {
        this._breadcrumbs = this._breadcrumbs.slice(-maxCrumbs);
      }
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Get the last breadcrumb of the scope.
     */
    getLastBreadcrumb() {
      return this._breadcrumbs[this._breadcrumbs.length - 1];
    }
    /**
     * Clear all breadcrumbs from the scope.
     */
    clearBreadcrumbs() {
      this._breadcrumbs = [];
      this._notifyScopeListeners();
      return this;
    }
    /**
     * Add an attachment to the scope.
     */
    addAttachment(attachment) {
      this._attachments.push(attachment);
      return this;
    }
    /**
     * Clear all attachments from the scope.
     */
    clearAttachments() {
      this._attachments = [];
      return this;
    }
    /**
     * Get the data of this scope, which should be applied to an event during processing.
     */
    getScopeData() {
      return {
        breadcrumbs: this._breadcrumbs,
        attachments: this._attachments,
        contexts: this._contexts,
        tags: this._tags,
        attributes: this._attributes,
        extra: this._extra,
        user: this._user,
        level: this._level,
        fingerprint: this._fingerprint || [],
        eventProcessors: this._eventProcessors,
        propagationContext: this._propagationContext,
        sdkProcessingMetadata: this._sdkProcessingMetadata,
        transactionName: this._transactionName,
        conversationId: this._conversationId
      };
    }
    /**
     * Add data which will be accessible during event processing but won't get sent to Sentry.
     */
    setSDKProcessingMetadata(newData) {
      this._sdkProcessingMetadata = merge(this._sdkProcessingMetadata, newData, 2);
      return this;
    }
    /**
     * Add propagation context to the scope, used for distributed tracing
     */
    setPropagationContext(context) {
      this._propagationContext = context;
      return this;
    }
    /**
     * Get propagation context from the scope, used for distributed tracing
     */
    getPropagationContext() {
      return this._propagationContext;
    }
    /**
     * Capture an exception for this scope.
     *
     * @returns {string} The id of the captured Sentry event.
     */
    captureException(exception, hint) {
      const eventId = hint?.event_id || uuid4();
      if (!this._client) {
        debug.warn("No client configured on scope - will not capture exception!");
        return eventId;
      }
      const syntheticException = new Error("Sentry syntheticException");
      this._client.captureException(
        exception,
        {
          originalException: exception,
          syntheticException,
          ...hint,
          event_id: eventId
        },
        this
      );
      return eventId;
    }
    /**
     * Capture a message for this scope.
     *
     * @returns {string} The id of the captured message.
     */
    captureMessage(message, level, hint) {
      const eventId = hint?.event_id || uuid4();
      if (!this._client) {
        debug.warn("No client configured on scope - will not capture message!");
        return eventId;
      }
      const syntheticException = hint?.syntheticException ?? new Error(message);
      this._client.captureMessage(
        message,
        level,
        {
          originalException: message,
          syntheticException,
          ...hint,
          event_id: eventId
        },
        this
      );
      return eventId;
    }
    /**
     * Capture a Sentry event for this scope.
     *
     * @returns {string} The id of the captured event.
     */
    captureEvent(event, hint) {
      const eventId = event.event_id || hint?.event_id || uuid4();
      if (!this._client) {
        debug.warn("No client configured on scope - will not capture event!");
        return eventId;
      }
      this._client.captureEvent(event, { ...hint, event_id: eventId }, this);
      return eventId;
    }
    /**
     * This will be called on every set call.
     */
    _notifyScopeListeners() {
      if (!this._notifyingListeners) {
        this._notifyingListeners = true;
        this._scopeListeners.forEach((callback) => {
          callback(this);
        });
        this._notifyingListeners = false;
      }
    }
  }

  function getDefaultCurrentScope() {
    return getGlobalSingleton("defaultCurrentScope", () => new Scope());
  }
  function getDefaultIsolationScope() {
    return getGlobalSingleton("defaultIsolationScope", () => new Scope());
  }

  const SUPPRESS_TRACING_KEY = "__SENTRY_SUPPRESS_TRACING__";

  const isActualPromise = (p) => p instanceof Promise && !p[kChainedCopy];
  const kChainedCopy = /* @__PURE__ */ Symbol("chained PromiseLike");
  const chainAndCopyPromiseLike = (original, onSuccess, onError) => {
    const chained = original.then(
      (value) => {
        onSuccess(value);
        return value;
      },
      (err) => {
        onError(err);
        throw err;
      }
    );
    return isActualPromise(chained) && isActualPromise(original) ? chained : copyProps(original, chained);
  };
  const copyProps = (original, chained) => {
    if (!chained) return original;
    let mutated = false;
    for (const key in original) {
      if (key in chained) continue;
      mutated = true;
      const value = original[key];
      if (typeof value === "function") {
        Object.defineProperty(chained, key, {
          value: (...args) => value.apply(original, args),
          enumerable: true,
          configurable: true,
          writable: true
        });
      } else {
        chained[key] = value;
      }
    }
    if (mutated) Object.assign(chained, { [kChainedCopy]: true });
    return chained;
  };

  class AsyncContextStack {
    constructor(scope, isolationScope) {
      let assignedScope;
      if (!scope) {
        assignedScope = new Scope();
      } else {
        assignedScope = scope;
      }
      let assignedIsolationScope;
      if (!isolationScope) {
        assignedIsolationScope = new Scope();
      } else {
        assignedIsolationScope = isolationScope;
      }
      this._stack = [{ scope: assignedScope }];
      this._isolationScope = assignedIsolationScope;
    }
    /**
     * Fork a scope for the stack.
     */
    withScope(callback) {
      const scope = this._pushScope();
      let maybePromiseResult;
      try {
        maybePromiseResult = callback(scope);
      } catch (e) {
        this._popScope();
        throw e;
      }
      if (isThenable(maybePromiseResult)) {
        return chainAndCopyPromiseLike(
          maybePromiseResult,
          () => this._popScope(),
          () => this._popScope()
        );
      }
      this._popScope();
      return maybePromiseResult;
    }
    /**
     * Get the client of the stack.
     */
    getClient() {
      return this.getStackTop().client;
    }
    /**
     * Returns the scope of the top stack.
     */
    getScope() {
      return this.getStackTop().scope;
    }
    /**
     * Get the isolation scope for the stack.
     */
    getIsolationScope() {
      return this._isolationScope;
    }
    /**
     * Returns the topmost scope layer in the order domain > local > process.
     */
    getStackTop() {
      return this._stack[this._stack.length - 1];
    }
    /**
     * Push a scope to the stack.
     */
    _pushScope() {
      const scope = this.getScope().clone();
      this._stack.push({
        client: this.getClient(),
        scope
      });
      return scope;
    }
    /**
     * Pop a scope from the stack.
     */
    _popScope() {
      if (this._stack.length <= 1) return false;
      return !!this._stack.pop();
    }
  }
  function getAsyncContextStack() {
    const registry = getMainCarrier();
    const sentry = getSentryCarrier(registry);
    return sentry.stack = sentry.stack || new AsyncContextStack(getDefaultCurrentScope(), getDefaultIsolationScope());
  }
  function withScope$1(callback) {
    return getAsyncContextStack().withScope(callback);
  }
  function withSetScope(scope, callback) {
    const stack = getAsyncContextStack();
    return stack.withScope(() => {
      stack.getStackTop().scope = scope;
      return callback(scope);
    });
  }
  function withIsolationScope$1(callback) {
    return getAsyncContextStack().withScope(() => {
      return callback(getAsyncContextStack().getIsolationScope());
    });
  }
  function getStackAsyncContextStrategy() {
    return {
      suppressTracing: suppressTracingInStack,
      withIsolationScope: withIsolationScope$1,
      withScope: withScope$1,
      withSetScope,
      withSetIsolationScope: (_isolationScope, callback) => {
        return withIsolationScope$1(callback);
      },
      getCurrentScope: () => getAsyncContextStack().getScope(),
      getIsolationScope: () => getAsyncContextStack().getIsolationScope()
    };
  }
  function suppressTracingInStack(callback) {
    return withScope$1((scope) => {
      scope.setSDKProcessingMetadata({ [SUPPRESS_TRACING_KEY]: true });
      const res = callback();
      scope.setSDKProcessingMetadata({ [SUPPRESS_TRACING_KEY]: void 0 });
      return res;
    });
  }

  function getAsyncContextStrategy(carrier) {
    const sentry = getSentryCarrier(carrier);
    if (sentry.acs) {
      return sentry.acs;
    }
    return getStackAsyncContextStrategy();
  }

  function isAttributeObject(maybeObj) {
    return typeof maybeObj === "object" && maybeObj != null && !Array.isArray(maybeObj) && Object.keys(maybeObj).includes("value");
  }
  function attributeValueToTypedAttributeValue(rawValue, useFallback) {
    const { value, unit } = isAttributeObject(rawValue) ? rawValue : { value: rawValue, unit: void 0 };
    const attributeValue = getTypedAttributeValue(value);
    const checkedUnit = unit && typeof unit === "string" ? { unit } : {};
    if (attributeValue) {
      return { ...attributeValue, ...checkedUnit };
    }
    if (!useFallback || useFallback === "skip-undefined" && value === void 0) {
      return;
    }
    let stringValue = "";
    try {
      stringValue = JSON.stringify(value) ?? "";
    } catch {
    }
    return {
      value: stringValue,
      type: "string",
      ...checkedUnit
    };
  }
  function serializeAttributes(attributes, fallback = false) {
    const serializedAttributes = {};
    for (const [key, value] of Object.entries(attributes ?? {})) {
      const typedValue = attributeValueToTypedAttributeValue(value, fallback);
      if (typedValue) {
        serializedAttributes[key] = typedValue;
      }
    }
    return serializedAttributes;
  }
  function estimateTypedAttributesSizeInBytes(attributes) {
    if (!attributes) {
      return 0;
    }
    let weight = 0;
    for (const [key, attr] of Object.entries(attributes)) {
      weight += key.length * 2;
      weight += attr.type.length * 2;
      weight += (attr.unit?.length ?? 0) * 2;
      const val = attr.value;
      if (Array.isArray(val)) {
        weight += estimatePrimitiveSizeInBytes$1(val[0]) * val.length;
      } else if (isPrimitive(val)) {
        weight += estimatePrimitiveSizeInBytes$1(val);
      } else {
        weight += 100;
      }
    }
    return weight;
  }
  function estimatePrimitiveSizeInBytes$1(value) {
    if (typeof value === "string") {
      return value.length * 2;
    } else if (typeof value === "boolean") {
      return 4;
    } else if (typeof value === "number") {
      return 8;
    }
    return 0;
  }
  function getTypedAttributeValue(value) {
    if (Array.isArray(value)) {
      return { value, type: "array" };
    }
    const primitiveType = typeof value === "string" ? "string" : typeof value === "boolean" ? "boolean" : typeof value === "number" && !Number.isNaN(value) ? Number.isInteger(value) ? "integer" : "double" : null;
    if (primitiveType) {
      return { value, type: primitiveType };
    }
  }

  function getExternalPropagationContext() {
    return getSentryCarrier(getMainCarrier()).externalPropagationContextProvider?.();
  }
  function hasExternalPropagationContext() {
    return getSentryCarrier(getMainCarrier()).externalPropagationContextProvider !== void 0;
  }
  function getCurrentScope() {
    const carrier = getMainCarrier();
    const acs = getAsyncContextStrategy(carrier);
    return acs.getCurrentScope();
  }
  function getIsolationScope() {
    const carrier = getMainCarrier();
    const acs = getAsyncContextStrategy(carrier);
    return acs.getIsolationScope();
  }
  function getGlobalScope() {
    return getGlobalSingleton("globalScope", () => new Scope());
  }
  function withScope(...rest) {
    const carrier = getMainCarrier();
    const acs = getAsyncContextStrategy(carrier);
    if (rest.length === 2) {
      const [scope, callback] = rest;
      if (!scope) {
        return acs.withScope(callback);
      }
      return acs.withSetScope(scope, callback);
    }
    return acs.withScope(rest[0]);
  }
  function withIsolationScope(...rest) {
    const carrier = getMainCarrier();
    const acs = getAsyncContextStrategy(carrier);
    if (rest.length === 2) {
      const [isolationScope, callback] = rest;
      if (!isolationScope) {
        return acs.withIsolationScope(callback);
      }
      return acs.withSetIsolationScope(isolationScope, callback);
    }
    return acs.withIsolationScope(rest[0]);
  }
  function getClient() {
    return getCurrentScope().getClient();
  }
  function getTraceContextFromScope(scope) {
    const externalContext = getExternalPropagationContext();
    if (externalContext) {
      return { trace_id: externalContext.traceId, span_id: externalContext.spanId };
    }
    const propagationContext = scope.getPropagationContext();
    const { traceId, parentSpanId, propagationSpanId } = propagationContext;
    const traceContext = {
      trace_id: traceId,
      span_id: propagationSpanId || generateSpanId()
    };
    if (parentSpanId) {
      traceContext.parent_span_id = parentSpanId;
    }
    return traceContext;
  }

  const Li="browser.navigation.id",Mi="browser.navigation.type",Ui="browser.paint.type",Qt="code.file.path",Jt="code.function.name",go="http.request.header",bo="http.request.method",So="http.request.same_origin",Ao="http.response.body.size",Po="http.response.size",Do="http.response.status_code",Mp="network.connection.effective_type",Up="network.connection.rtt",Gp="network.connection.type",ju="sentry.idle_span_finish_reason",cd="sentry.op",ud="sentry.origin",fd="sentry.replay_id",Td="sentry.sdk.name",Ed="sentry.sdk.version",Id="sentry.segment.id",Ad="sentry.segment.name",wd="sentry.segment.name.source",zd="sentry.trace_lifecycle",Fd="sentry.transaction",Zd="server.address",eg="server.port",Ig="ui.component_name",Ug="url.domain",Gg="url.fragment",zg="url.full",Yg="url.path",Kg="url.query",Qg="url.scheme",Jg="user_agent.original";

  const SEMANTIC_ATTRIBUTE_SENTRY_SAMPLE_RATE = "sentry.sample_rate";
  const SEMANTIC_ATTRIBUTE_SENTRY_PREVIOUS_TRACE_SAMPLE_RATE = "sentry.previous_trace_sample_rate";
  const SEMANTIC_ATTRIBUTE_SENTRY_OP = "sentry.op";
  const SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN = "sentry.origin";
  const SEMANTIC_ATTRIBUTE_SENTRY_STATUS_MESSAGE = "sentry.status.message";
  const SEMANTIC_ATTRIBUTE_SENTRY_IDLE_SPAN_FINISH_REASON = "sentry.idle_span_finish_reason";
  const SEMANTIC_ATTRIBUTE_SENTRY_MEASUREMENT_UNIT = "sentry.measurement_unit";
  const SEMANTIC_ATTRIBUTE_SENTRY_MEASUREMENT_VALUE = "sentry.measurement_value";
  const SEMANTIC_ATTRIBUTE_SENTRY_RELEASE = "sentry.release";
  const SEMANTIC_ATTRIBUTE_SENTRY_ENVIRONMENT = "sentry.environment";
  const SEMANTIC_ATTRIBUTE_SENTRY_SDK_INTEGRATIONS = "sentry.sdk.integrations";
  const SEMANTIC_ATTRIBUTE_USER_ID = "user.id";
  const SEMANTIC_ATTRIBUTE_USER_EMAIL = "user.email";
  const SEMANTIC_ATTRIBUTE_USER_IP_ADDRESS = "user.ip_address";
  const SEMANTIC_ATTRIBUTE_USER_USERNAME = "user.name";
  const SEMANTIC_ATTRIBUTE_SENTRY_CUSTOM_SPAN_NAME = "sentry.custom_span_name";
  const SEMANTIC_ATTRIBUTE_PROFILE_ID = "sentry.profile_id";
  const SEMANTIC_ATTRIBUTE_EXCLUSIVE_TIME = "sentry.exclusive_time";
  const SEMANTIC_LINK_ATTRIBUTE_LINK_TYPE = "sentry.link.type";
  const GEN_AI_CONVERSATION_ID_ATTRIBUTE = "gen_ai.conversation.id";

  const SPAN_STATUS_TYPES = [
    /** The operation completed successfully. */
    "ok",
    /** Deadline expired before operation could complete. */
    "deadline_exceeded",
    /** 401 Unauthorized (actually does mean unauthenticated according to RFC 7235) */
    "unauthenticated",
    /** 403 Forbidden */
    "permission_denied",
    /** 404 Not Found. Some requested entity (file or directory) was not found. */
    "not_found",
    /** 429 Too Many Requests */
    "resource_exhausted",
    /** Client specified an invalid argument. 4xx. */
    "invalid_argument",
    /** 501 Not Implemented */
    "unimplemented",
    /** 503 Service Unavailable */
    "unavailable",
    /** Other/generic 5xx. */
    "internal_error",
    /** Unknown. Any non-standard HTTP status code. */
    "unknown_error",
    /** The operation was cancelled (typically by the user). */
    "cancelled",
    /** Already exists (409) */
    "already_exists",
    /** Operation was rejected because the system is not in a state required for the operation's */
    "failed_precondition",
    /** The operation was aborted, typically due to a concurrency issue. */
    "aborted",
    /** Operation was attempted past the valid range. */
    "out_of_range",
    /** Unrecoverable data loss or corruption */
    "data_loss"
  ];

  const SPAN_STATUS_UNSET = 0;
  const SPAN_STATUS_OK = 1;
  const SPAN_STATUS_ERROR = 2;
  function isStatusErrorMessageValid(message) {
    return message !== "ok" && SPAN_STATUS_TYPES.includes(message);
  }
  function getSpanStatusFromHttpCode(httpStatus) {
    if (httpStatus < 400 && httpStatus >= 100) {
      return { code: SPAN_STATUS_OK };
    }
    if (httpStatus >= 400 && httpStatus < 500) {
      switch (httpStatus) {
        case 401:
          return { code: SPAN_STATUS_ERROR, message: "unauthenticated" };
        case 403:
          return { code: SPAN_STATUS_ERROR, message: "permission_denied" };
        case 404:
          return { code: SPAN_STATUS_ERROR, message: "not_found" };
        case 409:
          return { code: SPAN_STATUS_ERROR, message: "already_exists" };
        case 413:
          return { code: SPAN_STATUS_ERROR, message: "failed_precondition" };
        case 429:
          return { code: SPAN_STATUS_ERROR, message: "resource_exhausted" };
        case 499:
          return { code: SPAN_STATUS_ERROR, message: "cancelled" };
        default:
          return { code: SPAN_STATUS_ERROR, message: "invalid_argument" };
      }
    }
    if (httpStatus >= 500 && httpStatus < 600) {
      switch (httpStatus) {
        case 501:
          return { code: SPAN_STATUS_ERROR, message: "unimplemented" };
        case 503:
          return { code: SPAN_STATUS_ERROR, message: "unavailable" };
        case 504:
          return { code: SPAN_STATUS_ERROR, message: "deadline_exceeded" };
        default:
          return { code: SPAN_STATUS_ERROR, message: "internal_error" };
      }
    }
    return { code: SPAN_STATUS_ERROR, message: "internal_error" };
  }
  function setHttpStatus(span, httpStatus) {
    span.setAttribute("http.response.status_code", httpStatus);
    const spanStatus = getSpanStatusFromHttpCode(httpStatus);
    if (spanStatus.message !== "unknown_error") {
      span.setStatus(spanStatus);
    }
  }

  function makeWeakRef(value) {
    try {
      const WeakRefImpl = GLOBAL_OBJ.WeakRef;
      if (typeof WeakRefImpl === "function") {
        return new WeakRefImpl(value);
      }
    } catch {
    }
    return value;
  }
  function derefWeakRef(ref) {
    if (!ref) {
      return void 0;
    }
    if (typeof ref === "object" && "deref" in ref && typeof ref.deref === "function") {
      try {
        return ref.deref();
      } catch {
        return void 0;
      }
    }
    return ref;
  }

  const SCOPE_ON_START_SPAN_FIELD = "_sentryScope";
  const ISOLATION_SCOPE_ON_START_SPAN_FIELD = "_sentryIsolationScope";
  const TRACER_PROVIDER_SPAN_FIELD = /* @__PURE__ */ Symbol.for("sentry.tracerProviderSpan");
  function setCapturedScopesOnSpan(span, scope, isolationScope) {
    if (span) {
      addNonEnumerableProperty(span, ISOLATION_SCOPE_ON_START_SPAN_FIELD, makeWeakRef(isolationScope));
      addNonEnumerableProperty(span, SCOPE_ON_START_SPAN_FIELD, scope);
    }
  }
  function getCapturedScopesOnSpan(span) {
    const spanWithScopes = span;
    return {
      scope: spanWithScopes[SCOPE_ON_START_SPAN_FIELD],
      isolationScope: derefWeakRef(spanWithScopes[ISOLATION_SCOPE_ON_START_SPAN_FIELD])
    };
  }
  function spanIsTracerProviderSpan(span) {
    return span[TRACER_PROVIDER_SPAN_FIELD] === true;
  }

  const SENTRY_BAGGAGE_KEY_PREFIX = "sentry-";
  const MAX_BAGGAGE_STRING_LENGTH = 8192;
  function baggageHeaderToDynamicSamplingContext(baggageHeader) {
    const baggageObject = parseBaggageHeader(baggageHeader);
    if (!baggageObject) {
      return void 0;
    }
    const dynamicSamplingContext = Object.entries(baggageObject).reduce((acc, [key, value]) => {
      if (key.startsWith(SENTRY_BAGGAGE_KEY_PREFIX)) {
        const nonPrefixedKey = key.slice(SENTRY_BAGGAGE_KEY_PREFIX.length);
        acc[nonPrefixedKey] = value;
      }
      return acc;
    }, {});
    if (Object.keys(dynamicSamplingContext).length > 0) {
      return dynamicSamplingContext;
    } else {
      return void 0;
    }
  }
  function dynamicSamplingContextToSentryBaggageHeader(dynamicSamplingContext) {
    if (!dynamicSamplingContext) {
      return void 0;
    }
    const sentryPrefixedDSC = Object.entries(dynamicSamplingContext).reduce(
      (acc, [dscKey, dscValue]) => {
        if (dscValue) {
          acc[`${SENTRY_BAGGAGE_KEY_PREFIX}${dscKey}`] = dscValue;
        }
        return acc;
      },
      {}
    );
    return objectToBaggageHeader(sentryPrefixedDSC);
  }
  function parseBaggageHeader(baggageHeader) {
    if (!baggageHeader || !isString(baggageHeader) && !Array.isArray(baggageHeader)) {
      return void 0;
    }
    if (Array.isArray(baggageHeader)) {
      return baggageHeader.reduce((acc, curr) => {
        const currBaggageObject = baggageHeaderToObject(curr);
        Object.entries(currBaggageObject).forEach(([key, value]) => {
          acc[key] = value;
        });
        return acc;
      }, {});
    }
    return baggageHeaderToObject(baggageHeader);
  }
  function baggageHeaderToObject(baggageHeader) {
    return baggageHeader.split(",").map((baggageEntry) => {
      const eqIdx = baggageEntry.indexOf("=");
      if (eqIdx === -1) {
        return [];
      }
      const key = baggageEntry.slice(0, eqIdx);
      const value = baggageEntry.slice(eqIdx + 1);
      return [key, value].map((keyOrValue) => {
        try {
          return decodeURIComponent(keyOrValue.trim());
        } catch {
          return;
        }
      });
    }).reduce((acc, [key, value]) => {
      if (key && value) {
        acc[key] = value;
      }
      return acc;
    }, {});
  }
  function objectToBaggageHeader(object) {
    if (Object.keys(object).length === 0) {
      return void 0;
    }
    return Object.entries(object).reduce((baggageHeader, [objectKey, objectValue], currentIndex) => {
      const baggageEntry = `${encodeURIComponent(objectKey)}=${encodeURIComponent(objectValue)}`;
      const newBaggageHeader = currentIndex === 0 ? baggageEntry : `${baggageHeader},${baggageEntry}`;
      if (newBaggageHeader.length > MAX_BAGGAGE_STRING_LENGTH) {
        debug.warn(
          `Not adding key: ${objectKey} with val: ${objectValue} to baggage header due to exceeding baggage size limits.`
        );
        return baggageHeader;
      } else {
        return newBaggageHeader;
      }
    }, "");
  }

  const ORG_ID_REGEX = /^o(\d+)\./;
  const DSN_REGEX = /^(?:(\w+):)\/\/(?:(\w+)(?::(\w+)?)?@)((?:\[[:.%\w]+\]|[\w.-]+))(?::(\d+))?\/(.+)/;
  function isValidProtocol(protocol) {
    return protocol === "http" || protocol === "https";
  }
  function dsnToString(dsn, withPassword = false) {
    const { host, path, pass, port, projectId, protocol, publicKey } = dsn;
    return `${protocol}://${publicKey}${withPassword && pass ? `:${pass}` : ""}@${host}${port ? `:${port}` : ""}/${path ? `${path}/` : path}${projectId}`;
  }
  function dsnFromString(str) {
    const match = DSN_REGEX.exec(str);
    if (!match) {
      consoleSandbox(() => {
        console.error(`Invalid Sentry Dsn: ${str}`);
      });
      return void 0;
    }
    const [protocol, publicKey, pass = "", host = "", port = "", lastPath = ""] = match.slice(1);
    let path = "";
    let projectId = lastPath;
    const split = projectId.split("/");
    if (split.length > 1) {
      path = split.slice(0, -1).join("/");
      projectId = split.pop();
    }
    if (projectId) {
      const projectMatch = projectId.match(/^\d+/);
      if (projectMatch) {
        projectId = projectMatch[0];
      }
    }
    return dsnFromComponents({ host, pass, path, projectId, port, protocol, publicKey });
  }
  function dsnFromComponents(components) {
    return {
      protocol: components.protocol,
      publicKey: components.publicKey || "",
      pass: components.pass || "",
      host: components.host,
      port: components.port || "",
      path: components.path || "",
      projectId: components.projectId
    };
  }
  function validateDsn(dsn) {
    const { port, projectId, protocol } = dsn;
    const requiredComponents = ["protocol", "publicKey", "host", "projectId"];
    const hasMissingRequiredComponent = requiredComponents.find((component) => {
      if (!dsn[component]) {
        debug.error(`Invalid Sentry Dsn: ${component} missing`);
        return true;
      }
      return false;
    });
    if (hasMissingRequiredComponent) {
      return false;
    }
    if (!projectId.match(/^\d+$/)) {
      debug.error(`Invalid Sentry Dsn: Invalid projectId ${projectId}`);
      return false;
    }
    if (!isValidProtocol(protocol)) {
      debug.error(`Invalid Sentry Dsn: Invalid protocol ${protocol}`);
      return false;
    }
    if (port && isNaN(parseInt(port, 10))) {
      debug.error(`Invalid Sentry Dsn: Invalid port ${port}`);
      return false;
    }
    return true;
  }
  function extractOrgIdFromDsnHost(host) {
    const match = host.match(ORG_ID_REGEX);
    return match?.[1];
  }
  function extractOrgIdFromClient(client) {
    const options = client.getOptions();
    const { host } = client.getDsn() || {};
    let org_id;
    if (options.orgId) {
      org_id = String(options.orgId);
    } else if (host) {
      org_id = extractOrgIdFromDsnHost(host);
    }
    return org_id;
  }
  function makeDsn(from) {
    const components = typeof from === "string" ? dsnFromString(from) : dsnFromComponents(from);
    if (!components || !validateDsn(components)) {
      return void 0;
    }
    return components;
  }

  function parseSampleRate(sampleRate) {
    if (typeof sampleRate === "boolean") {
      return Number(sampleRate);
    }
    const rate = typeof sampleRate === "string" ? parseFloat(sampleRate) : sampleRate;
    if (typeof rate !== "number" || isNaN(rate) || rate < 0 || rate > 1) {
      return void 0;
    }
    return rate;
  }

  const TRACEPARENT_REGEXP = new RegExp(
    "^[ \\t]*([0-9a-f]{32})?-?([0-9a-f]{16})?-?([01])?[ \\t]*$"
    // whitespace
  );
  function extractTraceparentData(traceparent) {
    if (!traceparent) {
      return void 0;
    }
    const matches = traceparent.match(TRACEPARENT_REGEXP);
    if (!matches) {
      return void 0;
    }
    let parentSampled;
    if (matches[3] === "1") {
      parentSampled = true;
    } else if (matches[3] === "0") {
      parentSampled = false;
    }
    return {
      traceId: matches[1],
      parentSampled,
      parentSpanId: matches[2]
    };
  }
  function propagationContextFromHeaders(sentryTrace, baggage) {
    const traceparentData = extractTraceparentData(sentryTrace);
    const dynamicSamplingContext = baggageHeaderToDynamicSamplingContext(baggage);
    if (!traceparentData?.traceId) {
      return {
        traceId: generateTraceId(),
        sampleRand: safeMathRandom()
      };
    }
    const sampleRand = getSampleRandFromTraceparentAndDsc(traceparentData, dynamicSamplingContext);
    if (dynamicSamplingContext) {
      dynamicSamplingContext.sample_rand = sampleRand.toString();
    }
    const { traceId, parentSpanId, parentSampled } = traceparentData;
    return {
      traceId,
      parentSpanId,
      sampled: parentSampled,
      dsc: dynamicSamplingContext || {},
      // If we have traceparent data but no DSC it means we are not head of trace and we must freeze it
      sampleRand
    };
  }
  function generateSentryTraceHeader(traceId = generateTraceId(), spanId = generateSpanId(), sampled) {
    let sampledString = "";
    if (sampled !== void 0) {
      sampledString = sampled ? "-1" : "-0";
    }
    return `${traceId}-${spanId}${sampledString}`;
  }
  function generateTraceparentHeader(traceId = generateTraceId(), spanId = generateSpanId(), sampled) {
    return `00-${traceId}-${spanId}-${sampled ? "01" : "00"}`;
  }
  function getSampleRandFromTraceparentAndDsc(traceparentData, dsc) {
    const parsedSampleRand = parseSampleRate(dsc?.sample_rand);
    if (parsedSampleRand !== void 0) {
      return parsedSampleRand;
    }
    const parsedSampleRate = parseSampleRate(dsc?.sample_rate);
    if (parsedSampleRate && traceparentData?.parentSampled !== void 0) {
      return traceparentData.parentSampled ? (
        // Returns a sample rand with positive sampling decision [0, sampleRate)
        safeMathRandom() * parsedSampleRate
      ) : (
        // Returns a sample rand with negative sampling decision [sampleRate, 1)
        parsedSampleRate + safeMathRandom() * (1 - parsedSampleRate)
      );
    } else {
      return safeMathRandom();
    }
  }
  function shouldContinueTrace(client, baggageOrgId) {
    const clientOrgId = extractOrgIdFromClient(client);
    if (baggageOrgId && clientOrgId && baggageOrgId !== clientOrgId) {
      debug.log(
        `Won't continue trace because org IDs don't match (incoming baggage: ${baggageOrgId}, SDK options: ${clientOrgId})`
      );
      return false;
    }
    const strictTraceContinuation = client.getOptions().strictTraceContinuation || false;
    if (strictTraceContinuation) {
      if (baggageOrgId && !clientOrgId || !baggageOrgId && clientOrgId) {
        debug.log(
          `Starting a new trace because strict trace continuation is enabled but one org ID is missing (incoming baggage: ${baggageOrgId}, Sentry client: ${clientOrgId})`
        );
        return false;
      }
    }
    return true;
  }

  const SCOPE_SPAN_FIELD = "span";
  function _setSpanForScope(scope, span) {
    if (span) {
      scope.refs[SCOPE_SPAN_FIELD] = makeWeakRef(span);
    } else {
      delete scope.refs[SCOPE_SPAN_FIELD];
    }
  }
  function _getSpanForScope(scope) {
    return derefWeakRef(scope.refs[SCOPE_SPAN_FIELD]);
  }

  const TRACE_FLAG_NONE = 0;
  const TRACE_FLAG_SAMPLED = 1;
  function spanToTransactionTraceContext(span) {
    const { spanId: span_id, traceId: trace_id } = span.spanContext();
    const { data, op, parent_span_id, status, origin, links } = spanToStaticSpanJSON(span);
    return {
      parent_span_id,
      span_id,
      trace_id,
      data,
      op,
      status,
      origin,
      links
    };
  }
  function spanToTraceContext(span) {
    const { spanId, traceId: trace_id, isRemote } = span.spanContext();
    const parent_span_id = isRemote ? spanId : spanToStaticSpanJSON(span).parent_span_id;
    const scope = getCapturedScopesOnSpan(span).scope;
    const span_id = isRemote ? scope?.getPropagationContext().propagationSpanId || generateSpanId() : spanId;
    return {
      parent_span_id,
      span_id,
      trace_id
    };
  }
  function spanToTraceHeader(span) {
    const { traceId, spanId } = span.spanContext();
    const sampled = spanIsSampled(span);
    return generateSentryTraceHeader(traceId, spanId, sampled);
  }
  function spanToTraceparentHeader(span) {
    const { traceId, spanId } = span.spanContext();
    const sampled = spanIsSampled(span);
    return generateTraceparentHeader(traceId, spanId, sampled);
  }
  function convertSpanLinksForEnvelope(links) {
    if (links && links.length > 0) {
      return links.map(({ context: { spanId, traceId, traceFlags, ...restContext }, attributes }) => ({
        span_id: spanId,
        trace_id: traceId,
        sampled: traceFlags === TRACE_FLAG_SAMPLED,
        attributes,
        ...restContext
      }));
    } else {
      return void 0;
    }
  }
  function getStreamedSpanLinks(links) {
    if (links?.length) {
      return links.map(({ context: { spanId, traceId, traceFlags }, attributes }) => ({
        span_id: spanId,
        trace_id: traceId,
        sampled: traceFlags === TRACE_FLAG_SAMPLED,
        attributes
      }));
    } else {
      return void 0;
    }
  }
  function spanTimeInputToSeconds(input) {
    if (typeof input === "number") {
      return ensureTimestampInSeconds(input);
    }
    if (Array.isArray(input)) {
      return input[0] + input[1] / 1e9;
    }
    if (input instanceof Date) {
      return ensureTimestampInSeconds(input.getTime());
    }
    return timestampInSeconds();
  }
  function ensureTimestampInSeconds(timestamp) {
    const isMs = timestamp > 9999999999;
    return isMs ? timestamp / 1e3 : timestamp;
  }
  function spanToStaticSpanJSON(span) {
    if (spanIsSentrySpan(span)) {
      return span.getStaticSpanJSON();
    }
    const { spanId: span_id, traceId: trace_id } = span.spanContext();
    if (spanIsOpenTelemetrySdkTraceBaseSpan(span)) {
      const { attributes, startTime, name, endTime, status, links } = span;
      return {
        span_id,
        trace_id,
        data: attributes,
        description: name,
        parent_span_id: getOtelParentSpanId(span),
        start_timestamp: spanTimeInputToSeconds(startTime),
        // This is [0,0] by default in OTEL, in which case we want to interpret this as no end time
        timestamp: spanTimeInputToSeconds(endTime) || void 0,
        status: getStatusMessage(status),
        op: attributes[SEMANTIC_ATTRIBUTE_SENTRY_OP],
        origin: attributes[SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN],
        links: convertSpanLinksForEnvelope(links)
      };
    }
    return {
      span_id,
      trace_id,
      start_timestamp: 0,
      status: "ok",
      data: {}
    };
  }
  function spanToJSON(span) {
    if (spanIsSentrySpan(span)) {
      return span.getSpanJSON();
    }
    const { spanId: span_id, traceId: trace_id } = span.spanContext();
    if (spanIsOpenTelemetrySdkTraceBaseSpan(span)) {
      const { attributes, startTime, name, endTime, status, links } = span;
      return {
        name,
        span_id,
        trace_id,
        parent_span_id: getOtelParentSpanId(span),
        start_timestamp: spanTimeInputToSeconds(startTime),
        // This is [0,0] by default in OTEL, in which case we want to interpret this as no end time
        end_timestamp: spanTimeInputToSeconds(endTime) || void 0,
        is_segment: spanIsSegment(span),
        status: getSimpleStatus(status),
        attributes: addStatusMessageAttribute(attributes, status),
        links: getStreamedSpanLinks(links)
      };
    }
    return {
      span_id,
      trace_id,
      start_timestamp: 0,
      name: "",
      status: "ok",
      is_segment: spanIsSegment(span),
      attributes: {}
    };
  }
  function getOtelParentSpanId(span) {
    return "parentSpanId" in span ? span.parentSpanId : "parentSpanContext" in span ? span.parentSpanContext?.spanId : void 0;
  }
  function streamedSpanJsonToSerializedSpan(spanJson) {
    return {
      ...spanJson,
      // We only ever send ended spans, but fall back to the start time (i.e. duration 0) so that
      // sent spans always carry an end timestamp.
      end_timestamp: spanJson.end_timestamp ?? spanJson.start_timestamp,
      attributes: serializeAttributes(spanJson.attributes),
      links: spanJson.links?.map((link) => ({
        ...link,
        attributes: serializeAttributes(link.attributes)
      }))
    };
  }
  function spanIsOpenTelemetrySdkTraceBaseSpan(span) {
    const castSpan = span;
    return !!castSpan.attributes && !!castSpan.startTime && !!castSpan.name && !!castSpan.endTime && !!castSpan.status;
  }
  function spanIsSentrySpan(span) {
    return typeof span.getSpanJSON === "function";
  }
  function spanIsSampled(span) {
    const { traceFlags } = span.spanContext();
    return traceFlags === TRACE_FLAG_SAMPLED;
  }
  function getStatusMessage(status) {
    if (!status || status.code === SPAN_STATUS_UNSET) {
      return "ok";
    }
    if (status.code === SPAN_STATUS_OK) {
      return "ok";
    }
    return status.message && isStatusErrorMessageValid(status.message) ? status.message : "internal_error";
  }
  function getSimpleStatus(status) {
    return !status || status.code === SPAN_STATUS_OK || status.code === SPAN_STATUS_UNSET || status.message === "cancelled" ? "ok" : "error";
  }
  function addStatusMessageAttribute(attributes, status) {
    const statusMessage = getSimpleStatus(status) === "error" ? status?.message : void 0;
    return {
      ...statusMessage && { [SEMANTIC_ATTRIBUTE_SENTRY_STATUS_MESSAGE]: statusMessage },
      ...attributes
    };
  }
  const CHILD_SPANS_FIELD = "_sentryChildSpans";
  const ROOT_SPAN_FIELD = "_sentryRootSpan";
  function addChildSpanToSpan(span, childSpan) {
    const rootSpan = span[ROOT_SPAN_FIELD] || span;
    addNonEnumerableProperty(childSpan, ROOT_SPAN_FIELD, rootSpan);
    childSpan.setAttribute(wd, void 0);
    if (!spanIsSampled(span)) {
      return;
    }
    if (!span.isRecording() && !rootSpan.isRecording()) {
      return;
    }
    if (span[CHILD_SPANS_FIELD]) {
      span[CHILD_SPANS_FIELD].add(childSpan);
    } else {
      addNonEnumerableProperty(span, CHILD_SPANS_FIELD, /* @__PURE__ */ new Set([childSpan]));
    }
  }
  function removeChildSpanFromSpan(span, childSpan) {
    if (span[CHILD_SPANS_FIELD]) {
      span[CHILD_SPANS_FIELD].delete(childSpan);
    }
  }
  function getSpanDescendants(span) {
    const resultSet = /* @__PURE__ */ new Set();
    function addSpanChildren(span2) {
      if (resultSet.has(span2)) {
        return;
      } else if (spanIsSampled(span2)) {
        resultSet.add(span2);
        const childSpans = span2[CHILD_SPANS_FIELD] ? Array.from(span2[CHILD_SPANS_FIELD]) : [];
        for (const childSpan of childSpans) {
          addSpanChildren(childSpan);
        }
      }
    }
    addSpanChildren(span);
    return Array.from(resultSet);
  }
  const getRootSpan = INTERNAL_getSegmentSpan;
  function INTERNAL_getSegmentSpan(span) {
    return span[ROOT_SPAN_FIELD] || span;
  }
  function spanIsSegment(span) {
    return span === INTERNAL_getSegmentSpan(span);
  }
  function getActiveSpan(scope) {
    const carrier = getMainCarrier();
    const acs = getAsyncContextStrategy(carrier);
    if (acs.getActiveSpan) {
      return acs.getActiveSpan(scope);
    }
    return _getSpanForScope(scope || getCurrentScope());
  }
  function updateSpanName(span, name) {
    span.updateName(name);
    span.setAttributes({
      [SEMANTIC_ATTRIBUTE_SENTRY_CUSTOM_SPAN_NAME]: name
    });
    INTERNAL_setSegmentNameSourceIfSegment(span, "custom");
  }
  function INTERNAL_setSegmentNameSourceIfSegment(span, source) {
    if (spanIsSegment(span)) {
      span.setAttribute(wd, source);
    }
  }

  let errorsInstrumented = false;
  function registerSpanErrorInstrumentation() {
    if (errorsInstrumented) {
      return;
    }
    function errorCallback() {
      const activeSpan = getActiveSpan();
      const rootSpan = activeSpan && getRootSpan(activeSpan);
      if (rootSpan) {
        const message = "internal_error";
        debug.log(`[Tracing] Root span: ${message} -> Global error occurred`);
        rootSpan.setStatus({ code: SPAN_STATUS_ERROR, message });
      }
    }
    errorsInstrumented = true;
    addGlobalErrorInstrumentationHandler(errorCallback);
    addGlobalUnhandledRejectionInstrumentationHandler(errorCallback);
  }

  function hasSpansEnabled(maybeOptions) {
    if (typeof __SENTRY_TRACING__ === "boolean" && !__SENTRY_TRACING__) {
      return false;
    }
    const options = maybeOptions || getClient()?.getOptions();
    return !!options && // Note: This check is `!= null`, meaning "nullish". `0` is not "nullish", `undefined` and `null` are. (This comment was brought to you by 15 minutes of questioning life)
    (options.tracesSampleRate != null || !!options.tracesSampler);
  }

  function logIgnoredSpan(droppedSpan) {
    debug.log(`Ignoring span ${droppedSpan.op} - ${droppedSpan.description} because it matches \`ignoreSpans\`.`);
  }
  function shouldIgnoreSpan(span, ignoreSpans) {
    if (!ignoreSpans?.length) {
      return false;
    }
    for (const pattern of ignoreSpans) {
      if (isStringOrRegExp(pattern)) {
        if (span.description && isMatchingPattern(span.description, pattern)) {
          logIgnoredSpan(span);
          return true;
        }
        continue;
      }
      const hasAttributes = !!pattern.attributes && Object.keys(pattern.attributes).length > 0;
      if (!pattern.name && !pattern.op && !hasAttributes) {
        continue;
      }
      const nameMatches = pattern.name ? span.description && isMatchingPattern(span.description, pattern.name) : true;
      const opMatches = pattern.op ? span.op && isMatchingPattern(span.op, pattern.op) : true;
      const attrsMatch = pattern.attributes ? Object.entries(pattern.attributes).every(
        ([key, valuePattern]) => _matchesAttributeValue(span.attributes?.[key], valuePattern)
      ) : true;
      if (nameMatches && opMatches && attrsMatch) {
        logIgnoredSpan(span);
        return true;
      }
    }
    return false;
  }
  function _matchesAttributeValue(actual, pat) {
    if (typeof actual === "string" && (typeof pat === "string" || pat instanceof RegExp)) {
      return isMatchingPattern(actual, pat);
    }
    if (Array.isArray(actual) && Array.isArray(pat)) {
      return actual.length === pat.length && actual.every((v, i) => v === pat[i]);
    }
    return actual === pat;
  }
  function reparentChildSpans(spans, dropSpan) {
    const droppedSpanParentId = dropSpan.parent_span_id;
    const droppedSpanId = dropSpan.span_id;
    if (!droppedSpanParentId) {
      return;
    }
    for (const span of spans) {
      if (span.parent_span_id === droppedSpanId) {
        span.parent_span_id = droppedSpanParentId;
      }
    }
  }
  function isStringOrRegExp(value) {
    return typeof value === "string" || value instanceof RegExp;
  }

  const installedIntegrations = [];
  function filterDuplicates(integrations) {
    const integrationsByName = {};
    integrations.forEach((currentInstance) => {
      const { name } = currentInstance;
      const existingInstance = integrationsByName[name];
      if (existingInstance && !existingInstance.isDefaultInstance && currentInstance.isDefaultInstance) {
        return;
      }
      integrationsByName[name] = currentInstance;
    });
    return Object.values(integrationsByName);
  }
  function getIntegrationsToSetup(options) {
    const defaultIntegrations = options.defaultIntegrations || [];
    const userIntegrations = options.integrations;
    defaultIntegrations.forEach((integration) => {
      integration.isDefaultInstance = true;
    });
    let integrations;
    if (Array.isArray(userIntegrations)) {
      integrations = [...defaultIntegrations, ...userIntegrations];
    } else if (typeof userIntegrations === "function") {
      const resolvedUserIntegrations = userIntegrations(defaultIntegrations);
      integrations = Array.isArray(resolvedUserIntegrations) ? resolvedUserIntegrations : [resolvedUserIntegrations];
    } else {
      integrations = defaultIntegrations;
    }
    return filterDuplicates(integrations);
  }
  function setupIntegrations(client, integrations) {
    const integrationIndex = {};
    integrations.forEach((integration) => {
      if (integration?.beforeSetup) {
        integration.beforeSetup(client);
      }
    });
    integrations.forEach((integration) => {
      if (integration) {
        setupIntegration(client, integration, integrationIndex);
      }
    });
    return integrationIndex;
  }
  function afterSetupIntegrations(client, integrations) {
    for (const integration of integrations) {
      if (integration?.afterAllSetup) {
        integration.afterAllSetup(client);
      }
    }
  }
  function setupIntegration(client, integration, integrationIndex) {
    if (integrationIndex[integration.name]) {
      debug.log(`Integration skipped because it was already installed: ${integration.name}`);
      return;
    }
    integrationIndex[integration.name] = integration;
    if (!installedIntegrations.includes(integration.name) && typeof integration.setupOnce === "function") {
      integration.setupOnce();
      installedIntegrations.push(integration.name);
    }
    if (integration.setup && typeof integration.setup === "function") {
      integration.setup(client);
    }
    if (typeof integration.preprocessEvent === "function") {
      const callback = integration.preprocessEvent.bind(integration);
      client.on("preprocessEvent", (event, hint) => callback(event, hint, client));
    }
    if (typeof integration.processEvent === "function") {
      const callback = integration.processEvent.bind(integration);
      const processor = Object.assign((event, hint) => callback(event, hint, client), {
        id: integration.name
      });
      client.addEventProcessor(processor);
    }
    ["processSpan", "processSegmentSpan"].forEach((hook) => {
      const callback = integration[hook];
      if (typeof callback === "function") {
        client.on(hook, (span) => callback.call(integration, span, client));
      }
    });
    debug.log(`Integration installed: ${integration.name}`);
  }
  function addIntegration(integration) {
    const client = getClient();
    if (!client) {
      debug.warn(`Cannot add integration "${integration.name}" because no SDK Client is available.`);
      return;
    }
    client.addIntegration(integration);
  }
  function defineIntegration(fn) {
    return fn;
  }

  const DEFAULT_ENVIRONMENT = "production";

  const NON_RECORDING_SPAN_FIELD = /* @__PURE__ */ Symbol.for("sentry.nonRecordingSpan");
  class SentryNonRecordingSpan {
    constructor(spanContext = {}) {
      this._traceId = spanContext.traceId || generateTraceId();
      this._spanId = spanContext.spanId || generateSpanId();
      this.dropReason = spanContext.dropReason;
      addNonEnumerableProperty(this, NON_RECORDING_SPAN_FIELD, true);
    }
    /** @inheritdoc */
    spanContext() {
      return {
        spanId: this._spanId,
        traceId: this._traceId,
        traceFlags: TRACE_FLAG_NONE
      };
    }
    /** @inheritdoc */
    end(_timestamp) {
    }
    /** @inheritdoc */
    setAttribute(_key, _value) {
      return this;
    }
    /** @inheritdoc */
    setAttributes(_values) {
      return this;
    }
    /** @inheritdoc */
    setStatus(_status) {
      return this;
    }
    /** @inheritdoc */
    updateName(_name) {
      return this;
    }
    /** @inheritdoc */
    isRecording() {
      return false;
    }
    /** @inheritdoc */
    addEvent(_name, _attributesOrStartTime, _startTime) {
      return this;
    }
    /** @inheritDoc */
    addLink(_link) {
      return this;
    }
    /** @inheritDoc */
    addLinks(_links) {
      return this;
    }
    /**
     * This should generally not be used,
     * but we need it for being compliant with the OTEL Span interface.
     *
     * @hidden
     * @internal
     */
    recordException(_exception, _time) {
    }
  }
  function spanIsNonRecordingSpan(span) {
    return !!span && span[NON_RECORDING_SPAN_FIELD] === true;
  }

  const FROZEN_DSC_FIELD = "_frozenDsc";
  function freezeDscOnSpan(span, dsc) {
    const spanWithMaybeDsc = span;
    addNonEnumerableProperty(spanWithMaybeDsc, FROZEN_DSC_FIELD, dsc);
  }
  function getDynamicSamplingContextFromClient(trace_id, client) {
    const options = client.getOptions();
    const { publicKey: public_key } = client.getDsn() || {};
    const dsc = {
      environment: options.environment || DEFAULT_ENVIRONMENT,
      release: options.release,
      public_key,
      trace_id,
      org_id: extractOrgIdFromClient(client)
    };
    client.emit("createDsc", dsc);
    return dsc;
  }
  function getDynamicSamplingContextFromScope(client, scope) {
    if (getExternalPropagationContext()) {
      return void 0;
    }
    const propagationContext = scope.getPropagationContext();
    return propagationContext.dsc || getDynamicSamplingContextFromClient(propagationContext.traceId, client);
  }
  function getDynamicSamplingContextFromSpan(span) {
    const client = getClient();
    if (!client) {
      return {};
    }
    const rootSpan = getRootSpan(span);
    const rootSpanJson = spanToStaticSpanJSON(rootSpan);
    const rootSpanAttributes = rootSpanJson.data;
    const traceState = rootSpan.spanContext().traceState;
    const rootSpanSampleRate = traceState?.get("sentry.sample_rate") ?? rootSpanAttributes[SEMANTIC_ATTRIBUTE_SENTRY_SAMPLE_RATE] ?? rootSpanAttributes[SEMANTIC_ATTRIBUTE_SENTRY_PREVIOUS_TRACE_SAMPLE_RATE];
    function applyLocalSampleRateToDsc(dsc2) {
      if (typeof rootSpanSampleRate === "number" || typeof rootSpanSampleRate === "string") {
        dsc2.sample_rate = `${rootSpanSampleRate}`;
      }
      return dsc2;
    }
    const frozenDsc = rootSpan[FROZEN_DSC_FIELD];
    if (frozenDsc) {
      return applyLocalSampleRateToDsc(frozenDsc);
    }
    const isNonRecordingRoot = spanIsNonRecordingSpan(rootSpan);
    const isIgnoredRoot = isNonRecordingRoot && rootSpan.dropReason === "ignored";
    if (isNonRecordingRoot && (!hasSpansEnabled(client.getOptions()) || isIgnoredRoot)) {
      const capturedScope = getCapturedScopesOnSpan(rootSpan).scope;
      const scopeDsc = capturedScope && getDynamicSamplingContextFromScope(client, capturedScope);
      if (scopeDsc) {
        const dsc2 = { ...scopeDsc };
        if (isIgnoredRoot) {
          dsc2.sampled = "false";
        }
        return applyLocalSampleRateToDsc(dsc2);
      }
    }
    const traceStateDsc = traceState?.get("sentry.dsc");
    const dscOnTraceState = traceStateDsc && baggageHeaderToDynamicSamplingContext(traceStateDsc);
    if (dscOnTraceState) {
      return applyLocalSampleRateToDsc(dscOnTraceState);
    }
    const dsc = getDynamicSamplingContextFromClient(span.spanContext().traceId, client);
    const source = rootSpanAttributes[wd];
    const name = rootSpanJson.description;
    if (source !== "url" && name) {
      dsc.transaction = name;
    }
    if (hasSpansEnabled()) {
      dsc.sampled = String(spanIsSampled(rootSpan));
      dsc.sample_rand = // In OTEL we store the sample rand on the trace state because we cannot access scopes for NonRecordingSpans
      // The Sentry OTEL SpanSampler takes care of writing the sample rand on the root span
      traceState?.get("sentry.sample_rand") ?? // On all other platforms we can actually get the scopes from a root span (we use this as a fallback)
      getCapturedScopesOnSpan(rootSpan).scope?.getPropagationContext().sampleRand.toString();
    }
    applyLocalSampleRateToDsc(dsc);
    client.emit("createDsc", dsc, rootSpan);
    return dsc;
  }
  function spanToBaggageHeader(span) {
    const dsc = getDynamicSamplingContextFromSpan(span);
    return dynamicSamplingContextToSentryBaggageHeader(dsc);
  }

  function applyScopeDataToEvent(event, data) {
    const { fingerprint, breadcrumbs, sdkProcessingMetadata } = data;
    applyDataToEvent(event, data);
    applyFingerprintToEvent(event, fingerprint);
    applyBreadcrumbsToEvent(event, breadcrumbs);
    applySdkMetadataToEvent(event, sdkProcessingMetadata);
  }
  function mergeScopeData(data, mergeData) {
    const {
      extra,
      tags,
      attributes,
      user,
      contexts,
      level,
      sdkProcessingMetadata,
      breadcrumbs,
      fingerprint,
      eventProcessors,
      attachments,
      propagationContext,
      transactionName
    } = mergeData;
    mergeAndOverwriteScopeData(data, "extra", extra);
    mergeAndOverwriteScopeData(data, "tags", tags);
    mergeAndOverwriteScopeData(data, "attributes", attributes);
    mergeAndOverwriteScopeData(data, "user", user);
    mergeAndOverwriteScopeData(data, "contexts", contexts);
    data.sdkProcessingMetadata = merge(data.sdkProcessingMetadata, sdkProcessingMetadata, 2);
    if (level) {
      data.level = level;
    }
    if (transactionName) {
      data.transactionName = transactionName;
    }
    if (breadcrumbs.length) {
      data.breadcrumbs = [...data.breadcrumbs, ...breadcrumbs];
    }
    if (fingerprint.length) {
      data.fingerprint = [...data.fingerprint, ...fingerprint];
    }
    if (eventProcessors.length) {
      data.eventProcessors = [...data.eventProcessors, ...eventProcessors];
    }
    if (attachments.length) {
      data.attachments = [...data.attachments, ...attachments];
    }
    data.propagationContext = { ...data.propagationContext, ...propagationContext };
  }
  function mergeAndOverwriteScopeData(data, prop, mergeVal) {
    data[prop] = merge(data[prop], mergeVal, 1);
  }
  function getCombinedScopeData(isolationScope, currentScope) {
    const scopeData = getGlobalScope().getScopeData();
    isolationScope && mergeScopeData(scopeData, isolationScope.getScopeData());
    currentScope && mergeScopeData(scopeData, currentScope.getScopeData());
    return scopeData;
  }
  function applyDataToEvent(event, data) {
    const { extra, tags, user, contexts, level, transactionName } = data;
    if (Object.keys(extra).length) {
      event.extra = { ...extra, ...event.extra };
    }
    if (Object.keys(tags).length) {
      event.tags = { ...tags, ...event.tags };
    }
    if (Object.keys(user).length) {
      event.user = { ...user, ...event.user };
    }
    if (Object.keys(contexts).length) {
      event.contexts = { ...contexts, ...event.contexts };
    }
    if (level) {
      event.level = level;
    }
    if (transactionName && event.type !== "transaction") {
      event.transaction = transactionName;
    }
  }
  function applyBreadcrumbsToEvent(event, breadcrumbs) {
    const mergedBreadcrumbs = [...event.breadcrumbs || [], ...breadcrumbs];
    event.breadcrumbs = mergedBreadcrumbs.length ? mergedBreadcrumbs : void 0;
  }
  function applySdkMetadataToEvent(event, sdkProcessingMetadata) {
    event.sdkProcessingMetadata = {
      ...event.sdkProcessingMetadata,
      ...sdkProcessingMetadata
    };
  }
  function applySpanToEvent(event, span) {
    event.contexts = {
      trace: spanToTraceContext(span),
      ...event.contexts
    };
    event.sdkProcessingMetadata = {
      dynamicSamplingContext: getDynamicSamplingContextFromSpan(span),
      ...event.sdkProcessingMetadata
    };
    const rootSpan = getRootSpan(span);
    const transactionName = spanToStaticSpanJSON(rootSpan).description;
    if (transactionName && !event.transaction && event.type === "transaction") {
      event.transaction = transactionName;
    }
  }
  function applyFingerprintToEvent(event, fingerprint) {
    event.fingerprint = event.fingerprint ? Array.isArray(event.fingerprint) ? event.fingerprint : [event.fingerprint] : [];
    if (fingerprint) {
      event.fingerprint = event.fingerprint.concat(fingerprint);
    }
    if (!event.fingerprint.length) {
      delete event.fingerprint;
    }
  }

  function safeCallback(message, fn, fallback) {
    let result;
    try {
      result = fn();
    } catch (error) {
      return recover(message, error, fallback);
    }
    if (isThenable(result)) {
      return result.then(void 0, (error) => recover(message, error, fallback));
    }
    return result;
  }
  function recover(message, error, fallback) {
    debug.error(message, error);
    return fallback(error);
  }

  function withStaticSpan(callback) {
    addNonEnumerableProperty(callback, "_static", true);
    return callback;
  }
  function withStreamedSpan(callback) {
    return callback;
  }
  function isStaticBeforeSendSpanCallback(callback) {
    return !!callback && typeof callback === "function" && "_static" in callback && !!callback._static;
  }
  let hasShownSpanDropWarning = false;
  function applyBeforeSendSpanCallback(span, beforeSendSpan) {
    const modifiedSpan = safeCallback(
      "The `beforeSendSpan` callback threw an error, sending the span unmodified:" ,
      () => beforeSendSpan(span),
      () => span
    );
    if (modifiedSpan) {
      return modifiedSpan;
    }
    if (!hasShownSpanDropWarning) {
      consoleSandbox(() => {
        console.warn(
          "[Sentry] Returning null from `beforeSendSpan` is disallowed. To drop certain spans, configure the respective integrations directly or use `ignoreSpans`."
        );
      });
      hasShownSpanDropWarning = true;
    }
    return span;
  }

  function spanJsonToSerializedStreamedSpan(span) {
    const streamedSpan = {
      trace_id: span.trace_id,
      span_id: span.span_id,
      parent_span_id: span.parent_span_id,
      name: span.description || "",
      start_timestamp: span.start_timestamp,
      end_timestamp: span.timestamp,
      status: !span.status || span.status === "ok" || span.status === "cancelled" ? "ok" : "error",
      is_segment: false,
      attributes: { ...span.data },
      links: span.links
    };
    return streamedSpanJsonToSerializedSpan(streamedSpan);
  }

  function scopeContextsToSpanAttributes(contexts) {
    const attrs = {};
    const { response, profile, cloud_resource, culture, state } = contexts;
    if (response) {
      if (response.status_code != null) {
        attrs["http.response.status_code"] = response.status_code;
      }
      if (response.body_size != null) {
        attrs["http.response.body.size"] = response.body_size;
      }
    }
    if (profile) {
      if (profile.profile_id) {
        attrs["sentry.profile_id"] = profile.profile_id;
      }
      if (profile.profiler_id) {
        attrs["sentry.profiler_id"] = profile.profiler_id;
      }
    }
    if (cloud_resource) {
      for (const [key, value] of Object.entries(cloud_resource)) {
        if (value != null) {
          attrs[key] = value;
        }
      }
    }
    if (culture) {
      if (culture.locale) {
        attrs["culture.locale"] = culture.locale;
      }
      if (culture.timezone) {
        attrs["culture.timezone"] = culture.timezone;
      }
    }
    if (state?.state && typeof state.state.type === "string") {
      attrs["state.type"] = state.state.type;
    }
    const angular = contexts["angular"];
    if (angular) {
      const version = angular["version"];
      if (typeof version === "string" || typeof version === "number") {
        attrs["angular.version"] = version;
      }
    }
    const react = contexts["react"];
    if (react) {
      const version = react["version"];
      if (typeof version === "string" || typeof version === "number") {
        attrs["react.version"] = version;
      }
    }
    return attrs;
  }

  function captureSpan(span, client) {
    const spanJSON = spanToJSON(span);
    const segmentSpan = INTERNAL_getSegmentSpan(span);
    const serializedSegmentSpan = spanToJSON(segmentSpan);
    const { isolationScope: spanIsolationScope, scope: spanScope } = getCapturedScopesOnSpan(span);
    const finalScopeData = getCombinedScopeData(spanIsolationScope, spanScope);
    applyCommonSpanAttributes(spanJSON, serializedSegmentSpan, client, finalScopeData);
    client.emit("preprocessSpan", spanJSON);
    if (spanJSON.is_segment) {
      applyScopeToSegmentSpan(spanJSON, finalScopeData);
      applySdkMetadataToSegmentSpan(spanJSON, client);
      client.emit("processSegmentSpan", spanJSON);
    }
    client.emit("processSpan", spanJSON);
    const { beforeSendSpan, traceLifecycle } = client.getOptions();
    const processedSpan = (
      // check for traceLifecycle here because in static lifecycle,
      // captureSpan is called for INP spans. If an unmigrated beforeSendSpan
      // callback is run on these spans, it will throw an error.
      traceLifecycle !== "static" && beforeSendSpan && !isStaticBeforeSendSpanCallback(beforeSendSpan) ? applyBeforeSendSpanCallback(spanJSON, beforeSendSpan) : spanJSON
    );
    return {
      ...streamedSpanJsonToSerializedSpan(processedSpan),
      _segmentSpan: segmentSpan
    };
  }
  function applyScopeToSegmentSpan(segmentSpanJSON, scopeData) {
    const contextAttributes = scopeContextsToSpanAttributes(scopeData.contexts);
    safeSetSpanJSONAttributes(segmentSpanJSON, contextAttributes);
  }
  function safeSetSpanJSONAttributes(spanJSON, newAttributes) {
    const originalAttributes = spanJSON.attributes ?? (spanJSON.attributes = {});
    Object.entries(newAttributes).forEach(([key, value]) => {
      if (value != null && !(key in originalAttributes)) {
        originalAttributes[key] = value;
      }
    });
  }
  function applySdkMetadataToSegmentSpan(segmentSpanJSON, client) {
    const integrationNames = client.getIntegrationNames();
    if (!integrationNames.length) return;
    safeSetSpanJSONAttributes(segmentSpanJSON, {
      [SEMANTIC_ATTRIBUTE_SENTRY_SDK_INTEGRATIONS]: integrationNames
    });
  }
  function commonSpanAttributes(serializedSegmentSpan, client, scopeData, includeScopeAttributes = true) {
    const sdk = client.getSdkMetadata();
    const { release, environment } = client.getOptions();
    return {
      [zd]: "stream",
      [Ad]: serializedSegmentSpan.name,
      [Id]: serializedSegmentSpan.span_id,
      [Td]: sdk?.sdk?.name,
      [Ed]: sdk?.sdk?.version,
      [SEMANTIC_ATTRIBUTE_SENTRY_RELEASE]: release,
      [SEMANTIC_ATTRIBUTE_SENTRY_ENVIRONMENT]: environment || DEFAULT_ENVIRONMENT,
      [SEMANTIC_ATTRIBUTE_USER_ID]: scopeData.user?.id,
      [SEMANTIC_ATTRIBUTE_USER_EMAIL]: scopeData.user?.email,
      [SEMANTIC_ATTRIBUTE_USER_IP_ADDRESS]: scopeData.user?.ip_address,
      [SEMANTIC_ATTRIBUTE_USER_USERNAME]: scopeData.user?.username,
      ...includeScopeAttributes ? scopeData.attributes : void 0
    };
  }
  function applyCommonSpanAttributes(spanJSON, serializedSegmentSpan, client, scopeData) {
    safeSetSpanJSONAttributes(spanJSON, commonSpanAttributes(serializedSegmentSpan, client, scopeData));
  }
  function captureStandaloneSpanWithStaticCallback(span, client, beforeSendSpan) {
    const spanJSON = spanToStaticSpanJSON(span);
    const segmentSpan = INTERNAL_getSegmentSpan(span);
    const serializedSegmentSpan = spanToJSON(segmentSpan);
    const { isolationScope: spanIsolationScope, scope: spanScope } = getCapturedScopesOnSpan(span);
    const finalScopeData = getCombinedScopeData(spanIsolationScope, spanScope);
    const commonAttributes = commonSpanAttributes(serializedSegmentSpan, client, finalScopeData, false);
    Object.entries(commonAttributes).forEach(([key, value]) => {
      if (value != null && !(key in spanJSON.data)) {
        spanJSON.data[key] = value;
      }
    });
    const processedSpan = applyBeforeSendSpanCallback(spanJSON, beforeSendSpan);
    return spanJsonToSerializedStreamedSpan(processedSpan);
  }

  function hasSpanStreamingEnabled(client) {
    return client.getOptions().traceLifecycle === "stream";
  }

  function safeUnref(timer) {
    if (typeof timer === "object" && typeof timer.unref === "function") {
      timer.unref();
    }
    return timer;
  }

  function createEnvelope(headers, items = []) {
    return [headers, items];
  }
  function addItemToEnvelope(envelope, newItem) {
    const [headers, items] = envelope;
    return [headers, [...items, newItem]];
  }
  function forEachEnvelopeItem(envelope, callback) {
    const envelopeItems = envelope[1];
    for (const envelopeItem of envelopeItems) {
      const envelopeItemType = envelopeItem[0].type;
      const result = callback(envelopeItem, envelopeItemType);
      if (result) {
        return true;
      }
    }
    return false;
  }
  function envelopeContainsItemType(envelope, types) {
    return forEachEnvelopeItem(envelope, (_, type) => types.includes(type));
  }
  function encodeUTF8(input) {
    const carrier = getSentryCarrier(GLOBAL_OBJ);
    return carrier.encodePolyfill ? carrier.encodePolyfill(input) : new TextEncoder().encode(input);
  }
  function serializeEnvelope(envelope) {
    const [envHeaders, items] = envelope;
    let parts = JSON.stringify(envHeaders);
    function append(next) {
      if (typeof parts === "string") {
        parts = typeof next === "string" ? parts + next : [encodeUTF8(parts), next];
      } else {
        parts.push(typeof next === "string" ? encodeUTF8(next) : next);
      }
    }
    for (const item of items) {
      const [itemHeaders, payload] = item;
      append(`
${JSON.stringify(itemHeaders)}
`);
      if (typeof payload === "string" || payload instanceof Uint8Array) {
        append(payload);
      } else {
        let stringifiedPayload;
        try {
          stringifiedPayload = JSON.stringify(payload);
        } catch {
          stringifiedPayload = JSON.stringify(normalize(payload));
        }
        append(stringifiedPayload);
      }
    }
    return typeof parts === "string" ? parts : concatBuffers(parts);
  }
  function concatBuffers(buffers) {
    const totalLength = buffers.reduce((acc, buf) => acc + buf.length, 0);
    const merged = new Uint8Array(totalLength);
    let offset = 0;
    for (const buffer of buffers) {
      merged.set(buffer, offset);
      offset += buffer.length;
    }
    return merged;
  }
  function createAttachmentEnvelopeItem(attachment) {
    const buffer = typeof attachment.data === "string" ? encodeUTF8(attachment.data) : attachment.data;
    return [
      {
        type: "attachment",
        length: buffer.length,
        filename: attachment.filename,
        content_type: attachment.contentType,
        attachment_type: attachment.attachmentType
      },
      buffer
    ];
  }
  const DATA_CATEGORY_OVERRIDES = {
    sessions: "session",
    event: "error",
    client_report: "internal",
    user_report: "default",
    profile_chunk: "profile",
    replay_event: "replay",
    replay_recording: "replay",
    check_in: "monitor",
    raw_security: "security",
    log: "log_item",
    trace_metric: "metric"
  };
  function _isOverriddenType(type) {
    return type in DATA_CATEGORY_OVERRIDES;
  }
  function envelopeItemTypeToDataCategory(type) {
    return _isOverriddenType(type) ? DATA_CATEGORY_OVERRIDES[type] : type;
  }
  function getSdkMetadataForEnvelopeHeader(metadataOrEvent) {
    if (!metadataOrEvent?.sdk) {
      return;
    }
    const { name, version } = metadataOrEvent.sdk;
    return { name, version };
  }
  function createEventEnvelopeHeaders(event, sdkInfo, tunnel, dsn) {
    const dynamicSamplingContext = event.sdkProcessingMetadata?.dynamicSamplingContext;
    return {
      event_id: event.event_id,
      sent_at: new Date(safeDateNow()).toISOString(),
      ...sdkInfo && { sdk: sdkInfo },
      ...!!tunnel && dsn && { dsn: dsnToString(dsn) },
      ...dynamicSamplingContext && {
        trace: dynamicSamplingContext
      }
    };
  }
  function getDataCategoryByType(type) {
    return type === "replay_event" ? "replay" : type || "error";
  }

  function getSDKSource() {
    return "cdn";
  }

  function isBrowser() {
    return typeof window !== "undefined" && (true);
  }

  function createStreamedSpanEnvelope(serializedSpans, dsc, client) {
    const options = client.getOptions();
    const dsn = client.getDsn();
    const tunnel = options.tunnel;
    const sdk = getSdkMetadataForEnvelopeHeader(options._metadata);
    const headers = {
      sent_at: new Date(safeDateNow()).toISOString(),
      ...dscHasRequiredProps(dsc) && { trace: dsc },
      ...sdk && { sdk },
      ...!!tunnel && dsn && { dsn: dsnToString(dsn) }
    };
    return createEnvelope(headers, [createSpanContainerItem(serializedSpans, client)]);
  }
  function createSpanContainerItem(serializedSpans, client) {
    const inferSetting = client.getDataCollectionOptions().userInfo ? "auto" : "never";
    return [
      { type: "span", item_count: serializedSpans.length, content_type: "application/vnd.sentry.items.span.v2+json" },
      {
        version: 2,
        ingest_settings: isBrowser() ? { infer_ip: inferSetting, infer_user_agent: inferSetting } : void 0,
        items: serializedSpans
      }
    ];
  }
  function dscHasRequiredProps(dsc) {
    return !!dsc.trace_id && !!dsc.public_key;
  }

  function estimateSerializedSpanSizeInBytes(span) {
    let weight = 156;
    weight += span.name.length * 2;
    weight += estimateTypedAttributesSizeInBytes(span.attributes);
    if (span.links && span.links.length > 0) {
      const firstLink = span.links[0];
      const attributes = firstLink?.attributes;
      const linkWeight = 100 + (attributes ? estimateTypedAttributesSizeInBytes(attributes) : 0);
      weight += linkWeight * span.links.length;
    }
    return weight;
  }

  const MAX_SPANS_PER_ENVELOPE = 1e3;
  const MAX_TRACE_WEIGHT_IN_BYTES = 5e6;
  class SpanBuffer {
    constructor(client, options) {
      this._traceBuckets = /* @__PURE__ */ new Map();
      this._client = client;
      const { maxSpanLimit, flushInterval, maxTraceWeightInBytes } = options ?? {};
      this._maxSpanLimit = maxSpanLimit && maxSpanLimit > 0 && maxSpanLimit <= MAX_SPANS_PER_ENVELOPE ? maxSpanLimit : MAX_SPANS_PER_ENVELOPE;
      this._flushInterval = flushInterval && flushInterval > 0 ? flushInterval : 5e3;
      this._maxTraceWeight = maxTraceWeightInBytes && maxTraceWeightInBytes > 0 ? maxTraceWeightInBytes : MAX_TRACE_WEIGHT_IN_BYTES;
      this._client.on("flush", () => {
        this.drain();
      });
      this._client.on("close", () => {
        this._traceBuckets.forEach((bucket) => {
          clearTimeout(bucket.timeout);
        });
        this._traceBuckets.clear();
      });
    }
    /**
     * Add a span to the buffer.
     */
    add(spanJSON) {
      const traceId = spanJSON.trace_id;
      let bucket = this._traceBuckets.get(traceId);
      if (!bucket) {
        bucket = {
          spans: /* @__PURE__ */ new Set(),
          size: 0,
          timeout: safeUnref(
            setTimeout(() => {
              this.flush(traceId);
            }, this._flushInterval)
          )
        };
        this._traceBuckets.set(traceId, bucket);
      }
      bucket.spans.add(spanJSON);
      bucket.size += estimateSerializedSpanSizeInBytes(spanJSON);
      if (bucket.spans.size >= this._maxSpanLimit || bucket.size >= this._maxTraceWeight) {
        this.flush(traceId);
      }
    }
    /**
     * Drain and flush all buffered traces.
     */
    drain() {
      if (!this._traceBuckets.size) {
        return;
      }
      debug.log(`Flushing span tree map with ${this._traceBuckets.size} traces`);
      this._traceBuckets.forEach((_, traceId) => {
        this.flush(traceId);
      });
    }
    /**
     * Flush spans of a specific trace.
     * In contrast to {@link SpanBuffer.drain}, this method does not flush all traces, but only the one with the given traceId.
     */
    flush(traceId) {
      const bucket = this._traceBuckets.get(traceId);
      if (!bucket) {
        return;
      }
      if (!bucket.spans.size) {
        this._removeTrace(traceId);
        return;
      }
      const spans = Array.from(bucket.spans);
      const segmentSpan = spans[0]?._segmentSpan;
      if (!segmentSpan) {
        debug.warn("No segment span reference found on span JSON, cannot compute DSC");
        this._removeTrace(traceId);
        return;
      }
      const dsc = getDynamicSamplingContextFromSpan(segmentSpan);
      const cleanedSpans = spans.map((spanJSON) => {
        const { _segmentSpan, ...cleanSpanJSON } = spanJSON;
        return cleanSpanJSON;
      });
      const envelope = createStreamedSpanEnvelope(cleanedSpans, dsc, this._client);
      debug.log(`Sending span envelope for trace ${traceId} with ${cleanedSpans.length} spans`);
      this._client.sendEnvelope(envelope).then(null, (reason) => {
        debug.error("Error while sending streamed span envelope:", reason);
      });
      this._removeTrace(traceId);
    }
    _removeTrace(traceId) {
      const bucket = this._traceBuckets.get(traceId);
      if (bucket) {
        clearTimeout(bucket.timeout);
      }
      this._traceBuckets.delete(traceId);
    }
  }

  const INTEGRATION_NAME$a = "SpanStreaming";
  const spanStreamingIntegration = defineIntegration((options = {}) => {
    const flushOnSegmentEnd = options.flushOnSegmentEnd ?? true;
    return {
      name: INTEGRATION_NAME$a,
      setup(client) {
        if (!hasSpanStreamingEnabled(client)) {
          debug.log(`[${INTEGRATION_NAME$a}] \`traceLifecycle\` is "static", skipping setup.`);
          return;
        }
        const buffer = new SpanBuffer(client);
        client.on("afterSpanEnd", (span) => {
          if (!spanIsSampled(span)) {
            return;
          }
          buffer.add(captureSpan(span, client));
        });
        client.on("flushTraceSpans", (traceId) => {
          buffer.flush(traceId);
        });
        if (flushOnSegmentEnd) {
          client.on("afterSegmentSpanEnd", (segmentSpan) => {
            const traceId = segmentSpan.spanContext().traceId;
            safeUnref(
              setTimeout(() => {
                buffer.flush(traceId);
              }, 500)
            );
          });
        }
      }
    };
  });

  function handleCallbackErrors(fn, onError, onFinally = () => {
  }, onSuccess = () => {
  }) {
    let maybePromiseResult;
    try {
      maybePromiseResult = fn();
    } catch (e) {
      onError(e);
      onFinally();
      throw e;
    }
    return maybeHandlePromiseRejection(maybePromiseResult, onError, onFinally, onSuccess);
  }
  function maybeHandlePromiseRejection(value, onError, onFinally, onSuccess) {
    if (isThenable(value)) {
      return chainAndCopyPromiseLike(
        value,
        (result) => {
          onFinally();
          onSuccess(result);
        },
        (err) => {
          onError(err);
          onFinally();
        }
      );
    }
    onFinally();
    onSuccess(value);
    return value;
  }

  const escapedSpanTraceContexts = /* @__PURE__ */ new WeakMap();
  function toWeakMapKey(error) {
    return isPrimitive(error) ? void 0 : error;
  }
  function recordEscapedErrorSpan(error, span) {
    const key = toWeakMapKey(error);
    if (!key || !spanIsSampled(span) || escapedSpanTraceContexts.has(key)) {
      return;
    }
    escapedSpanTraceContexts.set(key, spanToTraceContext(span));
  }
  function applyEscapedErrorSpanToEvent(event, hint, scope) {
    const key = toWeakMapKey(hint.originalException);
    const traceContext = key && escapedSpanTraceContexts.get(key);
    if (!traceContext) {
      return;
    }
    const eventTraceContext = event.contexts?.trace;
    const eventTraceId = eventTraceContext?.trace_id ?? (scope && getTraceContextFromScope(scope).trace_id);
    if (eventTraceId !== traceContext.trace_id) {
      return;
    }
    event.contexts = {
      ...event.contexts,
      trace: {
        ...eventTraceContext,
        ...traceContext
      }
    };
  }

  function logSpanStart(span) {
    const {
      description = "< unknown name >",
      op = "< unknown op >",
      parent_span_id: parentSpanId
    } = spanToStaticSpanJSON(span);
    const { spanId } = span.spanContext();
    const sampled = spanIsSampled(span);
    const rootSpan = getRootSpan(span);
    const isRootSpan = rootSpan === span;
    const header = `[Tracing] Starting ${sampled ? "sampled" : "unsampled"} ${isRootSpan ? "root " : ""}span`;
    const infoParts = [`op: ${op}`, `name: ${description}`, `ID: ${spanId}`];
    if (parentSpanId) {
      infoParts.push(`parent ID: ${parentSpanId}`);
    }
    if (!isRootSpan) {
      const { op: op2, description: description2 } = spanToStaticSpanJSON(rootSpan);
      infoParts.push(`root ID: ${rootSpan.spanContext().spanId}`);
      if (op2) {
        infoParts.push(`root op: ${op2}`);
      }
      if (description2) {
        infoParts.push(`root description: ${description2}`);
      }
    }
    debug.log(`${header}
  ${infoParts.join("\n  ")}`);
  }
  function logSpanEnd(span) {
    const { description = "< unknown name >", op = "< unknown op >" } = spanToStaticSpanJSON(span);
    const { spanId } = span.spanContext();
    const rootSpan = getRootSpan(span);
    const isRootSpan = rootSpan === span;
    const msg = `[Tracing] Finishing "${op}" ${isRootSpan ? "root " : ""}span "${description}" with ID ${spanId}`;
    debug.log(msg);
  }

  function sampleSpan(options, samplingContext, sampleRand) {
    if (!hasSpansEnabled(options)) {
      return [false];
    }
    const resolved = resolveSampleRate(options, samplingContext);
    if (!resolved) {
      return [false, void 0, void 0, "callback_error"];
    }
    const [sampleRate, localSampleRateWasApplied] = resolved;
    const parsedSampleRate = parseSampleRate(sampleRate);
    if (parsedSampleRate === void 0) {
      debug.warn(
        `[Tracing] Discarding root span because of invalid sample rate. Sample rate must be a boolean or a number between 0 and 1. Got ${JSON.stringify(
        sampleRate
      )} of type ${JSON.stringify(typeof sampleRate)}.`
      );
      return [false];
    }
    if (!parsedSampleRate) {
      debug.log(
        `[Tracing] Discarding transaction because ${typeof options.tracesSampler === "function" ? "tracesSampler returned 0 or false" : "a negative sampling decision was inherited or tracesSampleRate is set to 0"}`
      );
      return [false, parsedSampleRate, localSampleRateWasApplied];
    }
    const shouldSample = sampleRand < parsedSampleRate;
    if (!shouldSample) {
      debug.log(
        `[Tracing] Discarding transaction because it's not included in the random sample (sampling rate = ${Number(
        sampleRate
      )})`
      );
    }
    return [shouldSample, parsedSampleRate, localSampleRateWasApplied];
  }
  function resolveSampleRate(options, samplingContext) {
    const { tracesSampler, tracesSampleRate } = options;
    if (typeof tracesSampler === "function") {
      const samplerResult = safeCallback(
        "The `tracesSampler` callback threw an error, falling back to the parent sampling decision or `tracesSampleRate`:" ,
        () => [
          tracesSampler({
            ...samplingContext,
            inheritOrSampleWith: (fallbackSampleRate) => {
              if (typeof samplingContext.parentSampleRate === "number") {
                return samplingContext.parentSampleRate;
              }
              if (typeof samplingContext.parentSampled === "boolean") {
                return Number(samplingContext.parentSampled);
              }
              return fallbackSampleRate;
            }
          }),
          true
        ],
        () => void 0
      );
      if (samplerResult) {
        return samplerResult;
      }
    }
    if (samplingContext.parentSampled !== void 0) {
      return [samplingContext.parentSampled];
    }
    if (typeof tracesSampleRate !== "undefined") {
      return [tracesSampleRate, true];
    }
    return void 0;
  }

  function setMeasurement(name, value, unit, activeSpan = getActiveSpan()) {
    const rootSpan = activeSpan && getRootSpan(activeSpan);
    if (rootSpan) {
      debug.log(`[Measurement] Setting measurement on root span: ${name} = ${value} ${unit}`);
      rootSpan.addEvent(name, {
        [SEMANTIC_ATTRIBUTE_SENTRY_MEASUREMENT_VALUE]: value,
        [SEMANTIC_ATTRIBUTE_SENTRY_MEASUREMENT_UNIT]: unit
      });
    }
  }
  function timedEventsToMeasurements(events) {
    if (!events || events.length === 0) {
      return void 0;
    }
    const measurements = {};
    events.forEach((event) => {
      const attributes = event.attributes || {};
      const unit = attributes[SEMANTIC_ATTRIBUTE_SENTRY_MEASUREMENT_UNIT];
      const value = attributes[SEMANTIC_ATTRIBUTE_SENTRY_MEASUREMENT_VALUE];
      if (typeof unit === "string" && typeof value === "number") {
        measurements[event.name] = { value, unit };
      }
    });
    return measurements;
  }

  function getSegmentSpanCaptureStrategy() {
    return getSentryCarrier(getMainCarrier()).segmentSpanCaptureStrategy;
  }

  const MAX_SPAN_COUNT = 1e3;
  class SentrySpan {
    /**
     * You should never call the constructor manually, always use `Sentry.startSpan()`
     * or other span methods.
     * @internal
     * @hideconstructor
     * @hidden
     */
    constructor(spanContext = {}) {
      this._traceId = spanContext.traceId || generateTraceId();
      this._spanId = spanContext.spanId || generateSpanId();
      this._startTime = spanContext.startTimestamp || timestampInSeconds();
      this._links = spanContext.links;
      this._attributes = {};
      this.setAttributes({
        [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "manual",
        [SEMANTIC_ATTRIBUTE_SENTRY_OP]: spanContext.op,
        ...spanContext.attributes
      });
      this._name = spanContext.name;
      if (spanContext.parentSpanId) {
        this._parentSpanId = spanContext.parentSpanId;
      }
      if ("sampled" in spanContext) {
        this._sampled = spanContext.sampled;
      }
      this._events = [];
      this._isStandaloneSpan = spanContext.isStandalone;
    }
    /** @inheritDoc */
    addLink(link) {
      if (this._frozen) {
        return this;
      }
      if (this._links) {
        this._links.push(link);
      } else {
        this._links = [link];
      }
      return this;
    }
    /** @inheritDoc */
    addLinks(links) {
      if (this._frozen) {
        return this;
      }
      if (this._links) {
        this._links.push(...links);
      } else {
        this._links = links;
      }
      return this;
    }
    /**
     * This should generally not be used,
     * but it is needed for being compliant with the OTEL Span interface.
     *
     * @hidden
     * @internal
     */
    recordException(_exception, _time) {
    }
    /** @inheritdoc */
    spanContext() {
      const { _spanId: spanId, _traceId: traceId, _sampled: sampled } = this;
      return {
        spanId,
        traceId,
        traceFlags: sampled ? TRACE_FLAG_SAMPLED : TRACE_FLAG_NONE
      };
    }
    /** @inheritdoc */
    setAttribute(key, value) {
      if (this._frozen) {
        return this;
      }
      if (key === wd && value !== void 0 && !spanIsSegment(this)) {
        debug.warn("[Tracing] Ignoring name source on a child span: this attribute is only valid on the root span.");
        return this;
      }
      if (value === void 0) {
        delete this._attributes[key];
      } else {
        this._attributes[key] = value;
      }
      return this;
    }
    /** @inheritdoc */
    setAttributes(attributes) {
      Object.keys(attributes).forEach((key) => this.setAttribute(key, attributes[key]));
      return this;
    }
    /**
     * This should generally not be used,
     * but we need it for browser tracing where we want to adjust the start time afterwards.
     * USE THIS WITH CAUTION!
     *
     * @hidden
     * @internal
     */
    updateStartTime(timeInput) {
      if (this._frozen) {
        return;
      }
      this._startTime = spanTimeInputToSeconds(timeInput);
    }
    /**
     * @inheritDoc
     */
    setStatus(value) {
      if (this._frozen) {
        return this;
      }
      this._status = value;
      return this;
    }
    /**
     * @inheritDoc
     */
    updateName(name) {
      if (this._frozen) {
        return this;
      }
      this._name = name;
      INTERNAL_setSegmentNameSourceIfSegment(this, "custom");
      return this;
    }
    /** @inheritdoc */
    end(endTimestamp) {
      if (this._endTime) {
        return;
      }
      this._endTime = spanTimeInputToSeconds(endTimestamp);
      logSpanEnd(this);
      this._onSpanEnded();
      this._frozen = spanIsTracerProviderSpan(this);
    }
    /**
     * Get JSON representation of this span.
     *
     * @hidden
     * @internal This method is purely for internal purposes and should not be used outside
     * of SDK code. If you need to get a JSON representation of a span,
     * use `spanToJSON(span)` instead.
     */
    getStaticSpanJSON() {
      return {
        data: this._attributes,
        description: this._name,
        op: this._attributes[SEMANTIC_ATTRIBUTE_SENTRY_OP],
        parent_span_id: this._parentSpanId,
        span_id: this._spanId,
        start_timestamp: this._startTime,
        status: getStatusMessage(this._status),
        timestamp: this._endTime,
        trace_id: this._traceId,
        origin: this._attributes[SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN],
        profile_id: this._attributes[SEMANTIC_ATTRIBUTE_PROFILE_ID],
        exclusive_time: this._attributes[SEMANTIC_ATTRIBUTE_EXCLUSIVE_TIME],
        measurements: timedEventsToMeasurements(this._events),
        links: convertSpanLinksForEnvelope(this._links)
      };
    }
    /**
     * Get {@link StreamedSpanJSON} representation of this span.
     *
     * @hidden
     * @internal This method is purely for internal purposes and should not be used outside
     * of SDK code. If you need to get a JSON representation of a span,
     * use `spanToJSON(span)` instead.
     */
    getSpanJSON() {
      return {
        name: this._name ?? "",
        span_id: this._spanId,
        trace_id: this._traceId,
        parent_span_id: this._parentSpanId,
        start_timestamp: this._startTime,
        end_timestamp: this._endTime,
        is_segment: spanIsSegment(this),
        status: getSimpleStatus(this._status),
        attributes: addStatusMessageAttribute(this._attributes, this._status),
        links: getStreamedSpanLinks(this._links)
      };
    }
    /** @inheritdoc */
    isRecording() {
      return !this._endTime && !!this._sampled;
    }
    /**
     * @inheritdoc
     */
    addEvent(name, attributesOrStartTime, startTime) {
      if (this._frozen) {
        return this;
      }
      debug.log("[Tracing] Adding an event to span:", name);
      const time = isSpanTimeInput(attributesOrStartTime) ? attributesOrStartTime : startTime || timestampInSeconds();
      const attributes = isSpanTimeInput(attributesOrStartTime) ? {} : attributesOrStartTime || {};
      const event = {
        name,
        time: spanTimeInputToSeconds(time),
        attributes
      };
      this._events.push(event);
      return this;
    }
    /**
     * Whether this span is sent on its own (as a v2 streamed span) rather than as part of a
     * transaction. Used internally; see `_isStandaloneSpan`.
     * @internal
     */
    isStandaloneSpan() {
      return !!this._isStandaloneSpan;
    }
    /** Emit `spanEnd` when the span is ended. */
    _onSpanEnded() {
      const client = getClient();
      client?.emit("spanEnd", this);
      if (this._isStandaloneSpan) {
        if (!client) return;
        if (this._sampled) {
          sendStandaloneSpan(this, client);
          return;
        }
        debug.log("[Tracing] Discarding standalone span because its trace was not chosen to be sampled.");
        client.recordDroppedEvent("sample_rate", "span");
        return;
      }
      client?.emit("afterSpanEnd", this);
      const rootSpan = getRootSpan(this);
      if (rootSpan !== this) {
        const strategy2 = getSegmentSpanCaptureStrategy();
        if (strategy2) {
          const scope2 = getCapturedScopesOnSpan(this).scope || getCurrentScope();
          strategy2.onChildSpanEnded(this, rootSpan, (options) => this._convertSpanToTransaction(options), scope2);
        }
        return;
      }
      if (client && hasSpanStreamingEnabled(client)) {
        client.emit("afterSegmentSpanEnd", this);
        return;
      }
      const scope = getCapturedScopesOnSpan(this).scope || getCurrentScope();
      const strategy = getSegmentSpanCaptureStrategy();
      if (strategy) {
        strategy.onSegmentSpanEnded((options) => this._convertSpanToTransaction(options), scope);
      } else {
        const transactionEvent = this._convertSpanToTransaction();
        if (transactionEvent) {
          scope.captureEvent(transactionEvent);
        }
      }
    }
    /**
     * Finish the transaction & prepare the event to send to Sentry.
     */
    _convertSpanToTransaction(options = {}) {
      if (!isFullFinishedSpan(spanToStaticSpanJSON(this))) {
        return void 0;
      }
      if (!this._name) {
        debug.warn("Transaction has no name, falling back to `<unlabeled transaction>`.");
        this._name = "<unlabeled transaction>";
      }
      const { scope: capturedSpanScope, isolationScope: capturedSpanIsolationScope } = getCapturedScopesOnSpan(this);
      const normalizedRequest = capturedSpanScope?.getScopeData().sdkProcessingMetadata?.normalizedRequest;
      if (this._sampled !== true) {
        return void 0;
      }
      options.onSpanCaptured?.(this);
      const spans = [];
      for (const descendant of getSpanDescendants(this)) {
        if (descendant === this || isStandaloneSpan(descendant) || options.isSpanAlreadyCaptured?.(descendant)) {
          continue;
        }
        const spanJSON = spanToStaticSpanJSON(descendant);
        if (!isFullFinishedSpan(spanJSON)) {
          continue;
        }
        options.onSpanCaptured?.(descendant);
        spans.push(spanJSON);
      }
      const source = this._attributes[wd];
      delete this._attributes[SEMANTIC_ATTRIBUTE_SENTRY_CUSTOM_SPAN_NAME];
      let hasGenAiSpans = false;
      spans.forEach((span) => {
        delete span.data[SEMANTIC_ATTRIBUTE_SENTRY_CUSTOM_SPAN_NAME];
        if (span.op?.startsWith("gen_ai.")) {
          hasGenAiSpans = true;
        }
      });
      const transaction = {
        contexts: {
          trace: spanToTransactionTraceContext(this)
        },
        spans: (
          // spans.sort() mutates the array, but `spans` is already a copy so we can safely do this here
          // we do not use spans anymore after this point
          spans.length > MAX_SPAN_COUNT ? spans.sort((a, b) => a.start_timestamp - b.start_timestamp).slice(0, MAX_SPAN_COUNT) : spans
        ),
        start_timestamp: this._startTime,
        timestamp: this._endTime,
        transaction: this._name,
        type: "transaction",
        sdkProcessingMetadata: {
          capturedSpanScope,
          capturedSpanIsolationScope,
          dynamicSamplingContext: getDynamicSamplingContextFromSpan(this),
          hasGenAiSpans
        },
        request: normalizedRequest,
        ...source && {
          transaction_info: {
            source
          }
        }
      };
      const measurements = timedEventsToMeasurements(this._events);
      const hasMeasurements = measurements && Object.keys(measurements).length;
      if (hasMeasurements) {
        debug.log(
          "[Measurements] Adding measurements to transaction event",
          JSON.stringify(measurements, void 0, 2)
        );
        transaction.measurements = measurements;
      }
      return transaction;
    }
  }
  function isSpanTimeInput(value) {
    return value && typeof value === "number" || value instanceof Date || Array.isArray(value);
  }
  function isFullFinishedSpan(input) {
    return !!input.start_timestamp && !!input.timestamp && !!input.span_id && !!input.trace_id;
  }
  function isStandaloneSpan(span) {
    return span instanceof SentrySpan && span.isStandaloneSpan();
  }
  function sendStandaloneSpan(span, client) {
    const { beforeSendSpan, traceLifecycle } = client.getOptions();
    if (traceLifecycle === "static" && isStaticBeforeSendSpanCallback(beforeSendSpan)) {
      const serializedSpan2 = captureStandaloneSpanWithStaticCallback(span, client, beforeSendSpan);
      const dsc2 = getDynamicSamplingContextFromSpan(span);
      client.sendEnvelope(createStreamedSpanEnvelope([serializedSpan2], dsc2, client));
      return;
    }
    const { _segmentSpan, ...serializedSpan } = captureSpan(span, client);
    const dsc = getDynamicSamplingContextFromSpan(_segmentSpan);
    client.sendEnvelope(createStreamedSpanEnvelope([serializedSpan], dsc, client));
  }

  function startSpan$1(options, callback) {
    const spanArguments = parseSentrySpanArguments(options);
    const { forceTransaction, parentSpan: customParentSpan, scope: customScope } = options;
    const customForkedScope = customScope?.clone();
    return withScope(customForkedScope, () => {
      const wrapper = getActiveSpanWrapper(customParentSpan);
      return wrapper(() => {
        const scope = getCurrentScope();
        const parentSpan = getParentSpan(customScope ?? scope, customParentSpan);
        const client = getClient();
        const missingRequiredParent = options.onlyIfParent && !parentSpan;
        const activeSpan = missingRequiredParent ? startMissingRequiredParentSpan(scope, client) : createChildOrRootSpan({
          parentSpan,
          spanArguments,
          forceTransaction,
          scope
        });
        const makeSpanActive = !spanIsIgnored(activeSpan) || !parentSpan;
        return runCallback(
          activeSpan,
          makeSpanActive,
          () => callback(activeSpan),
          () => activeSpan.end()
        );
      });
    });
  }
  function startSpanManual$1(options, callback) {
    const spanArguments = parseSentrySpanArguments(options);
    const { forceTransaction, parentSpan: customParentSpan, scope: customScope } = options;
    const customForkedScope = customScope?.clone();
    return withScope(customForkedScope, () => {
      const wrapper = getActiveSpanWrapper(customParentSpan);
      return wrapper(() => {
        const scope = getCurrentScope();
        const parentSpan = getParentSpan(customScope ?? scope, customParentSpan);
        const missingRequiredParent = options.onlyIfParent && !parentSpan;
        const activeSpan = missingRequiredParent ? startMissingRequiredParentSpan(scope, getClient()) : createChildOrRootSpan({
          parentSpan,
          spanArguments,
          forceTransaction,
          scope
        });
        const makeSpanActive = !spanIsIgnored(activeSpan) || !parentSpan;
        return runCallback(activeSpan, makeSpanActive, () => callback(activeSpan, () => activeSpan.end()));
      });
    });
  }
  function startInactiveSpan$1(options) {
    const spanArguments = parseSentrySpanArguments(options);
    const { forceTransaction, parentSpan: customParentSpan, scope: customScope } = options;
    const wrapper = customScope ? (callback) => withScope(customScope, callback) : customParentSpan !== void 0 ? (callback) => withActiveSpan(customParentSpan, callback) : (callback) => callback();
    return wrapper(() => {
      const scope = getCurrentScope();
      const parentSpan = getParentSpan(customScope ?? scope, customParentSpan);
      const client = getClient();
      const missingRequiredParent = options.onlyIfParent && !parentSpan;
      if (missingRequiredParent) {
        return startMissingRequiredParentSpan(scope, client);
      }
      return createChildOrRootSpan({
        parentSpan,
        spanArguments,
        forceTransaction,
        scope
      });
    });
  }
  const continueTrace = (options, callback) => {
    const carrier = getMainCarrier();
    const acs = getAsyncContextStrategy(carrier);
    if (acs.continueTrace) {
      return acs.continueTrace(options, callback);
    }
    const { sentryTrace, baggage } = options;
    const client = getClient();
    const incomingDsc = baggageHeaderToDynamicSamplingContext(baggage);
    if (client && !shouldContinueTrace(client, incomingDsc?.org_id)) {
      return startNewTrace(callback);
    }
    return withScope((scope) => {
      const propagationContext = propagationContextFromHeaders(sentryTrace, baggage);
      scope.setPropagationContext(propagationContext);
      return withActiveSpan(null, callback);
    });
  };
  function withActiveSpan(span, callback) {
    const acs = getAcs();
    if (acs.withActiveSpan) {
      return acs.withActiveSpan(span, callback);
    }
    return withScope((scope) => {
      _setSpanForScope(scope, span || void 0);
      return callback(scope);
    });
  }
  function suppressTracing(callback) {
    const acs = getAcs();
    if (acs.suppressTracing) {
      return acs.suppressTracing(callback);
    }
    return withScope((scope) => {
      scope.setSDKProcessingMetadata({ [SUPPRESS_TRACING_KEY]: true });
      return callback();
    });
  }
  function isTracingSuppressed(scope = getCurrentScope()) {
    const acs = getAcs();
    if (acs.isTracingSuppressed) {
      return acs.isTracingSuppressed(scope);
    }
    return scope.getScopeData().sdkProcessingMetadata[SUPPRESS_TRACING_KEY] === true;
  }
  function startNewTrace(callback) {
    const acs = getAcs();
    if (acs.startNewTrace) {
      return acs.startNewTrace(callback);
    }
    return withActiveSpan(null, () => {
      return withScope((scope) => {
        scope.setPropagationContext({
          traceId: generateTraceId(),
          sampleRand: safeMathRandom()
        });
        debug.log(`Starting a new trace with id ${scope.getPropagationContext().traceId}`);
        return callback();
      });
    });
  }
  function startMissingRequiredParentSpan(scope, client) {
    client?.recordDroppedEvent("no_parent_span", "span");
    const span = new SentryNonRecordingSpan({ traceId: scope.getPropagationContext().traceId });
    setCapturedScopesOnSpan(span, scope, getIsolationScope());
    return span;
  }
  function createChildOrRootSpan({
    parentSpan: resolvedParentSpan,
    spanArguments,
    forceTransaction,
    scope: currentScope
  }) {
    const isolationScope = getIsolationScope();
    const spanScope = {
      scope: currentScope,
      parentSpan: resolvedParentSpan
    };
    getClient()?.emit("prepareSpanScope", spanScope);
    const { scope, parentSpan } = spanScope;
    if (!hasSpansEnabled()) {
      const scopePropagationContext = scope.getPropagationContext();
      const traceId = parentSpan ? parentSpan.spanContext().traceId : scopePropagationContext.traceId;
      const span2 = new SentryNonRecordingSpan({ traceId });
      if (parentSpan && !forceTransaction) {
        addChildSpanToSpan(parentSpan, span2);
      }
      setCapturedScopesOnSpan(span2, scope, isolationScope);
      return span2;
    }
    const client = getClient();
    if (_shouldIgnoreStreamedSpan(client, spanArguments)) {
      if (!isTracingSuppressed(scope)) {
        client?.recordDroppedEvent("ignored", "span");
      }
      const ignoredSpan = new SentryNonRecordingSpan({
        dropReason: "ignored",
        traceId: parentSpan?.spanContext().traceId ?? scope.getPropagationContext().traceId
      });
      if (parentSpan && !forceTransaction) {
        addChildSpanToSpan(parentSpan, ignoredSpan);
      }
      setCapturedScopesOnSpan(ignoredSpan, scope, isolationScope);
      return ignoredSpan;
    }
    let span;
    if (parentSpan && !forceTransaction) {
      span = _startChildSpan(parentSpan, scope, spanArguments, isolationScope);
      addChildSpanToSpan(parentSpan, span);
    } else if (parentSpan) {
      const dsc = getDynamicSamplingContextFromSpan(parentSpan);
      const { traceId, spanId: parentSpanId } = parentSpan.spanContext();
      const parentSampled = spanIsSampled(parentSpan);
      span = _startRootSpan(
        {
          traceId,
          parentSpanId,
          ...spanArguments
        },
        scope,
        isolationScope,
        parentSampled
      );
      freezeDscOnSpan(span, dsc);
    } else {
      const { traceId, dsc, parentSpanId, sampled: parentSampled, sampleRand } = scope.getPropagationContext();
      span = _startRootSpan(
        {
          traceId,
          parentSpanId,
          ...spanArguments
        },
        scope,
        isolationScope,
        parentSampled
      );
      if (dsc) {
        const dscWithSampleRand = Object.keys(dsc).length === 0 && sampleRand !== void 0 ? { sample_rand: sampleRand.toString() } : dsc;
        freezeDscOnSpan(span, dscWithSampleRand);
      }
    }
    logSpanStart(span);
    return span;
  }
  function parseSentrySpanArguments(options) {
    const initialCtx = {
      // TODO(standalone): remove once the static (transaction) trace lifecycle is dropped.
      // oxlint-disable-next-line typescript/no-deprecated
      isStandalone: options.experimental?.standalone,
      ...options
    };
    if (options.op) {
      initialCtx.attributes = {
        [SEMANTIC_ATTRIBUTE_SENTRY_OP]: options.op,
        ...options.attributes
      };
    }
    if (options.startTime) {
      const ctx = { ...initialCtx };
      ctx.startTimestamp = spanTimeInputToSeconds(options.startTime);
      delete ctx.startTime;
      return ctx;
    }
    return initialCtx;
  }
  function getAcs() {
    const carrier = getMainCarrier();
    return getAsyncContextStrategy(carrier);
  }
  function _startRootSpan(spanArguments, scope, isolationScope, parentSampled) {
    const client = getClient();
    const options = client?.getOptions() || {};
    const { name = "" } = spanArguments;
    const mutableSpanSamplingData = { spanAttributes: { ...spanArguments.attributes }, spanName: name, parentSampled };
    client?.emit("beforeSampling", mutableSpanSamplingData, { decision: false });
    const finalParentSampled = mutableSpanSamplingData.parentSampled ?? parentSampled;
    const finalAttributes = mutableSpanSamplingData.spanAttributes;
    const currentPropagationContext = scope.getPropagationContext();
    const _isTracingSuppressed = isTracingSuppressed(scope);
    const [sampled, sampleRate, localSampleRateWasApplied, dropReason] = _isTracingSuppressed ? [false] : sampleSpan(
      options,
      {
        name,
        parentSampled: finalParentSampled,
        attributes: finalAttributes,
        normalizedRequest: isolationScope.getScopeData().sdkProcessingMetadata.normalizedRequest,
        parentSampleRate: parseSampleRate(currentPropagationContext.dsc?.sample_rate)
      },
      currentPropagationContext.sampleRand
    );
    const rootSpan = new SentrySpan({
      ...spanArguments,
      attributes: {
        [wd]: "custom",
        [SEMANTIC_ATTRIBUTE_SENTRY_SAMPLE_RATE]: sampleRate !== void 0 && localSampleRateWasApplied ? sampleRate : void 0,
        ...finalAttributes
      },
      sampled
    });
    if (!sampled && client && !_isTracingSuppressed) {
      debug.log("[Tracing] Discarding root span because its trace was not chosen to be sampled.");
      client.recordDroppedEvent(dropReason || "sample_rate", hasSpanStreamingEnabled(client) ? "span" : "transaction");
    }
    setCapturedScopesOnSpan(rootSpan, scope, isolationScope);
    if (client) {
      client.emit("spanStart", rootSpan);
    }
    return rootSpan;
  }
  function _startChildSpan(parentSpan, scope, spanArguments, isolationScope) {
    const { spanId, traceId } = parentSpan.spanContext();
    const _isTracingSuppressed = isTracingSuppressed(scope);
    const sampled = _isTracingSuppressed ? false : spanIsSampled(parentSpan);
    const childSpan = sampled ? new SentrySpan({
      ...spanArguments,
      parentSpanId: spanId,
      traceId,
      sampled
    }) : new SentryNonRecordingSpan({ traceId });
    addChildSpanToSpan(parentSpan, childSpan);
    setCapturedScopesOnSpan(childSpan, scope, isolationScope);
    const client = getClient();
    if (!client) {
      return childSpan;
    }
    if (hasSpanStreamingEnabled(client) && spanIsNonRecordingSpan(childSpan)) {
      if (spanIsNonRecordingSpan(parentSpan) && parentSpan.dropReason) {
        childSpan.dropReason = parentSpan.dropReason;
        client.recordDroppedEvent(parentSpan.dropReason, "span");
      } else if (!_isTracingSuppressed) {
        childSpan.dropReason = "sample_rate";
        client.recordDroppedEvent("sample_rate", "span");
      }
    }
    client.emit("spanStart", childSpan);
    return childSpan;
  }
  function getParentSpan(scope, customParentSpan) {
    if (customParentSpan) {
      return customParentSpan;
    }
    if (customParentSpan === null) {
      return void 0;
    }
    const span = getActiveSpan(scope);
    if (!span) {
      return void 0;
    }
    const client = getClient();
    const options = client ? client.getOptions() : {};
    if (options.parentSpanIsAlwaysRootSpan) {
      return getRootSpan(span);
    }
    return span;
  }
  function getActiveSpanWrapper(parentSpan) {
    return parentSpan !== void 0 ? (callback) => {
      return withActiveSpan(parentSpan, callback);
    } : (callback) => callback();
  }
  function _shouldIgnoreStreamedSpan(client, spanArguments) {
    const ignoreSpans = client?.getOptions().ignoreSpans;
    if (!client || !hasSpanStreamingEnabled(client) || !ignoreSpans?.length) {
      return false;
    }
    return shouldIgnoreSpan(
      {
        description: spanArguments.name || "",
        op: spanArguments.attributes?.[SEMANTIC_ATTRIBUTE_SENTRY_OP] || spanArguments.op,
        attributes: spanArguments.attributes
      },
      ignoreSpans
    );
  }
  function spanIsIgnored(span) {
    return spanIsNonRecordingSpan(span) && span.dropReason === "ignored";
  }
  function runCallback(span, makeSpanActive, callback, finallyCallback) {
    const wrapper = makeSpanActive ? (callback2) => {
      return withActiveSpan(span, () => {
        const scope = getCurrentScope();
        const creationScope = getCapturedScopesOnSpan(span).scope;
        if (creationScope) {
          scope.setPropagationContext(creationScope.getPropagationContext());
        }
        setCapturedScopesOnSpan(span, scope, getIsolationScope());
        return callback2();
      });
    } : (callback2) => callback2();
    return wrapper(
      () => handleCallbackErrors(
        () => callback(),
        (error) => {
          recordEscapedErrorSpan(error, span);
          const { status } = spanToStaticSpanJSON(span);
          if (span.isRecording() && status === "ok") {
            span.setStatus({ code: SPAN_STATUS_ERROR, message: "internal_error" });
          }
        },
        finallyCallback
      )
    );
  }

  const clientsWithIntegration = /* @__PURE__ */ new WeakSet();
  function _INTERNAL_ensureBrowserSpanStreaming(client = getClient()) {
    if (!client || clientsWithIntegration.has(client) || !hasSpanStreamingEnabled(client)) {
      return;
    }
    clientsWithIntegration.add(client);
    client.addIntegration(spanStreamingIntegration());
  }
  function startSpan(options, callback) {
    _INTERNAL_ensureBrowserSpanStreaming();
    return startSpan$1(options, callback);
  }
  function startSpanManual(options, callback) {
    _INTERNAL_ensureBrowserSpanStreaming();
    return startSpanManual$1(options, callback);
  }
  function startInactiveSpan(options) {
    _INTERNAL_ensureBrowserSpanStreaming();
    return startInactiveSpan$1(options);
  }

  const TRACING_DEFAULTS = {
    idleTimeout: 1e3,
    finalTimeout: 3e4,
    childSpanTimeout: 15e3
  };
  const FINISH_REASON_HEARTBEAT_FAILED = "heartbeatFailed";
  const FINISH_REASON_IDLE_TIMEOUT = "idleTimeout";
  const FINISH_REASON_FINAL_TIMEOUT = "finalTimeout";
  const FINISH_REASON_EXTERNAL_FINISH = "externalFinish";
  function startIdleSpan(startSpanOptions, options = {}) {
    const client = getClient();
    _INTERNAL_ensureBrowserSpanStreaming(client);
    const activities = /* @__PURE__ */ new Map();
    let _finished = false;
    let _idleTimeoutID;
    let _childSpanTimeoutID;
    let _finishReason = FINISH_REASON_EXTERNAL_FINISH;
    let _autoFinishAllowed = !options.disableAutoFinish;
    const _cleanupHooks = [];
    const {
      idleTimeout = TRACING_DEFAULTS.idleTimeout,
      finalTimeout = TRACING_DEFAULTS.finalTimeout,
      childSpanTimeout = TRACING_DEFAULTS.childSpanTimeout,
      trimIdleSpanEndTimestamp = true
    } = options;
    const scope = getCurrentScope();
    if (!client || !hasSpansEnabled()) {
      const span2 = new SentryNonRecordingSpan({ traceId: scope.getPropagationContext().traceId });
      setCapturedScopesOnSpan(span2, scope, getIsolationScope());
      return span2;
    }
    const previousActiveSpan = getActiveSpan();
    const span = startInactiveSpan$1(startSpanOptions);
    _setSpanForScope(getCurrentScope(), span);
    debug.log("[Tracing] Started span is an idle span");
    span.end = new Proxy(span.end, {
      apply(target, thisArg, args) {
        client.emit("beforeIdleSpanEnd", span);
        if (spanIsNonRecordingSpan(thisArg)) {
          return;
        }
        const [definedEndTimestamp, ...rest] = args;
        const timestamp = definedEndTimestamp || timestampInSeconds();
        const spanEndTimestamp = spanTimeInputToSeconds(timestamp);
        const spans = getSpanDescendants(span).filter((child) => child !== span);
        const spanJson = spanToStaticSpanJSON(span);
        if (!spans.length || !trimIdleSpanEndTimestamp) {
          onIdleSpanEnded(spanEndTimestamp);
          return Reflect.apply(target, thisArg, [spanEndTimestamp, ...rest]);
        }
        const ignoreSpans = client.getOptions().ignoreSpans;
        const latestSpanEndTimestamp = spans?.reduce((acc, current) => {
          const currentSpanJson = spanToStaticSpanJSON(current);
          if (!currentSpanJson.timestamp) {
            return acc;
          }
          if (ignoreSpans && shouldIgnoreSpan(
            { description: currentSpanJson.description, op: currentSpanJson.op, attributes: currentSpanJson.data },
            ignoreSpans
          )) {
            return acc;
          }
          return acc ? Math.max(acc, currentSpanJson.timestamp) : currentSpanJson.timestamp;
        }, void 0);
        const spanStartTimestamp = spanJson.start_timestamp;
        const endTimestamp = Math.min(
          spanStartTimestamp ? spanStartTimestamp + finalTimeout / 1e3 : Infinity,
          Math.max(spanStartTimestamp || -Infinity, Math.min(spanEndTimestamp, latestSpanEndTimestamp || Infinity))
        );
        onIdleSpanEnded(endTimestamp);
        return Reflect.apply(target, thisArg, [endTimestamp, ...rest]);
      }
    });
    function _cancelIdleTimeout() {
      if (_idleTimeoutID) {
        clearTimeout(_idleTimeoutID);
        _idleTimeoutID = void 0;
      }
    }
    function _cancelChildSpanTimeout() {
      if (_childSpanTimeoutID) {
        clearTimeout(_childSpanTimeoutID);
        _childSpanTimeoutID = void 0;
      }
    }
    function _restartIdleTimeout(endTimestamp) {
      _cancelIdleTimeout();
      _idleTimeoutID = setTimeout(() => {
        if (!_finished && activities.size === 0 && _autoFinishAllowed) {
          _finishReason = FINISH_REASON_IDLE_TIMEOUT;
          span.end(endTimestamp);
        }
      }, idleTimeout);
    }
    function _restartChildSpanTimeout(endTimestamp) {
      _cancelChildSpanTimeout();
      _childSpanTimeoutID = setTimeout(() => {
        if (!_finished && _autoFinishAllowed) {
          _finishReason = FINISH_REASON_HEARTBEAT_FAILED;
          span.end(endTimestamp);
        }
      }, childSpanTimeout);
    }
    function _pushActivity(spanId) {
      _cancelIdleTimeout();
      activities.set(spanId, true);
      const endTimestamp = timestampInSeconds();
      _restartChildSpanTimeout(endTimestamp + childSpanTimeout / 1e3);
    }
    function _popActivity(spanId) {
      if (activities.has(spanId)) {
        activities.delete(spanId);
      }
      if (activities.size === 0) {
        const endTimestamp = timestampInSeconds();
        _restartIdleTimeout(endTimestamp + idleTimeout / 1e3);
        _cancelChildSpanTimeout();
      }
    }
    function onIdleSpanEnded(endTimestamp) {
      _finished = true;
      activities.clear();
      _cleanupHooks.forEach((cleanup) => cleanup());
      _setSpanForScope(scope, previousActiveSpan);
      const spanJSON = spanToStaticSpanJSON(span);
      const { start_timestamp: startTimestamp } = spanJSON;
      if (!startTimestamp) {
        return;
      }
      const attributes = spanJSON.data;
      if (!attributes[SEMANTIC_ATTRIBUTE_SENTRY_IDLE_SPAN_FINISH_REASON]) {
        span.setAttribute(SEMANTIC_ATTRIBUTE_SENTRY_IDLE_SPAN_FINISH_REASON, _finishReason);
      }
      const currentStatus = spanJSON.status;
      if (!currentStatus || currentStatus === "unknown") {
        span.setStatus({ code: SPAN_STATUS_OK });
      }
      debug.log(`[Tracing] Idle span "${spanJSON.op}" finished`);
      const childSpans = getSpanDescendants(span).filter((child) => child !== span);
      let discardedSpans = 0;
      childSpans.forEach((childSpan) => {
        if (childSpan.isRecording()) {
          childSpan.setStatus({ code: SPAN_STATUS_ERROR, message: "cancelled" });
          childSpan.end(endTimestamp);
          debug.log("[Tracing] Cancelling span since span ended early", JSON.stringify(childSpan, void 0, 2));
        }
        const childSpanJSON = spanToStaticSpanJSON(childSpan);
        const { timestamp: childEndTimestamp = 0, start_timestamp: childStartTimestamp = 0 } = childSpanJSON;
        const spanStartedBeforeIdleSpanEnd = childStartTimestamp <= endTimestamp;
        const timeoutWithMarginOfError = (finalTimeout + idleTimeout) / 1e3;
        const spanEndedBeforeFinalTimeout = childEndTimestamp - childStartTimestamp <= timeoutWithMarginOfError;
        {
          const stringifiedSpan = JSON.stringify(childSpan, void 0, 2);
          if (!spanStartedBeforeIdleSpanEnd) {
            debug.log("[Tracing] Discarding span since it happened after idle span was finished", stringifiedSpan);
          } else if (!spanEndedBeforeFinalTimeout) {
            debug.log("[Tracing] Discarding span since it finished after idle span final timeout", stringifiedSpan);
          }
        }
        if (!spanEndedBeforeFinalTimeout || !spanStartedBeforeIdleSpanEnd) {
          removeChildSpanFromSpan(span, childSpan);
          discardedSpans++;
        }
      });
      if (discardedSpans > 0) {
        span.setAttribute("sentry.idle_span_discarded_spans", discardedSpans);
      }
    }
    _cleanupHooks.push(
      client.on("spanStart", (startedSpan) => {
        if (_finished || startedSpan === span || !!spanToJSON(startedSpan).end_timestamp || startedSpan instanceof SentrySpan && startedSpan.isStandaloneSpan()) {
          return;
        }
        const allSpans = getSpanDescendants(span);
        if (allSpans.includes(startedSpan)) {
          _pushActivity(startedSpan.spanContext().spanId);
        }
      })
    );
    _cleanupHooks.push(
      client.on("spanEnd", (endedSpan) => {
        if (_finished) {
          return;
        }
        _popActivity(endedSpan.spanContext().spanId);
      })
    );
    _cleanupHooks.push(
      client.on("idleSpanEnableAutoFinish", (spanToAllowAutoFinish) => {
        if (spanToAllowAutoFinish === span) {
          _autoFinishAllowed = true;
          _restartIdleTimeout();
          if (activities.size) {
            _restartChildSpanTimeout();
          }
        }
      })
    );
    if (!options.disableAutoFinish) {
      _restartIdleTimeout();
    }
    setTimeout(() => {
      if (!_finished) {
        span.setStatus({ code: SPAN_STATUS_ERROR, message: "deadline_exceeded" });
        _finishReason = FINISH_REASON_FINAL_TIMEOUT;
        span.end();
      }
    }, finalTimeout);
    return span;
  }

  const e$1="pageload",E$1="navigation",_$1="navigation.redirect",o$1="resource.other",s$1="browser.paint",S$1="browser.unload_event",l$1="browser.redirect",p$1="browser.dom_content_loaded_event",L$1="browser.load_event",P$1="browser.connect",b$1="browser.tls_ssl",d$1="browser.cache",B$1="browser.dns",D$1="browser.request",m$1="browser.response",W$1="ui.long_task",h$1="ui.long_animation_frame",v$1="ui.interaction.click",H$1="ui.interaction.hover",V="ui.interaction.drag",k$1="ui.interaction.press",K="ui.webvital.lcp",f$1="ui.webvital.cls",rE="http.client",RE="http.client.stream";

  const PAGELOAD_SPAN_NAME_FALLBACK = "Pageload";
  const NAVIGATION_SPAN_NAME_FALLBACK = "Navigation";
  const RESOURCE_SPAN_NAME_FALLBACK = "Resource";
  const UI_LONG_TASK_SPAN_NAME_FALLBACK = "Main UI thread blocked";
  const UI_INTERACTION_CLICK_SPAN_NAME_FALLBACK = "Click";
  const UI_INTERACTION_HOVER_SPAN_NAME_FALLBACK = "Hover";
  const UI_INTERACTION_DRAG_SPAN_NAME_FALLBACK = "Drag";
  const UI_INTERACTION_PRESS_SPAN_NAME_FALLBACK = "Key press";
  const UI_WEBVITAL_LCP_SPAN_NAME_FALLBACK = "Largest contentful paint";
  const UI_WEBVITAL_CLS_SPAN_NAME_FALLBACK = "Layout shift";
  const BROWSER_NAVIGATION_TIMING_SPAN_NAMES = {
    [d$1]: "Cache lookup",
    [B$1]: "DNS lookup",
    [P$1]: "Connect",
    [b$1]: "TLS handshake",
    [l$1]: "Redirect",
    [D$1]: "Request",
    [m$1]: "Response",
    [S$1]: "Unload event",
    [p$1]: "DOMContentLoaded event",
    [L$1]: "Load event"
  };

  function _enhanceEventWithSdkInfo(event, newSdkInfo) {
    if (!newSdkInfo) {
      return event;
    }
    const eventSdkInfo = event.sdk || {};
    event.sdk = {
      ...eventSdkInfo,
      name: eventSdkInfo.name || newSdkInfo.name,
      version: eventSdkInfo.version || newSdkInfo.version,
      integrations: [...event.sdk?.integrations || [], ...newSdkInfo.integrations || []],
      packages: [...event.sdk?.packages || [], ...newSdkInfo.packages || []],
      settings: event.sdk?.settings || newSdkInfo.settings ? {
        ...event.sdk?.settings,
        ...newSdkInfo.settings
      } : void 0
    };
    return event;
  }
  function createSessionEnvelope(session, dsn, metadata, tunnel) {
    const sdkInfo = getSdkMetadataForEnvelopeHeader(metadata);
    const envelopeHeaders = {
      sent_at: new Date(safeDateNow()).toISOString(),
      ...sdkInfo && { sdk: sdkInfo },
      ...!!tunnel && dsn && { dsn: dsnToString(dsn) }
    };
    const envelopeItem = "aggregates" in session ? [{ type: "sessions" }, session] : [{ type: "session" }, session.toJSON()];
    return createEnvelope(envelopeHeaders, [envelopeItem]);
  }
  function createEventEnvelope(event, dsn, metadata, tunnel) {
    const sdkInfo = getSdkMetadataForEnvelopeHeader(metadata);
    const eventType = event.type && event.type !== "replay_event" ? event.type : "event";
    _enhanceEventWithSdkInfo(event, metadata?.sdk);
    const envelopeHeaders = createEventEnvelopeHeaders(event, sdkInfo, tunnel, dsn);
    delete event.sdkProcessingMetadata;
    const eventItem = [{ type: eventType }, event];
    return createEnvelope(envelopeHeaders, [eventItem]);
  }

  const STATE_PENDING = 0;
  const STATE_RESOLVED = 1;
  const STATE_REJECTED = 2;
  function resolvedSyncPromise(value) {
    return new SyncPromise((resolve) => {
      resolve(value);
    });
  }
  function rejectedSyncPromise(reason) {
    return new SyncPromise((_, reject) => {
      reject(reason);
    });
  }
  class SyncPromise {
    constructor(executor) {
      this._state = STATE_PENDING;
      this._handlers = [];
      this._runExecutor(executor);
    }
    /** @inheritdoc */
    then(onfulfilled, onrejected) {
      return new SyncPromise((resolve, reject) => {
        this._handlers.push([
          false,
          (result) => {
            if (!onfulfilled) {
              resolve(result);
            } else {
              try {
                resolve(onfulfilled(result));
              } catch (e) {
                reject(e);
              }
            }
          },
          (reason) => {
            if (!onrejected) {
              reject(reason);
            } else {
              try {
                resolve(onrejected(reason));
              } catch (e) {
                reject(e);
              }
            }
          }
        ]);
        this._executeHandlers();
      });
    }
    /** @inheritdoc */
    catch(onrejected) {
      return this.then((val) => val, onrejected);
    }
    /** @inheritdoc */
    finally(onfinally) {
      return new SyncPromise((resolve, reject) => {
        let val;
        let isRejected;
        return this.then(
          (value) => {
            isRejected = false;
            val = value;
            if (onfinally) {
              onfinally();
            }
          },
          (reason) => {
            isRejected = true;
            val = reason;
            if (onfinally) {
              onfinally();
            }
          }
        ).then(() => {
          if (isRejected) {
            reject(val);
            return;
          }
          resolve(val);
        });
      });
    }
    /** Excute the resolve/reject handlers. */
    _executeHandlers() {
      if (this._state === STATE_PENDING) {
        return;
      }
      const cachedHandlers = this._handlers.slice();
      this._handlers = [];
      cachedHandlers.forEach((handler) => {
        if (handler[0]) {
          return;
        }
        if (this._state === STATE_RESOLVED) {
          handler[1](this._value);
        }
        if (this._state === STATE_REJECTED) {
          handler[2](this._value);
        }
        handler[0] = true;
      });
    }
    /** Run the executor for the SyncPromise. */
    _runExecutor(executor) {
      const setResult = (state, value) => {
        if (this._state !== STATE_PENDING) {
          return;
        }
        if (isThenable(value)) {
          void value.then(resolve, reject);
          return;
        }
        this._state = state;
        this._value = value;
        this._executeHandlers();
      };
      const resolve = (value) => {
        setResult(STATE_RESOLVED, value);
      };
      const reject = (reason) => {
        setResult(STATE_REJECTED, reason);
      };
      try {
        executor(resolve, reject);
      } catch (e) {
        reject(e);
      }
    }
  }

  function notifyEventProcessors(processors, event, hint, index = 0, onDrop) {
    try {
      const result = _notifyEventProcessors(event, hint, processors, index, onDrop);
      return isThenable(result) ? result : resolvedSyncPromise(result);
    } catch (error) {
      return rejectedSyncPromise(error);
    }
  }
  function _notifyEventProcessors(event, hint, processors, index, onDrop) {
    const processor = processors[index];
    if (!event || !processor) {
      return event;
    }
    const processorName = `Event processor "${processor.id || "?"}"`;
    let callbackError = false;
    const result = safeCallback(
      `${processorName} threw an error, dropping event:` ,
      () => processor({ ...event }, hint),
      () => {
        callbackError = true;
        return null;
      }
    );
    result === null && debug.log(`${processorName} dropped event`);
    if (isThenable(result)) {
      return result.then((final) => {
        if (!final) {
          onDrop?.(callbackError ? "callback_error" : "event_processor");
          return null;
        }
        return _notifyEventProcessors(final, hint, processors, index + 1, onDrop);
      });
    }
    if (!result) {
      onDrop?.(callbackError ? "callback_error" : "event_processor");
      return null;
    }
    return _notifyEventProcessors(result, hint, processors, index + 1, onDrop);
  }

  let parsedStackResults;
  let lastSentryKeysCount;
  let lastNativeKeysCount;
  let cachedFilenameDebugIds;
  function getFilenameToDebugIdMap(stackParser) {
    const sentryDebugIdMap = GLOBAL_OBJ._sentryDebugIds;
    const nativeDebugIdMap = GLOBAL_OBJ._debugIds;
    if (!sentryDebugIdMap && !nativeDebugIdMap) {
      return {};
    }
    const sentryDebugIdKeys = sentryDebugIdMap ? Object.keys(sentryDebugIdMap) : [];
    const nativeDebugIdKeys = nativeDebugIdMap ? Object.keys(nativeDebugIdMap) : [];
    if (cachedFilenameDebugIds && sentryDebugIdKeys.length === lastSentryKeysCount && nativeDebugIdKeys.length === lastNativeKeysCount) {
      return cachedFilenameDebugIds;
    }
    lastSentryKeysCount = sentryDebugIdKeys.length;
    lastNativeKeysCount = nativeDebugIdKeys.length;
    cachedFilenameDebugIds = {};
    if (!parsedStackResults) {
      parsedStackResults = {};
    }
    const processDebugIds = (debugIdKeys, debugIdMap) => {
      for (const key of debugIdKeys) {
        const debugId = debugIdMap[key];
        const result = parsedStackResults?.[key];
        if (result && cachedFilenameDebugIds && debugId) {
          cachedFilenameDebugIds[result[0]] = debugId;
          if (parsedStackResults) {
            parsedStackResults[key] = [result[0], debugId];
          }
        } else if (debugId) {
          const parsedStack = stackParser(key);
          for (let i = parsedStack.length - 1; i >= 0; i--) {
            const stackFrame = parsedStack[i];
            const filename = stackFrame?.filename;
            if (filename && cachedFilenameDebugIds && parsedStackResults) {
              cachedFilenameDebugIds[filename] = debugId;
              parsedStackResults[key] = [filename, debugId];
              break;
            }
          }
        }
      }
    };
    if (sentryDebugIdMap) {
      processDebugIds(sentryDebugIdKeys, sentryDebugIdMap);
    }
    if (nativeDebugIdMap) {
      processDebugIds(nativeDebugIdKeys, nativeDebugIdMap);
    }
    return cachedFilenameDebugIds;
  }

  function prepareEvent(options, event, hint, scope, client, isolationScope) {
    const { normalizeDepth = 3, normalizeMaxBreadth = 1e3 } = options;
    const prepared = {
      ...event,
      event_id: event.event_id || hint.event_id || uuid4(),
      timestamp: event.timestamp || dateTimestampInSeconds()
    };
    const integrations = hint.integrations || options.integrations.map((i) => i.name);
    applyClientOptions(prepared, options);
    applyIntegrationsMetadata(prepared, integrations);
    if (client) {
      client.emit("applyFrameMetadata", event);
    }
    if (event.type === void 0) {
      applyDebugIds(prepared, options.stackParser);
    }
    const finalScope = getFinalScope(scope, hint.captureContext);
    if (hint.mechanism) {
      addExceptionMechanismToCapturedException(prepared, hint.mechanism);
    }
    const clientEventProcessors = client ? client.getEventProcessors() : [];
    const data = getCombinedScopeData(isolationScope, finalScope);
    const attachments = [...hint.attachments || [], ...data.attachments];
    if (attachments.length) {
      hint.attachments = attachments;
    }
    applyScopeDataToEvent(prepared, data);
    const span = getActiveSpan(finalScope);
    if (span) {
      applySpanToEvent(prepared, span);
    }
    applyEscapedErrorSpanToEvent(prepared, hint, finalScope);
    const eventProcessors = [
      ...clientEventProcessors,
      // Run scope event processors _after_ all other processors
      ...data.eventProcessors
    ];
    const isInternalException = hint.data && hint.data.__sentry__ === true;
    const result = isInternalException ? resolvedSyncPromise(prepared) : notifyEventProcessors(eventProcessors, prepared, hint, 0, (reason) => {
      if (!client) {
        return;
      }
      client.recordDroppedEvent(reason, getDataCategoryByType(event.type));
      if (event.type === "transaction") {
        client.recordDroppedEvent(reason, "span", 1 + (event.spans || []).length);
      }
    });
    return result.then((evt) => {
      if (!evt) {
        return null;
      }
      applyDebugMeta(evt);
      if (typeof normalizeDepth === "number" && normalizeDepth > 0) {
        return normalizeEvent(evt, normalizeDepth, normalizeMaxBreadth);
      }
      return evt;
    });
  }
  function applyClientOptions(event, options) {
    const { environment, release, dist, maxValueLength } = options;
    event.environment = event.environment || environment || DEFAULT_ENVIRONMENT;
    if (!event.release && release) {
      event.release = release;
    }
    if (!event.dist && dist) {
      event.dist = dist;
    }
    const request = event.request;
    if (request?.url && maxValueLength) {
      request.url = truncate(request.url, maxValueLength);
    }
    if (maxValueLength) {
      event.exception?.values?.forEach((exception) => {
        if (exception.value) {
          exception.value = truncate(exception.value, maxValueLength);
        }
      });
    }
  }
  function applyDebugIds(event, stackParser) {
    const filenameDebugIdMap = getFilenameToDebugIdMap(stackParser);
    event.exception?.values?.forEach((exception) => {
      exception.stacktrace?.frames?.forEach((frame) => {
        if (frame.filename) {
          frame.debug_id = filenameDebugIdMap[frame.filename];
        }
      });
    });
  }
  function applyDebugMeta(event) {
    const filenameDebugIdMap = {};
    event.exception?.values?.forEach((exception) => {
      exception.stacktrace?.frames?.forEach((frame) => {
        if (frame.debug_id) {
          if (frame.abs_path) {
            filenameDebugIdMap[frame.abs_path] = frame.debug_id;
          } else if (frame.filename) {
            filenameDebugIdMap[frame.filename] = frame.debug_id;
          }
          delete frame.debug_id;
        }
      });
    });
    if (Object.keys(filenameDebugIdMap).length === 0) {
      return;
    }
    event.debug_meta = event.debug_meta || {};
    event.debug_meta.images = event.debug_meta.images || [];
    const images = event.debug_meta.images;
    Object.entries(filenameDebugIdMap).forEach(([filename, debug_id]) => {
      images.push({
        type: "sourcemap",
        code_file: filename,
        debug_id
      });
    });
  }
  function applyIntegrationsMetadata(event, integrationNames) {
    if (integrationNames.length > 0) {
      event.sdk = event.sdk || {};
      event.sdk.integrations = [...event.sdk.integrations || [], ...integrationNames];
    }
  }
  function normalizeEvent(event, depth, maxBreadth) {
    if (!event) {
      return null;
    }
    const normalized = {
      ...event,
      ...event.breadcrumbs && {
        breadcrumbs: event.breadcrumbs.map((b) => ({
          ...b,
          ...b.data && {
            data: normalize(b.data, depth, maxBreadth)
          }
        }))
      },
      ...event.user && {
        user: normalize(event.user, depth, maxBreadth)
      },
      ...event.contexts && {
        contexts: normalize(event.contexts, depth, maxBreadth)
      },
      ...event.extra && {
        extra: normalize(event.extra, depth, maxBreadth)
      }
    };
    if (event.contexts?.trace && normalized.contexts) {
      normalized.contexts.trace = event.contexts.trace;
      if (event.contexts.trace.data) {
        normalized.contexts.trace.data = normalize(event.contexts.trace.data, depth, maxBreadth);
      }
    }
    if (event.spans) {
      normalized.spans = event.spans.map((span) => {
        return {
          ...span,
          ...span.data && {
            data: normalize(span.data, depth, maxBreadth)
          }
        };
      });
    }
    if (event.contexts?.flags && normalized.contexts) {
      normalized.contexts.flags = normalize(event.contexts.flags, 3, maxBreadth);
    }
    return normalized;
  }
  function getFinalScope(scope, captureContext) {
    if (!captureContext) {
      return scope;
    }
    const finalScope = scope ? scope.clone() : new Scope();
    finalScope.update(captureContext);
    return finalScope;
  }
  function parseEventHintOrCaptureContext(hint) {
    if (!hint) {
      return void 0;
    }
    if (hintIsScopeOrFunction(hint)) {
      return { captureContext: hint };
    }
    if (hintIsScopeContext(hint)) {
      return {
        captureContext: hint
      };
    }
    return hint;
  }
  function hintIsScopeOrFunction(hint) {
    return hint instanceof Scope || typeof hint === "function";
  }
  const captureContextKeys = [
    "user",
    "level",
    "extra",
    "contexts",
    "tags",
    "fingerprint",
    "propagationContext"
  ];
  function hintIsScopeContext(hint) {
    return Object.keys(hint).some((key) => captureContextKeys.includes(key));
  }

  function captureException(exception, hint) {
    return getCurrentScope().captureException(exception, parseEventHintOrCaptureContext(hint));
  }
  function captureMessage(message, captureContext) {
    const level = typeof captureContext === "string" ? captureContext : void 0;
    const hint = typeof captureContext !== "string" ? { captureContext } : void 0;
    return getCurrentScope().captureMessage(message, level, hint);
  }
  function captureEvent(event, hint) {
    return getCurrentScope().captureEvent(event, hint);
  }
  function setContext(name, context) {
    getIsolationScope().setContext(name, context);
  }
  function setExtras(extras) {
    getIsolationScope().setExtras(extras);
  }
  function setExtra(key, extra) {
    getIsolationScope().setExtra(key, extra);
  }
  function setTags(tags) {
    getIsolationScope().setTags(tags);
  }
  function setTag(key, value) {
    getIsolationScope().setTag(key, value);
  }
  function setAttributes(attributes) {
    getIsolationScope().setAttributes(attributes);
  }
  function setAttribute(key, value) {
    getIsolationScope().setAttribute(key, value);
  }
  function setUser(user) {
    getIsolationScope().setUser(user);
  }
  function setConversationId(conversationId) {
    getIsolationScope().setConversationId(conversationId);
  }
  function lastEventId() {
    return getIsolationScope().lastEventId();
  }
  async function flush(timeout) {
    const client = getClient();
    if (client) {
      return client.flush(timeout);
    }
    debug.warn("Cannot flush events. No client defined.");
    return Promise.resolve(false);
  }
  async function close(timeout) {
    const client = getClient();
    if (client) {
      return client.close(timeout);
    }
    debug.warn("Cannot flush events and disable SDK. No client defined.");
    return Promise.resolve(false);
  }
  function isInitialized() {
    return !!getClient();
  }
  function isEnabled() {
    const client = getClient();
    return client?.getOptions().enabled !== false && !!client?.getTransport();
  }
  function addEventProcessor(callback) {
    getIsolationScope().addEventProcessor(callback);
  }
  function startSession(context) {
    const isolationScope = getIsolationScope();
    const { user } = getCombinedScopeData(isolationScope, getCurrentScope());
    const { userAgent } = GLOBAL_OBJ.navigator || {};
    const session = makeSession({
      user,
      ...userAgent && { userAgent },
      ...context
    });
    const currentSession = isolationScope.getSession();
    if (currentSession?.status === "ok") {
      updateSession(currentSession, { status: "exited" });
    }
    endSession();
    isolationScope.setSession(session);
    return session;
  }
  function endSession() {
    const isolationScope = getIsolationScope();
    const currentScope = getCurrentScope();
    const session = currentScope.getSession() || isolationScope.getSession();
    if (session) {
      closeSession(session);
    }
    _sendSessionUpdate();
    isolationScope.setSession();
  }
  function _sendSessionUpdate() {
    const isolationScope = getIsolationScope();
    const client = getClient();
    const session = isolationScope.getSession();
    if (session && client) {
      client.captureSession(session);
    }
  }
  function captureSession(end = false) {
    if (end) {
      endSession();
      return;
    }
    _sendSessionUpdate();
  }

  const SENTRY_API_VERSION = "7";
  function getBaseApiEndpoint(dsn) {
    const protocol = dsn.protocol ? `${dsn.protocol}:` : "";
    const port = dsn.port ? `:${dsn.port}` : "";
    return `${protocol}//${dsn.host}${port}${dsn.path ? `/${dsn.path}` : ""}/api/`;
  }
  function _getIngestEndpoint(dsn) {
    return `${getBaseApiEndpoint(dsn)}${dsn.projectId}/envelope/`;
  }
  function _encodedAuth(dsn, sdkInfo) {
    const params = {
      sentry_version: SENTRY_API_VERSION
    };
    if (dsn.publicKey) {
      params.sentry_key = dsn.publicKey;
    }
    if (sdkInfo) {
      params.sentry_client = `${sdkInfo.name}/${sdkInfo.version}`;
    }
    return new URLSearchParams(params).toString();
  }
  function getEnvelopeEndpointWithUrlEncodedAuth(dsn, tunnel, sdkInfo) {
    return tunnel ? tunnel : `${_getIngestEndpoint(dsn)}?${_encodedAuth(dsn, sdkInfo)}`;
  }
  function getReportDialogEndpoint(dsnLike, dialogOptions) {
    const dsn = makeDsn(dsnLike);
    if (!dsn) {
      return "";
    }
    const endpoint = `${getBaseApiEndpoint(dsn)}embed/error-page/`;
    let encodedOptions = `dsn=${dsnToString(dsn)}`;
    for (const key in dialogOptions) {
      if (key === "dsn") {
        continue;
      }
      if (key === "onClose") {
        continue;
      }
      if (key === "user") {
        const user = dialogOptions.user;
        if (!user) {
          continue;
        }
        if (user.name) {
          encodedOptions += `&name=${encodeURIComponent(user.name)}`;
        }
        if (user.email) {
          encodedOptions += `&email=${encodeURIComponent(user.email)}`;
        }
      } else {
        encodedOptions += `&${encodeURIComponent(key)}=${encodeURIComponent(dialogOptions[key])}`;
      }
    }
    return `${endpoint}?${encodedOptions}`;
  }

  function createLogContainerEnvelopeItem(items, inferUserData) {
    const inferSetting = inferUserData ? "auto" : "never";
    return [
      {
        type: "log",
        item_count: items.length,
        content_type: "application/vnd.sentry.items.log+json"
      },
      {
        version: 2,
        ...isBrowser() && {
          ingest_settings: { infer_ip: inferSetting, infer_user_agent: inferSetting }
        },
        items
      }
    ];
  }
  function createLogEnvelope(logs, metadata, tunnel, dsn, inferUserData) {
    const headers = {};
    if (metadata?.sdk) {
      headers.sdk = {
        name: metadata.sdk.name,
        version: metadata.sdk.version
      };
    }
    if (!!tunnel && !!dsn) {
      headers.dsn = dsnToString(dsn);
    }
    return createEnvelope(headers, [createLogContainerEnvelopeItem(logs, inferUserData)]);
  }

  function _INTERNAL_flushLogsBuffer(client, maybeLogBuffer) {
    const logBuffer = maybeLogBuffer ?? _INTERNAL_getLogBuffer(client) ?? [];
    if (logBuffer.length === 0) {
      return;
    }
    const clientOptions = client.getOptions();
    const envelope = createLogEnvelope(
      logBuffer,
      clientOptions._metadata,
      clientOptions.tunnel,
      client.getDsn(),
      client.getDataCollectionOptions().userInfo
    );
    _getBufferMap$1().set(client, []);
    client.emit("flushLogs");
    client.sendEnvelope(envelope);
  }
  function _INTERNAL_getLogBuffer(client) {
    return _getBufferMap$1().get(client);
  }
  function _getBufferMap$1() {
    return getGlobalSingleton("clientToLogBufferMap", () => /* @__PURE__ */ new WeakMap());
  }

  function createMetricContainerEnvelopeItem(items, inferUserData) {
    const inferSetting = inferUserData ? "auto" : "never";
    return [
      {
        type: "trace_metric",
        item_count: items.length,
        content_type: "application/vnd.sentry.items.trace-metric+json"
      },
      {
        version: 2,
        ...isBrowser() && {
          ingest_settings: { infer_ip: inferSetting, infer_user_agent: inferSetting }
        },
        items
      }
    ];
  }
  function createMetricEnvelope(metrics, metadata, tunnel, dsn, inferUserData) {
    const headers = {};
    if (metadata?.sdk) {
      headers.sdk = {
        name: metadata.sdk.name,
        version: metadata.sdk.version
      };
    }
    if (!!tunnel && !!dsn) {
      headers.dsn = dsnToString(dsn);
    }
    return createEnvelope(headers, [createMetricContainerEnvelopeItem(metrics, inferUserData)]);
  }

  function _INTERNAL_flushMetricsBuffer(client, maybeMetricBuffer) {
    const metricBuffer = maybeMetricBuffer ?? _INTERNAL_getMetricBuffer(client) ?? [];
    if (metricBuffer.length === 0) {
      return;
    }
    const clientOptions = client.getOptions();
    const envelope = createMetricEnvelope(
      metricBuffer,
      clientOptions._metadata,
      clientOptions.tunnel,
      client.getDsn(),
      client.getDataCollectionOptions().userInfo
    );
    _getBufferMap().set(client, []);
    client.emit("flushMetrics");
    client.sendEnvelope(envelope);
  }
  function _INTERNAL_getMetricBuffer(client) {
    return _getBufferMap().get(client);
  }
  function _getBufferMap() {
    return getGlobalSingleton("clientToMetricBufferMap", () => /* @__PURE__ */ new WeakMap());
  }

  function extractGenAiSpansFromEvent(event, client) {
    if (event.type !== "transaction" || !event.spans?.length || !event.sdkProcessingMetadata?.hasGenAiSpans || hasSpanStreamingEnabled(client)) {
      return void 0;
    }
    const genAiSpans = [];
    const remainingSpans = [];
    for (const span of event.spans) {
      if (span.op?.startsWith("gen_ai.")) {
        genAiSpans.push(spanJsonToSerializedStreamedSpan(span));
      } else {
        remainingSpans.push(span);
      }
    }
    if (genAiSpans.length === 0) {
      return void 0;
    }
    event.spans = remainingSpans;
    return createSpanContainerItem(genAiSpans, client);
  }

  const SENTRY_BUFFER_FULL_ERROR = /* @__PURE__ */ Symbol.for("SentryBufferFullError");
  function makePromiseBuffer(limit = 100) {
    const buffer = /* @__PURE__ */ new Set();
    function isReady() {
      return buffer.size < limit;
    }
    function remove(task) {
      buffer.delete(task);
    }
    function add(taskProducer) {
      if (!isReady()) {
        return rejectedSyncPromise(SENTRY_BUFFER_FULL_ERROR);
      }
      const task = taskProducer();
      buffer.add(task);
      void task.then(
        () => remove(task),
        () => remove(task)
      );
      return task;
    }
    function drain(timeout) {
      if (!buffer.size) {
        return resolvedSyncPromise(true);
      }
      const drainPromise = Promise.allSettled(Array.from(buffer)).then(() => true);
      if (!timeout) {
        return drainPromise;
      }
      const promises = [
        drainPromise,
        new Promise((resolve) => safeUnref(setTimeout(() => resolve(false), timeout)))
      ];
      return Promise.race(promises);
    }
    return {
      get $() {
        return Array.from(buffer);
      },
      add,
      drain
    };
  }

  const DEFAULT_RETRY_AFTER = 60 * 1e3;
  function parseRetryAfterHeader(header, now = safeDateNow()) {
    const headerDelay = parseInt(`${header}`, 10);
    if (!isNaN(headerDelay)) {
      return headerDelay * 1e3;
    }
    const headerDate = Date.parse(`${header}`);
    if (!isNaN(headerDate)) {
      return headerDate - now;
    }
    return DEFAULT_RETRY_AFTER;
  }
  function disabledUntil(limits, dataCategory) {
    return limits[dataCategory] || limits.all || 0;
  }
  function isRateLimited(limits, dataCategory, now = safeDateNow()) {
    return disabledUntil(limits, dataCategory) > now;
  }
  function updateRateLimits(limits, { statusCode, headers }, now = safeDateNow()) {
    const updatedRateLimits = {
      ...limits
    };
    const rateLimitHeader = headers?.["x-sentry-rate-limits"];
    const retryAfterHeader = headers?.["retry-after"];
    if (rateLimitHeader) {
      for (const limit of rateLimitHeader.trim().split(",")) {
        const [retryAfter, categories, , , namespaces] = limit.split(":", 5);
        const headerDelay = parseInt(retryAfter, 10);
        const delay = (!isNaN(headerDelay) ? headerDelay : 60) * 1e3;
        if (!categories) {
          updatedRateLimits.all = now + delay;
        } else {
          for (const category of categories.split(";")) {
            if (category === "metric_bucket") {
              if (!namespaces || namespaces.split(";").includes("custom")) {
                updatedRateLimits[category] = now + delay;
              }
            } else {
              updatedRateLimits[category] = now + delay;
            }
          }
        }
      }
    } else if (retryAfterHeader) {
      updatedRateLimits.all = now + parseRetryAfterHeader(retryAfterHeader, now);
    } else if (statusCode === 429) {
      updatedRateLimits.all = now + 60 * 1e3;
    }
    return updatedRateLimits;
  }

  const DEFAULT_TRANSPORT_BUFFER_SIZE = 64;
  function createTransport(options, makeRequest, buffer = makePromiseBuffer(
    options.bufferSize || DEFAULT_TRANSPORT_BUFFER_SIZE
  )) {
    let rateLimits = {};
    const flush = (timeout) => buffer.drain(timeout);
    function send(envelope) {
      const filteredEnvelopeItems = [];
      forEachEnvelopeItem(envelope, (item, type) => {
        const dataCategory = envelopeItemTypeToDataCategory(type);
        if (isRateLimited(rateLimits, dataCategory)) {
          options.recordDroppedEvent("ratelimit_backoff", dataCategory);
        } else {
          filteredEnvelopeItems.push(item);
        }
      });
      if (filteredEnvelopeItems.length === 0) {
        return Promise.resolve({});
      }
      const filteredEnvelope = createEnvelope(envelope[0], filteredEnvelopeItems);
      const recordEnvelopeLoss = (reason) => {
        if (envelopeContainsItemType(filteredEnvelope, ["client_report"])) {
          debug.warn(`Dropping client report. Will not send outcomes (reason: ${reason}).`);
          return;
        }
        forEachEnvelopeItem(filteredEnvelope, (item, type) => {
          options.recordDroppedEvent(reason, envelopeItemTypeToDataCategory(type));
        });
      };
      const requestTask = () => makeRequest({ body: serializeEnvelope(filteredEnvelope) }).then(
        (response) => {
          if (response.statusCode === 413) {
            debug.error(
              "Sentry responded with status code 413. Envelope was discarded due to exceeding size limits."
            );
            recordEnvelopeLoss("send_error");
            return response;
          }
          if (response.statusCode !== void 0 && (response.statusCode < 200 || response.statusCode >= 300)) {
            debug.warn(`Sentry responded with status code ${response.statusCode} to sent event.`);
          }
          rateLimits = updateRateLimits(rateLimits, response);
          return response;
        },
        (error) => {
          recordEnvelopeLoss("network_error");
          debug.error("Encountered error running transport request:", error);
          throw error;
        }
      );
      return buffer.add(requestTask).then(
        (result) => result,
        (error) => {
          if (error === SENTRY_BUFFER_FULL_ERROR) {
            debug.error("Skipped sending event because buffer is full.");
            recordEnvelopeLoss("queue_overflow");
            return Promise.resolve({});
          } else {
            throw error;
          }
        }
      );
    }
    return {
      send,
      flush
    };
  }

  function createClientReportEnvelope(discarded_events, dsn, timestamp) {
    const clientReportItem = [
      { type: "client_report" },
      {
        timestamp: dateTimestampInSeconds(),
        discarded_events
      }
    ];
    return createEnvelope(dsn ? { dsn } : {}, [clientReportItem]);
  }

  function getPossibleEventMessages(event) {
    const possibleMessages = [];
    if (event.message) {
      possibleMessages.push(event.message);
    }
    try {
      const lastException = event.exception.values[event.exception.values.length - 1];
      if (lastException?.value) {
        possibleMessages.push(lastException.value);
        if (lastException.type) {
          possibleMessages.push(`${lastException.type}: ${lastException.value}`);
        }
      }
    } catch {
    }
    return possibleMessages;
  }

  function convertTransactionEventToSpanJson(event) {
    const { trace_id, parent_span_id, span_id, status, origin, data, op } = event.contexts?.trace ?? {};
    return {
      data: data ?? {},
      description: event.transaction,
      op,
      parent_span_id,
      span_id: span_id ?? "",
      start_timestamp: event.start_timestamp ?? 0,
      status: status ?? "ok",
      timestamp: event.timestamp,
      trace_id: trace_id ?? "",
      origin,
      profile_id: data?.[SEMANTIC_ATTRIBUTE_PROFILE_ID],
      exclusive_time: data?.[SEMANTIC_ATTRIBUTE_EXCLUSIVE_TIME],
      measurements: event.measurements,
      is_segment: true
    };
  }
  function convertSpanJsonToTransactionEvent(span) {
    return {
      type: "transaction",
      timestamp: span.timestamp,
      start_timestamp: span.start_timestamp,
      transaction: span.description,
      contexts: {
        trace: {
          trace_id: span.trace_id,
          span_id: span.span_id,
          parent_span_id: span.parent_span_id,
          op: span.op,
          status: span.status,
          origin: span.origin,
          data: {
            ...span.data,
            ...span.profile_id && { [SEMANTIC_ATTRIBUTE_PROFILE_ID]: span.profile_id },
            ...span.exclusive_time && { [SEMANTIC_ATTRIBUTE_EXCLUSIVE_TIME]: span.exclusive_time }
          }
        }
      },
      measurements: span.measurements
    };
  }

  function maybeWarnAboutIgnoredTransactionOptions(options) {
    if (options.traceLifecycle !== "stream" || // oxlint-disable-next-line typescript/no-deprecated
    !(options.beforeSendTransaction || options.ignoreTransactions?.length)) {
      return;
    }
    consoleSandbox(() => {
      console.warn(
        "[Sentry] `beforeSendTransaction` and `ignoreTransactions` are ignored with `traceLifecycle: 'stream'` (enabled by default). Use `beforeSendSpan` and `ignoreSpans` instead, or set `traceLifecycle: 'static'`."
      );
    });
  }

  const DEFAULTS = {
    userInfo: true,
    cookies: true,
    httpHeaders: { request: true, response: true },
    httpBodies: ["incomingRequest", "outgoingRequest", "incomingResponse", "outgoingResponse"],
    urlQueryParams: true,
    graphQL: { document: true, variables: true },
    genAI: { inputs: true, outputs: true },
    databaseQueryData: true,
    queues: true,
    stackFrameVariables: true,
    frameContextLines: 5
  };
  function isCollectBehavior(value) {
    return typeof value === "boolean" || "allow" in value || "deny" in value;
  }
  function resolveHttpHeaders(httpHeaders) {
    if (httpHeaders === void 0) {
      return { ...DEFAULTS.httpHeaders };
    }
    if (isCollectBehavior(httpHeaders)) {
      return { request: httpHeaders, response: httpHeaders };
    }
    return {
      request: httpHeaders.request ?? DEFAULTS.httpHeaders.request,
      response: httpHeaders.response ?? DEFAULTS.httpHeaders.response
    };
  }
  function resolveDataCollectionOptions(options) {
    const dc = options.dataCollection ?? {};
    return {
      userInfo: dc.userInfo ?? DEFAULTS.userInfo,
      cookies: dc.cookies ?? DEFAULTS.cookies,
      httpHeaders: resolveHttpHeaders(dc.httpHeaders),
      httpBodies: dc.httpBodies ?? DEFAULTS.httpBodies,
      urlQueryParams: dc.urlQueryParams ?? DEFAULTS.urlQueryParams,
      graphQL: {
        document: dc.graphQL?.document ?? DEFAULTS.graphQL.document,
        variables: dc.graphQL?.variables ?? DEFAULTS.graphQL.variables
      },
      genAI: {
        inputs: dc.genAI?.inputs ?? DEFAULTS.genAI.inputs,
        outputs: dc.genAI?.outputs ?? DEFAULTS.genAI.outputs
      },
      databaseQueryData: dc.databaseQueryData ?? DEFAULTS.databaseQueryData,
      queues: dc.queues ?? DEFAULTS.queues,
      stackFrameVariables: dc.stackFrameVariables ?? DEFAULTS.stackFrameVariables,
      frameContextLines: dc.frameContextLines ?? DEFAULTS.frameContextLines
    };
  }

  const ALREADY_SEEN_ERROR = "Not capturing exception because it's already been captured.";
  const MISSING_RELEASE_FOR_SESSION_ERROR = "Discarded session because of missing or non-string release";
  const INTERNAL_ERROR_SYMBOL = /* @__PURE__ */ Symbol.for("SentryInternalError");
  const DO_NOT_SEND_EVENT_SYMBOL = /* @__PURE__ */ Symbol.for("SentryDoNotSendEventError");
  const DEFAULT_FLUSH_INTERVAL = 5e3;
  function _makeInternalError(message) {
    return {
      message,
      [INTERNAL_ERROR_SYMBOL]: true
    };
  }
  function _makeDoNotSendEventError(message) {
    return {
      message,
      [DO_NOT_SEND_EVENT_SYMBOL]: true
    };
  }
  function _isInternalError(error) {
    return isObjectLike(error) && INTERNAL_ERROR_SYMBOL in error;
  }
  function _isDoNotSendEventError(error) {
    return isObjectLike(error) && DO_NOT_SEND_EVENT_SYMBOL in error;
  }
  function setupWeightBasedFlushing(client, afterCaptureHook, flushHook, estimateSizeFn, flushFn) {
    let weight = 0;
    let flushTimeout;
    let isTimerActive = false;
    client.on(flushHook, () => {
      weight = 0;
      clearTimeout(flushTimeout);
      isTimerActive = false;
    });
    client.on(afterCaptureHook, (item) => {
      weight += estimateSizeFn(item);
      if (weight >= 8e5) {
        flushFn(client);
      } else if (!isTimerActive) {
        const flushInterval = client.getOptions()._flushInterval ?? DEFAULT_FLUSH_INTERVAL;
        if (flushInterval > 0) {
          isTimerActive = true;
          flushTimeout = safeUnref(
            setTimeout(() => {
              flushFn(client);
            }, flushInterval)
          );
        }
      }
    });
    client.on("flush", () => {
      flushFn(client);
    });
  }
  class Client {
    /**
     * Initializes this client instance.
     *
     * @param options Options for the client.
     */
    constructor(options) {
      this._options = {
        attachStacktrace: true,
        ...options,
        traceLifecycle: options.traceLifecycle === "static" ? "static" : "stream"
      };
      this._integrations = {};
      this._numProcessing = 0;
      this._outcomes = {};
      this._hooks = {};
      this._eventProcessors = [];
      this._promiseBuffer = makePromiseBuffer(options.transportOptions?.bufferSize ?? DEFAULT_TRANSPORT_BUFFER_SIZE);
      this._dataCollection = resolveDataCollectionOptions(options);
      this._unhandledSessionStatus = "crashed";
      if (options.dsn) {
        this._dsn = makeDsn(options.dsn);
      } else {
        debug.warn("No DSN provided, client will not send events.");
      }
      const { beforeSendSpan, traceLifecycle } = this._options;
      if (beforeSendSpan && isStaticBeforeSendSpanCallback(beforeSendSpan) !== (traceLifecycle === "static")) {
        consoleSandbox(() => {
          console.warn(
            `Ignoring \`beforeSendSpan\`: ${traceLifecycle === "static" ? "wrap it with" : "remove"} \`Sentry.withStaticSpan\` to use it with \`traceLifecycle: "${traceLifecycle}"\`.`
          );
        });
      }
      if (this._dsn) {
        const url = getEnvelopeEndpointWithUrlEncodedAuth(
          this._dsn,
          options.tunnel,
          options._metadata ? options._metadata.sdk : void 0
        );
        this._transport = options.transport({
          tunnel: this._options.tunnel,
          recordDroppedEvent: this.recordDroppedEvent.bind(this),
          ...options.transportOptions,
          url
        });
      }
      setupWeightBasedFlushing(this, "afterCaptureLog", "flushLogs", estimateLogSizeInBytes, _INTERNAL_flushLogsBuffer);
      setupWeightBasedFlushing(
        this,
        "afterCaptureMetric",
        "flushMetrics",
        estimateMetricSizeInBytes,
        _INTERNAL_flushMetricsBuffer
      );
    }
    /**
     * Captures an exception event and sends it to Sentry.
     *
     * Unlike `captureException` exported from every SDK, this method requires that you pass it the current scope.
     */
    captureException(exception, hint, scope) {
      const eventId = uuid4();
      if (checkOrSetAlreadyCaught(exception)) {
        debug.log(ALREADY_SEEN_ERROR);
        return eventId;
      }
      const hintWithEventId = {
        event_id: eventId,
        ...hint
      };
      this._process(
        () => this.eventFromException(exception, hintWithEventId).then((event) => this._captureEvent(event, hintWithEventId, scope)).then((res) => res),
        "error"
      );
      return hintWithEventId.event_id;
    }
    /**
     * Captures a message event and sends it to Sentry.
     *
     * Unlike `captureMessage` exported from every SDK, this method requires that you pass it the current scope.
     */
    captureMessage(message, level, hint, currentScope) {
      const hintWithEventId = {
        event_id: uuid4(),
        ...hint
      };
      const eventMessage = isParameterizedString(message) ? message : String(message);
      const isMessage = isPrimitive(message);
      const promisedEvent = isMessage ? this.eventFromMessage(eventMessage, level, hintWithEventId) : this.eventFromException(message, hintWithEventId);
      this._process(
        () => promisedEvent.then((event) => this._captureEvent(event, hintWithEventId, currentScope)),
        isMessage ? "unknown" : "error"
      );
      return hintWithEventId.event_id;
    }
    /**
     * Captures a manually created event and sends it to Sentry.
     *
     * Unlike `captureEvent` exported from every SDK, this method requires that you pass it the current scope.
     */
    captureEvent(event, hint, currentScope) {
      const eventId = uuid4();
      if (hint?.originalException && checkOrSetAlreadyCaught(hint.originalException)) {
        debug.log(ALREADY_SEEN_ERROR);
        return eventId;
      }
      const hintWithEventId = {
        event_id: eventId,
        ...hint
      };
      const sdkProcessingMetadata = event.sdkProcessingMetadata || {};
      const capturedSpanScope = sdkProcessingMetadata.capturedSpanScope;
      const capturedSpanIsolationScope = sdkProcessingMetadata.capturedSpanIsolationScope;
      const dataCategory = getDataCategoryByType(event.type);
      this._process(
        () => this._captureEvent(event, hintWithEventId, capturedSpanScope || currentScope, capturedSpanIsolationScope),
        dataCategory
      );
      return hintWithEventId.event_id;
    }
    /**
     * Captures a session.
     */
    captureSession(session) {
      this.sendSession(session);
      updateSession(session, { init: false });
    }
    /**
     * Get the current Dsn.
     */
    getDsn() {
      return this._dsn;
    }
    /**
     * Get the current options.
     */
    getOptions() {
      return this._options;
    }
    /**
     * Get the resolved data collection configuration.
     */
    getDataCollectionOptions() {
      return this._dataCollection;
    }
    /**
     * Get the SDK metadata.
     * @see SdkMetadata
     */
    getSdkMetadata() {
      return this._options._metadata;
    }
    /**
     * Returns the transport that is used by the client.
     * Please note that the transport gets lazy initialized so it will only be there once the first event has been sent.
     */
    getTransport() {
      return this._transport;
    }
    /**
     * Wait for all events to be sent or the timeout to expire, whichever comes first.
     *
     * @param timeout Maximum time in ms the client should wait for events to be flushed. Omitting this parameter will
     *   cause the client to wait until all events are sent before resolving the promise.
     * @returns A promise that will resolve with `true` if all events are sent before the timeout, or `false` if there are
     * still events in the queue when the timeout is reached.
     */
    // @ts-expect-error - PromiseLike is a subset of Promise
    async flush(timeout) {
      const transport = this._transport;
      this.emit("flush");
      if (!transport) {
        return true;
      }
      const clientFinished = await this._isClientDoneProcessing(timeout);
      const transportFlushed = await transport.flush(timeout);
      return clientFinished && transportFlushed;
    }
    /**
     * Flush the event queue and set the client to `enabled = false`. See {@link Client.flush}.
     *
     * @param {number} timeout Maximum time in ms the client should wait before shutting down. Omitting this parameter will cause
     *   the client to wait until all events are sent before disabling itself.
     * @returns {Promise<boolean>} A promise which resolves to `true` if the flush completes successfully before the timeout, or `false` if
     * it doesn't.
     */
    // @ts-expect-error - PromiseLike is a subset of Promise
    async close(timeout) {
      const result = await this.flush(timeout);
      this.getOptions().enabled = false;
      this.emit("close");
      return result;
    }
    /**
     * Get all installed event processors.
     */
    getEventProcessors() {
      return this._eventProcessors;
    }
    /**
     * Adds an event processor that applies to any event processed by this client.
     */
    addEventProcessor(eventProcessor) {
      this._eventProcessors.push(eventProcessor);
    }
    /**
     * Initialize this client.
     * Call this after the client was set on a scope.
     */
    init() {
      if (this._isEnabled() || // Force integrations to be setup even if no DSN was set when we have
      // Spotlight enabled. This is particularly important for browser as we
      // don't support the `spotlight` option there and rely on the users
      // adding the `spotlightBrowserIntegration()` to their integrations which
      // wouldn't get initialized with the check below when there's no DSN set.
      this._options.integrations.some(({ name }) => name.startsWith("Spotlight"))) {
        this._setupIntegrations();
        maybeWarnAboutIgnoredTransactionOptions(this._options);
      }
    }
    /**
     * Gets an installed integration by its name.
     *
     * @returns {Integration|undefined} The installed integration or `undefined` if no integration with that `name` was installed.
     */
    getIntegrationByName(integrationName) {
      return this._integrations[integrationName];
    }
    /**
     * Returns the names of all installed integrations.
     */
    getIntegrationNames() {
      return Object.keys(this._integrations);
    }
    /**
     * Add an integration to the client.
     * This can be used to e.g. lazy load integrations.
     * In most cases, this should not be necessary,
     * and you're better off just passing the integrations via `integrations: []` at initialization time.
     * However, if you find the need to conditionally load & add an integration, you can use `addIntegration` to do so.
     */
    addIntegration(integration) {
      const isAlreadyInstalled = this._integrations[integration.name];
      if (!isAlreadyInstalled && integration.beforeSetup) {
        integration.beforeSetup(this);
      }
      setupIntegration(this, integration, this._integrations);
      if (!isAlreadyInstalled) {
        afterSetupIntegrations(this, [integration]);
      }
    }
    /**
     * Send a fully prepared event to Sentry.
     */
    sendEvent(event, hint = {}) {
      this.emit("beforeSendEvent", event, hint);
      const genAiSpanItem = extractGenAiSpansFromEvent(event, this);
      let env = createEventEnvelope(event, this._dsn, this._options._metadata, this._options.tunnel);
      for (const attachment of hint.attachments || []) {
        env = addItemToEnvelope(env, createAttachmentEnvelopeItem(attachment));
      }
      if (genAiSpanItem) {
        env = addItemToEnvelope(env, genAiSpanItem);
      }
      this.sendEnvelope(env).then((sendResponse) => this.emit("afterSendEvent", event, sendResponse));
    }
    /**
     * Send a session or session aggregrates to Sentry.
     */
    sendSession(session) {
      const { release: clientReleaseOption, environment: clientEnvironmentOption = DEFAULT_ENVIRONMENT } = this._options;
      if ("aggregates" in session) {
        const sessionAttrs = session.attrs || {};
        if (!sessionAttrs.release && !clientReleaseOption) {
          debug.warn(MISSING_RELEASE_FOR_SESSION_ERROR);
          return;
        }
        sessionAttrs.release = sessionAttrs.release || clientReleaseOption;
        sessionAttrs.environment = sessionAttrs.environment || clientEnvironmentOption;
        session.attrs = sessionAttrs;
      } else {
        if (!session.release && !clientReleaseOption) {
          debug.warn(MISSING_RELEASE_FOR_SESSION_ERROR);
          return;
        }
        session.release = session.release || clientReleaseOption;
        session.environment = session.environment || clientEnvironmentOption;
      }
      this.emit("beforeSendSession", session);
      const env = createSessionEnvelope(session, this._dsn, this._options._metadata, this._options.tunnel);
      this.sendEnvelope(env);
    }
    /**
     * Record on the client that an event got dropped (ie, an event that will not be sent to Sentry).
     */
    recordDroppedEvent(reason, category, count = 1) {
      if (this._options.sendClientReports) {
        const key = `${reason}:${category}`;
        debug.log(`Recording outcome: "${key}"${count > 1 ? ` (${count} times)` : ""}`);
        this._outcomes[key] = (this._outcomes[key] || 0) + count;
      }
    }
    /**
     * Register a hook on this client.
     */
    on(hook, callback) {
      const hookCallbacks = this._hooks[hook] = this._hooks[hook] || /* @__PURE__ */ new Set();
      const uniqueCallback = (...args) => callback(...args);
      hookCallbacks.add(uniqueCallback);
      return () => {
        hookCallbacks.delete(uniqueCallback);
      };
    }
    /**
     * Emit a hook that was previously registered via `on()`.
     */
    emit(hook, ...rest) {
      const callbacks = this._hooks[hook];
      if (callbacks) {
        callbacks.forEach((callback) => callback(...rest));
      }
    }
    /**
     * Send an envelope to Sentry.
     */
    // @ts-expect-error - PromiseLike is a subset of Promise
    async sendEnvelope(envelope) {
      this.emit("beforeEnvelope", envelope);
      if (this._isEnabled() && this._transport) {
        try {
          const result = await this._transport.send(envelope);
          this.emit("afterEnvelope", envelope);
          return result;
        } catch (reason) {
          debug.error("Error while sending envelope:", reason);
          return {};
        }
      }
      debug.error("Transport disabled");
      return {};
    }
    /**
     * Register a cleanup function to be called when the client is disposed.
     * This is useful for integrations that need to clean up global state.
     *
     * NOTE: This is a no-op in the base `Client` class. Subclasses like `ServerRuntimeClient`
     * override this method to actually register and execute cleanup callbacks.
     */
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    registerCleanup(callback) {
    }
    /**
     * Disposes of the client and releases all resources.
     *
     * Subclasses should override this method to clean up their own resources, including invoking
     * any callbacks registered via {@link Client.registerCleanup}. The base implementation is a
     * no-op and does NOT execute registered cleanup callbacks.
     *
     * After calling dispose(), the client should not be used anymore.
     */
    dispose() {
    }
    /* eslint-enable @typescript-eslint/unified-signatures */
    /** Setup integrations for this client. */
    _setupIntegrations() {
      const { integrations } = this._options;
      this._integrations = setupIntegrations(this, integrations);
      afterSetupIntegrations(this, integrations);
    }
    /** Updates existing session based on the provided event */
    _updateSessionFromEvent(session, event) {
      let unhandled = event.level === "fatal";
      let errored = false;
      const exceptions = event.exception?.values;
      if (exceptions) {
        errored = true;
        unhandled = false;
        for (const ex of exceptions) {
          if (ex.mechanism?.handled === false) {
            unhandled = true;
            break;
          }
        }
      }
      const sessionNonTerminal = session.status === "ok";
      const shouldUpdateAndSend = sessionNonTerminal && session.errors === 0 || sessionNonTerminal && unhandled;
      if (shouldUpdateAndSend) {
        updateSession(session, {
          ...unhandled && { status: this._unhandledSessionStatus },
          errors: session.errors || Number(errored || unhandled)
        });
        this.captureSession(session);
      }
    }
    /**
     * Determine if the client is finished processing. Returns a promise because it will wait `timeout` ms before saying
     * "no" (resolving to `false`) in order to give the client a chance to potentially finish first.
     *
     * @param timeout The time, in ms, after which to resolve to `false` if the client is still busy. Passing `0` (or not
     * passing anything) will make the promise wait as long as it takes for processing to finish before resolving to
     * `true`.
     * @returns A promise which will resolve to `true` if processing is already done or finishes before the timeout, and
     * `false` otherwise
     */
    async _isClientDoneProcessing(timeout) {
      let ticked = 0;
      while (!timeout || ticked < timeout) {
        await new Promise((resolve) => setTimeout(resolve, 1));
        if (!this._numProcessing) {
          return true;
        }
        ticked++;
      }
      return false;
    }
    /** Determines whether this SDK is enabled and a transport is present. */
    _isEnabled() {
      return this.getOptions().enabled !== false && this._transport !== void 0;
    }
    /**
     * Adds common information to events.
     *
     * The information includes release and environment from `options`,
     * breadcrumbs and context (extra, tags and user) from the scope.
     *
     * Information that is already present in the event is never overwritten. For
     * nested objects, such as the context, keys are merged.
     *
     * @param event The original event.
     * @param hint May contain additional information about the original exception.
     * @param currentScope A scope containing event metadata.
     * @returns A new event with more information.
     */
    _prepareEvent(event, hint, currentScope, isolationScope) {
      const options = this.getOptions();
      const integrations = this.getIntegrationNames();
      if (!hint.integrations && integrations.length) {
        hint.integrations = integrations;
      }
      this.emit("preprocessEvent", event, hint);
      if (!event.type) {
        isolationScope.setLastEventId(event.event_id || hint.event_id);
      }
      return prepareEvent(options, event, hint, currentScope, this, isolationScope).then((evt) => {
        if (evt === null) {
          return evt;
        }
        this.emit("postprocessEvent", evt, hint);
        evt.contexts = {
          trace: { ...evt.contexts?.trace, ...getTraceContextFromScope(currentScope) },
          ...evt.contexts
        };
        const dynamicSamplingContext = getDynamicSamplingContextFromScope(this, currentScope);
        evt.sdkProcessingMetadata = {
          dynamicSamplingContext,
          ...evt.sdkProcessingMetadata
        };
        return evt;
      });
    }
    /**
     * Processes the event and logs an error in case of rejection
     * @param event
     * @param hint
     * @param scope
     */
    _captureEvent(event, hint = {}, currentScope = getCurrentScope(), isolationScope = getIsolationScope()) {
      if (isErrorEvent(event)) {
        debug.log(`Captured error event \`${getPossibleEventMessages(event)[0] || "<unknown>"}\``);
      }
      return this._processEvent(event, hint, currentScope, isolationScope).then(
        (finalEvent) => {
          return finalEvent.event_id;
        },
        (reason) => {
          {
            if (_isDoNotSendEventError(reason)) {
              debug.log(reason.message);
            } else if (_isInternalError(reason)) {
              debug.warn(reason.message);
            } else {
              debug.warn(reason);
            }
          }
          return void 0;
        }
      );
    }
    /**
     * Processes an event (either error or message) and sends it to Sentry.
     *
     * This also adds breadcrumbs and context information to the event. However,
     * platform specific meta data (such as the User's IP address) must be added
     * by the SDK implementor.
     *
     *
     * @param event The event to send to Sentry.
     * @param hint May contain additional information about the original exception.
     * @param currentScope A scope containing event metadata.
     * @returns A SyncPromise that resolves with the event or rejects in case event was/will not be send.
     */
    _processEvent(event, hint, currentScope, isolationScope) {
      const options = this.getOptions();
      const { sampleRate } = options;
      const isTransaction = isTransactionEvent(event);
      const isError = isErrorEvent(event);
      const eventType = event.type || "error";
      const beforeSendLabel = `before send for type \`${eventType}\``;
      let beforeSendDropReason = "before_send";
      const parsedSampleRate = typeof sampleRate === "undefined" ? void 0 : parseSampleRate(sampleRate);
      const dataCategory = getDataCategoryByType(event.type);
      return this._prepareEvent(event, hint, currentScope, isolationScope).then((prepared) => {
        if (prepared === null) {
          throw _makeDoNotSendEventError("An event processor returned `null`, will not send event.");
        }
        const isInternalException = hint.data?.__sentry__ === true;
        if (isInternalException) {
          return prepared;
        }
        const result = processBeforeSend(this, options, prepared, hint, () => {
          beforeSendDropReason = "callback_error";
        });
        return _validateBeforeSendResult(result, beforeSendLabel);
      }).then((processedEvent) => {
        if (processedEvent === null) {
          this.recordDroppedEvent(beforeSendDropReason, dataCategory);
          if (isTransaction) {
            const spans = event.spans || [];
            this.recordDroppedEvent(beforeSendDropReason, "span", 1 + spans.length);
          }
          const dropMessage = beforeSendDropReason === "callback_error" ? "threw an error" : "returned `null`";
          throw _makeDoNotSendEventError(`${beforeSendLabel} ${dropMessage}, will not send event.`);
        }
        const session = currentScope.getSession() || isolationScope.getSession();
        if (isError && session) {
          this._updateSessionFromEvent(session, processedEvent);
        }
        if (isError && typeof parsedSampleRate === "number" && safeMathRandom() > parsedSampleRate) {
          this.recordDroppedEvent("sample_rate", "error");
          throw _makeDoNotSendEventError(
            `Discarding event because it's not included in the random sample (sampling rate = ${sampleRate})`
          );
        }
        if (isTransaction) {
          const spanCountBefore = processedEvent.sdkProcessingMetadata?.spanCountBeforeProcessing || 0;
          const spanCountAfter = processedEvent.spans ? processedEvent.spans.length : 0;
          const droppedSpanCount = spanCountBefore - spanCountAfter;
          if (droppedSpanCount > 0) {
            this.recordDroppedEvent("before_send", "span", droppedSpanCount);
          }
        }
        const transactionInfo = processedEvent.transaction_info;
        if (isTransaction && transactionInfo && processedEvent.transaction !== event.transaction) {
          const source = "custom";
          processedEvent.transaction_info = {
            ...transactionInfo,
            source
          };
        }
        this.sendEvent(processedEvent, hint);
        return processedEvent;
      }).then(null, (reason) => {
        if (_isDoNotSendEventError(reason) || _isInternalError(reason)) {
          throw reason;
        }
        this.captureException(reason, {
          mechanism: {
            handled: false,
            type: "internal"
          },
          data: {
            __sentry__: true
          },
          originalException: reason
        });
        throw _makeInternalError(
          `Event processing pipeline threw an error, original event will not be sent. Details have been sent as a new event.
Reason: ${reason}`
        );
      });
    }
    /**
     * Occupies the client with processing and event
     */
    _process(taskProducer, dataCategory) {
      this._numProcessing++;
      void this._promiseBuffer.add(taskProducer).then(
        (value) => {
          this._numProcessing--;
          return value;
        },
        (reason) => {
          this._numProcessing--;
          if (reason === SENTRY_BUFFER_FULL_ERROR) {
            this.recordDroppedEvent("queue_overflow", dataCategory);
          }
          return reason;
        }
      );
    }
    /**
     * Clears outcomes on this client and returns them.
     */
    _clearOutcomes() {
      const outcomes = this._outcomes;
      this._outcomes = {};
      return Object.entries(outcomes).map(([key, quantity]) => {
        const [reason, category] = key.split(":");
        return {
          reason,
          category,
          quantity
        };
      });
    }
    /**
     * Sends client reports as an envelope.
     */
    _flushOutcomes() {
      debug.log("Flushing outcomes...");
      const outcomes = this._clearOutcomes();
      if (outcomes.length === 0) {
        debug.log("No outcomes to send");
        return;
      }
      if (!this._dsn) {
        debug.log("No dsn provided, will not send outcomes");
        return;
      }
      debug.log("Sending outcomes:", outcomes);
      const envelope = createClientReportEnvelope(outcomes, this._options.tunnel && dsnToString(this._dsn));
      this.sendEnvelope(envelope);
    }
  }
  function _validateBeforeSendResult(beforeSendResult, beforeSendLabel) {
    const invalidValueError = `${beforeSendLabel} must return \`null\` or a valid event.`;
    if (isThenable(beforeSendResult)) {
      return beforeSendResult.then(
        (event) => {
          if (!isPlainObject(event) && event !== null) {
            throw _makeInternalError(invalidValueError);
          }
          return event;
        },
        (e) => {
          throw _makeInternalError(`${beforeSendLabel} rejected with ${e}`);
        }
      );
    } else if (!isPlainObject(beforeSendResult) && beforeSendResult !== null) {
      throw _makeInternalError(invalidValueError);
    }
    return beforeSendResult;
  }
  function processBeforeSend(client, options, event, hint, onCallbackError) {
    const {
      beforeSend,
      ignoreSpans,
      // oxlint-disable-next-line typescript/no-deprecated
      beforeSendTransaction
    } = options;
    const beforeSendSpan = isStaticBeforeSendSpanCallback(options.beforeSendSpan) && options.beforeSendSpan;
    let processedEvent = event;
    if (isErrorEvent(processedEvent) && beforeSend) {
      const errorEvent = processedEvent;
      return safeCallback(
        "The `beforeSend` callback threw an error, dropping the event:" ,
        () => beforeSend(errorEvent, hint),
        () => {
          onCallbackError();
          return null;
        }
      );
    }
    if (isTransactionEvent(processedEvent)) {
      if (beforeSendSpan || ignoreSpans) {
        const rootSpanJson = convertTransactionEventToSpanJson(processedEvent);
        if (ignoreSpans?.length && shouldIgnoreSpan(
          { description: rootSpanJson.description, op: rootSpanJson.op, attributes: rootSpanJson.data },
          ignoreSpans
        )) {
          return null;
        }
        if (beforeSendSpan) {
          const processedRootSpanJson = applyBeforeSendSpanCallback(rootSpanJson, beforeSendSpan);
          processedEvent = merge(event, convertSpanJsonToTransactionEvent(processedRootSpanJson));
        }
        if (processedEvent.spans) {
          const processedSpans = [];
          const initialSpans = processedEvent.spans;
          for (const span of initialSpans) {
            if (ignoreSpans?.length && shouldIgnoreSpan({ description: span.description, op: span.op, attributes: span.data }, ignoreSpans)) {
              reparentChildSpans(initialSpans, span);
              continue;
            }
            if (beforeSendSpan) {
              processedSpans.push(applyBeforeSendSpanCallback(span, beforeSendSpan));
            } else {
              processedSpans.push(span);
            }
          }
          const droppedSpans = processedEvent.spans.length - processedSpans.length;
          if (droppedSpans) {
            client.recordDroppedEvent("before_send", "span", droppedSpans);
          }
          processedEvent.spans = processedSpans;
        }
      }
      if (beforeSendTransaction) {
        if (processedEvent.spans) {
          const spanCountBefore = processedEvent.spans.length;
          processedEvent.sdkProcessingMetadata = {
            ...event.sdkProcessingMetadata,
            spanCountBeforeProcessing: spanCountBefore
          };
        }
        return safeCallback(
          "The `beforeSendTransaction` callback threw an error, dropping the event:" ,
          () => beforeSendTransaction(processedEvent, hint),
          () => {
            onCallbackError();
            return null;
          }
        );
      }
    }
    return processedEvent;
  }
  function isErrorEvent(event) {
    return event.type === void 0;
  }
  function isTransactionEvent(event) {
    return event.type === "transaction";
  }
  function estimateMetricSizeInBytes(metric) {
    let weight = 0;
    if (metric.name) {
      weight += metric.name.length * 2;
    }
    weight += 8;
    return weight + estimateAttributesSizeInBytes(metric.attributes);
  }
  function estimateLogSizeInBytes(log) {
    let weight = 0;
    if (log.message) {
      weight += log.message.length * 2;
    }
    return weight + estimateAttributesSizeInBytes(log.attributes);
  }
  function estimateAttributesSizeInBytes(attributes) {
    if (!attributes) {
      return 0;
    }
    let weight = 0;
    Object.values(attributes).forEach((value) => {
      if (Array.isArray(value)) {
        weight += value.length * estimatePrimitiveSizeInBytes(value[0]);
      } else if (isPrimitive(value)) {
        weight += estimatePrimitiveSizeInBytes(value);
      } else {
        weight += 100;
      }
    });
    return weight;
  }
  function estimatePrimitiveSizeInBytes(value) {
    if (typeof value === "string") {
      return value.length * 2;
    } else if (typeof value === "number") {
      return 8;
    } else if (typeof value === "boolean") {
      return 4;
    }
    return 0;
  }

  function initAndBind(clientClass, options) {
    if (options.debug === true) {
      {
        debug.enable();
      }
    }
    const scope = getCurrentScope();
    scope.update(options.initialScope);
    const client = new clientClass(options);
    setCurrentClient(client);
    client.init();
    return client;
  }
  function setCurrentClient(client) {
    getCurrentScope().setClient(client);
  }

  const FILTERED_VALUE = "[Filtered]";
  const SENSITIVE_KEY_SNIPPETS = [
    "auth",
    "token",
    "secret",
    "session",
    // for the user_session cookie
    "password",
    "passwd",
    "pwd",
    "key",
    "jwt",
    "bearer",
    "sso",
    "saml",
    "csrf",
    "xsrf",
    "credentials",
    "sid",
    "identity",
    // Always treat cookie headers as sensitive in case individual key-value cookie pairs cannot properly be extracted
    "set-cookie",
    "cookie"
  ];

  function isSensitiveKey(lower, denySnippets) {
    return denySnippets.some((snippet) => lower.includes(snippet));
  }
  function shouldFilterDataKey(key, behavior, additionalDenyTerms) {
    if (behavior === false) {
      return true;
    }
    const lowerKey = key.toLowerCase();
    const denySnippets = SENSITIVE_KEY_SNIPPETS;
    if (isSensitiveKey(lowerKey, denySnippets)) {
      return true;
    }
    if (behavior === true) {
      return false;
    }
    const terms = "deny" in behavior ? behavior.deny : behavior.allow;
    const matchesConfiguredTerm = terms.some((term) => lowerKey.includes(term.toLowerCase()));
    return "deny" in behavior ? matchesConfiguredTerm : !matchesConfiguredTerm;
  }
  function filterKeyValueData(data, behavior, additionalDenyTerms) {
    if (behavior === false) {
      return {};
    }
    const result = {};
    for (const key of Object.keys(data)) {
      result[key] = shouldFilterDataKey(key, behavior) ? FILTERED_VALUE : data[key];
    }
    return result;
  }

  function filterQueryParams(queryString, behavior) {
    if (!queryString || behavior === false) {
      return void 0;
    }
    return queryString.split("&").map((pair) => {
      const separatorIndex = pair.indexOf("=");
      const encodedKey = separatorIndex === -1 ? pair : pair.slice(0, separatorIndex);
      const key = new URLSearchParams(`${encodedKey}=`).keys().next().value;
      return key !== void 0 && shouldFilterDataKey(key, behavior) ? `${encodedKey}=${FILTERED_VALUE}` : pair;
    }).join("&");
  }

  function filterUrlQuery(url, behavior) {
    const fragmentStart = url.indexOf("#");
    const queryEnd = fragmentStart === -1 ? url.length : fragmentStart;
    const queryStart = url.indexOf("?");
    if (queryStart === -1 || queryStart > queryEnd) {
      return url;
    }
    const prefix = url.slice(0, queryStart);
    const query = url.slice(queryStart + 1, queryEnd);
    const suffix = url.slice(queryEnd);
    const filtered = filterQueryParams(query, behavior);
    return filtered ? `${prefix}?${filtered}${suffix}` : `${prefix}${suffix}`;
  }

  function urlQueryParamsBehavior(client) {
    return (client ?? getClient())?.getDataCollectionOptions().urlQueryParams ?? true;
  }
  function filterCollectedUrl(url, client) {
    return url === void 0 ? void 0 : filterUrlQuery(url, urlQueryParamsBehavior(client));
  }
  function filterCollectedUrlQuery(query, client) {
    return query ? filterQueryParams(query, urlQueryParamsBehavior(client)) : void 0;
  }

  const DEFAULT_BASE_URL = "thismessage:/";
  function isURLObjectRelative(url) {
    return "isRelative" in url;
  }
  function parseStringToURLObject(url, urlBase) {
    const isRelative = url.indexOf("://") <= 0 && url.indexOf("//") !== 0;
    const base = (isRelative ? DEFAULT_BASE_URL : void 0);
    try {
      if ("canParse" in URL && !URL.canParse(url, base)) {
        return void 0;
      }
      const fullUrlObject = new URL(url, base);
      if (isRelative) {
        return {
          isRelative,
          pathname: fullUrlObject.pathname,
          search: fullUrlObject.search,
          hash: fullUrlObject.hash
        };
      }
      return fullUrlObject;
    } catch {
    }
    return void 0;
  }
  function getSanitizedUrlStringFromUrlObject(url) {
    if (isURLObjectRelative(url)) {
      return url.pathname;
    }
    const newUrl = new URL(url);
    newUrl.search = "";
    newUrl.hash = "";
    if (["80", "443"].includes(newUrl.port)) {
      newUrl.port = "";
    }
    if (newUrl.password) {
      newUrl.password = "%filtered%";
    }
    if (newUrl.username) {
      newUrl.username = "%filtered%";
    }
    return newUrl.toString();
  }
  function getUrlQuery(query) {
    return query?.replace(/^\?/, "") || void 0;
  }
  function getUrlFragment(fragment) {
    return fragment?.replace(/^#/, "") || void 0;
  }
  function getUrlDomain(url, base) {
    try {
      return new URL(url, base).hostname || void 0;
    } catch {
      return void 0;
    }
  }
  function parseUrl(url) {
    if (!url) {
      return {};
    }
    const match = url.match(/^(([^:/?#]+):)?(\/\/([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?$/);
    if (!match) {
      return {};
    }
    const query = match[6] || "";
    const fragment = match[8] || "";
    return {
      host: match[4],
      path: match[5],
      protocol: match[2],
      search: query,
      hash: fragment,
      relative: match[5] + query + fragment
      // everything minus origin
    };
  }
  function stripUrlQueryAndFragment(urlPath) {
    return urlPath.split(/[?#]/, 1)[0];
  }
  function stripDataUrlContent(url, includeDataPrefix = true) {
    if (url.startsWith("data:")) {
      const match = url.match(/^data:([^;,]+)/);
      const mimeType = match ? match[1] : "text/plain";
      const isBase64 = url.includes(";base64,");
      const dataStart = url.indexOf(",");
      let dataPrefix = "";
      if (includeDataPrefix && dataStart !== -1) {
        const data = url.slice(dataStart + 1);
        dataPrefix = data.length > 10 ? `${data.slice(0, 10)}... [truncated]` : data;
      }
      return `data:${mimeType}${isBase64 ? ",base64" : ""}${dataPrefix ? `,${dataPrefix}` : ""}`;
    }
    return url;
  }

  function parameterize(strings, ...values) {
    const formatted = new String(String.raw(strings, ...values));
    formatted.__sentry_template_string__ = strings.join("\0").replace(/%/g, "%%").replace(/\0/g, "%s");
    formatted.__sentry_template_values__ = values;
    return formatted;
  }

  function addAutoIpAddressToSession(session) {
    if ("aggregates" in session) {
      if (session.attrs?.["ip_address"] === void 0) {
        session.attrs = {
          ...session.attrs,
          ip_address: "{{auto}}"
        };
      }
    } else {
      if (session.ipAddress === void 0) {
        session.ipAddress = "{{auto}}";
      }
    }
  }

  function applySdkMetadata(options, name, names = [name], source = "npm") {
    const sdk = (options._metadata = options._metadata || {}).sdk = options._metadata.sdk || {};
    if (!sdk.name) {
      sdk.name = `sentry.javascript.${name}`;
      sdk.packages = names.map((name2) => ({
        name: `${source}:@sentry/${name2}`,
        version: SDK_VERSION
      }));
      sdk.version = SDK_VERSION;
    }
  }

  function getTraceData(options = {}) {
    const client = options.client || getClient();
    if (!isEnabled() || !client) {
      return {};
    }
    const carrier = getMainCarrier();
    const acs = getAsyncContextStrategy(carrier);
    if (acs.getTraceData) {
      return acs.getTraceData(options);
    }
    const scope = options.scope || getCurrentScope();
    const span = options.span || getActiveSpan();
    const isTwpPlaceholder = spanIsNonRecordingSpan(span) && !hasSpansEnabled(client.getOptions());
    if (!span && hasExternalPropagationContext()) {
      return {};
    }
    const sentryTrace = span && !isTwpPlaceholder ? spanToTraceHeader(span) : scopeToTraceHeader(scope);
    const dsc = span ? getDynamicSamplingContextFromSpan(span) : getDynamicSamplingContextFromScope(client, scope);
    const baggage = dynamicSamplingContextToSentryBaggageHeader(dsc);
    const isValidSentryTraceHeader = TRACEPARENT_REGEXP.test(sentryTrace);
    if (!isValidSentryTraceHeader) {
      debug.warn("Invalid sentry-trace data. Cannot generate trace data");
      return {};
    }
    const traceData = {
      "sentry-trace": sentryTrace,
      baggage
    };
    if (options.propagateTraceparent) {
      traceData.traceparent = span && !isTwpPlaceholder ? spanToTraceparentHeader(span) : scopeToTraceparentHeader(scope);
    }
    return traceData;
  }
  function scopeToTraceHeader(scope) {
    const { traceId, sampled, propagationSpanId } = scope.getPropagationContext();
    return generateSentryTraceHeader(traceId, propagationSpanId, sampled);
  }
  function scopeToTraceparentHeader(scope) {
    const { traceId, sampled, propagationSpanId } = scope.getPropagationContext();
    return generateTraceparentHeader(traceId, propagationSpanId, sampled);
  }

  const NORMALIZED_REGEXP_CACHE = /* @__PURE__ */ new WeakMap();
  function normalizeRegExpTarget(pattern) {
    const flags = `${pattern.flags.replace(/[gy]/g, "")}${pattern.ignoreCase ? "" : "i"}`;
    if (flags === pattern.flags) {
      return pattern;
    }
    const cached = NORMALIZED_REGEXP_CACHE.get(pattern);
    if (cached) {
      return cached;
    }
    const normalizedPattern = new RegExp(pattern.source, flags);
    NORMALIZED_REGEXP_CACHE.set(pattern, normalizedPattern);
    return normalizedPattern;
  }
  function matchesTracePropagationTargets(value, tracePropagationTargets, requireExactStringMatch = false) {
    const lowerCaseValue = value.toLowerCase();
    for (const target of tracePropagationTargets) {
      if (isString(target)) {
        const lowerCaseTarget = target.toLowerCase();
        if (requireExactStringMatch ? lowerCaseValue === lowerCaseTarget : lowerCaseValue.includes(lowerCaseTarget)) {
          return true;
        }
      } else if (isRegExp(target) && normalizeRegExpTarget(target).test(value)) {
        return true;
      }
    }
    return false;
  }

  const DEFAULT_BREADCRUMBS = 100;
  function addBreadcrumb(breadcrumb, hint) {
    const client = getClient();
    const isolationScope = getIsolationScope();
    if (!client) return;
    const { beforeBreadcrumb = null, maxBreadcrumbs = DEFAULT_BREADCRUMBS } = client.getOptions();
    if (maxBreadcrumbs <= 0) return;
    const timestamp = dateTimestampInSeconds();
    const mergedBreadcrumb = { timestamp, ...breadcrumb };
    const finalBreadcrumb = beforeBreadcrumb ? safeCallback(
      "The `beforeBreadcrumb` callback threw an error, dropping the breadcrumb:" ,
      () => consoleSandbox(() => beforeBreadcrumb(mergedBreadcrumb, hint)),
      () => null
    ) : mergedBreadcrumb;
    if (finalBreadcrumb === null) return;
    if (client.emit) {
      client.emit("beforeAddBreadcrumb", finalBreadcrumb, hint);
    }
    isolationScope.addBreadcrumb(finalBreadcrumb, maxBreadcrumbs);
  }

  const INTEGRATION_NAME$9 = "FunctionToString";
  const SETUP_CLIENTS = /* @__PURE__ */ new WeakMap();
  const _functionToStringIntegration = (() => {
    return {
      name: INTEGRATION_NAME$9,
      setupOnce() {
        const originalFunctionToString = Function.prototype.toString;
        try {
          Function.prototype.toString = function(...args) {
            const originalFunction = getOriginalFunction(this);
            let unwrappedFunction;
            try {
              if (SETUP_CLIENTS.has(getClient()) && originalFunction !== void 0) {
                unwrappedFunction = originalFunction;
              }
            } catch {
            }
            return originalFunctionToString.apply(unwrappedFunction ?? this, args);
          };
        } catch {
        }
      },
      setup(client) {
        SETUP_CLIENTS.set(client, true);
      }
    };
  });
  const functionToStringIntegration = defineIntegration(_functionToStringIntegration);

  const DEFAULT_IGNORE_ERRORS = [
    /^Script error\.?$/,
    /^Javascript error: Script error\.? on line 0$/,
    /^ResizeObserver loop completed with undelivered notifications.$/,
    // The browser logs this when a ResizeObserver handler takes a bit longer. Usually this is not an actual issue though. It indicates slowness.
    /^Cannot redefine property: googletag$/,
    // This is thrown when google tag manager is used in combination with an ad blocker
    /^Can't find variable: gmo$/,
    // Error from Google Search App https://issuetracker.google.com/issues/396043331
    /^undefined is not an object \(evaluating 'a\.[A-Z]'\)$/,
    // Random error that happens but not actionable or noticeable to end-users.
    /can't redefine non-configurable property "solana"/,
    // Probably a browser extension or custom browser (Brave) throwing this error
    /vv\(\)\.getRestrictions is not a function/,
    // Error thrown by GTM, seemingly not affecting end-users
    /Can't find variable: _AutofillCallbackHandler/,
    // Unactionable error in instagram webview https://developers.facebook.com/community/threads/320013549791141/
    /Object Not Found Matching Id:\d+, MethodName:simulateEvent/,
    // unactionable error from CEFSharp, a .NET library that embeds chromium in .NET apps
    /Java exception was raised during method invocation$/,
    // error from Facebook Mobile browser (https://github.com/getsentry/sentry-javascript/issues/15065, https://github.com/getsentry/sentry-javascript/issues/23733)
    /Java object is gone$/
    // error from Facebook Mobile browser (https://github.com/getsentry/sentry-javascript/issues/15065, https://github.com/getsentry/sentry-javascript/issues/23733)
  ];
  const INTEGRATION_NAME$8 = "EventFilters";
  const eventFiltersIntegration = defineIntegration((options = {}) => {
    let mergedOptions;
    return {
      name: INTEGRATION_NAME$8,
      setup(client) {
        const clientOptions = client.getOptions();
        mergedOptions = _mergeOptions(options, clientOptions);
      },
      processEvent(event, _hint, client) {
        if (!mergedOptions) {
          const clientOptions = client.getOptions();
          mergedOptions = _mergeOptions(options, clientOptions);
        }
        return _shouldDropEvent$1(event, mergedOptions) ? null : event;
      }
    };
  });
  function _mergeOptions(internalOptions = {}, clientOptions = {}) {
    return {
      allowUrls: [...internalOptions.allowUrls || [], ...clientOptions.allowUrls || []],
      denyUrls: [...internalOptions.denyUrls || [], ...clientOptions.denyUrls || []],
      ignoreErrors: [
        ...internalOptions.ignoreErrors || [],
        ...clientOptions.ignoreErrors || [],
        ...internalOptions.disableErrorDefaults ? [] : DEFAULT_IGNORE_ERRORS
      ],
      ignoreTransactions: [...internalOptions.ignoreTransactions || [], ...clientOptions.ignoreTransactions || []]
    };
  }
  function _shouldDropEvent$1(event, options) {
    if (!event.type) {
      if (_isIgnoredError(event, options.ignoreErrors)) {
        debug.warn(
          `Event dropped due to being matched by \`ignoreErrors\` option.
Event: ${getEventDescription(event)}`
        );
        return true;
      }
      if (_isUselessError(event)) {
        debug.warn(
          `Event dropped due to not having an error message, error type or stacktrace.
Event: ${getEventDescription(
          event
        )}`
        );
        return true;
      }
      if (_isDeniedUrl(event, options.denyUrls)) {
        debug.warn(
          `Event dropped due to being matched by \`denyUrls\` option.
Event: ${getEventDescription(
          event
        )}.
Url: ${_getEventFilterUrl(event)}`
        );
        return true;
      }
      if (!_isAllowedUrl(event, options.allowUrls)) {
        debug.warn(
          `Event dropped due to not being matched by \`allowUrls\` option.
Event: ${getEventDescription(
          event
        )}.
Url: ${_getEventFilterUrl(event)}`
        );
        return true;
      }
    } else if (event.type === "transaction") {
      if (_isIgnoredTransaction(event, options.ignoreTransactions)) {
        debug.warn(
          `Event dropped due to being matched by \`ignoreTransactions\` option.
Event: ${getEventDescription(event)}`
        );
        return true;
      }
    }
    return false;
  }
  function _isIgnoredError(event, ignoreErrors) {
    if (!ignoreErrors?.length) {
      return false;
    }
    return getPossibleEventMessages(event).some((message) => stringMatchesSomePattern(message, ignoreErrors));
  }
  function _isIgnoredTransaction(event, ignoreTransactions) {
    if (!ignoreTransactions?.length) {
      return false;
    }
    const name = event.transaction;
    return name ? stringMatchesSomePattern(name, ignoreTransactions) : false;
  }
  function _isDeniedUrl(event, denyUrls) {
    if (!denyUrls?.length) {
      return false;
    }
    const url = _getEventFilterUrl(event);
    return !url ? false : stringMatchesSomePattern(url, denyUrls);
  }
  function _isAllowedUrl(event, allowUrls) {
    if (!allowUrls?.length) {
      return true;
    }
    const url = _getEventFilterUrl(event);
    return !url ? true : stringMatchesSomePattern(url, allowUrls);
  }
  function _getLastValidUrl(frames = []) {
    for (let i = frames.length - 1; i >= 0; i--) {
      const frame = frames[i];
      if (frame && frame.filename !== "<anonymous>" && frame.filename !== "[native code]") {
        return frame.filename || null;
      }
    }
    return null;
  }
  function _getEventFilterUrl(event) {
    try {
      const rootException = [...event.exception?.values ?? []].reverse().find((value) => value.mechanism?.parent_id === void 0 && value.stacktrace?.frames?.length);
      const frames = rootException?.stacktrace?.frames;
      return frames ? _getLastValidUrl(frames) : null;
    } catch {
      debug.error(`Cannot extract url for event ${getEventDescription(event)}`);
      return null;
    }
  }
  function _isUselessError(event) {
    if (!event.exception?.values?.length) {
      return false;
    }
    return (
      // No top-level message
      !event.message && // There are no exception values that have a stacktrace, a non-generic-Error type or value
      !event.exception.values.some((value) => value.stacktrace || value.type && value.type !== "Error" || value.value)
    );
  }

  function applyAggregateErrorsToEvent(exceptionFromErrorImplementation, parser, key, limit, event, hint) {
    if (!event.exception?.values || !hint || !isError(hint.originalException)) {
      return;
    }
    const originalException = event.exception.values.length > 0 ? event.exception.values[event.exception.values.length - 1] : void 0;
    if (originalException) {
      event.exception.values = aggregateExceptionsFromError(
        exceptionFromErrorImplementation,
        parser,
        limit,
        hint.originalException,
        key,
        event.exception.values,
        originalException,
        0
      );
    }
  }
  function aggregateExceptionsFromError(exceptionFromErrorImplementation, parser, limit, error, key, prevExceptions, exception, exceptionId) {
    if (prevExceptions.length >= limit + 1) {
      return prevExceptions;
    }
    let newExceptions = [...prevExceptions];
    if (isError(error[key])) {
      applyExceptionGroupFieldsForParentException(exception, exceptionId, error);
      const newException = exceptionFromErrorImplementation(parser, error[key]);
      const newExceptionId = newExceptions.length;
      applyExceptionGroupFieldsForChildException(newException, key, newExceptionId, exceptionId);
      newExceptions = aggregateExceptionsFromError(
        exceptionFromErrorImplementation,
        parser,
        limit,
        error[key],
        key,
        [newException, ...newExceptions],
        newException,
        newExceptionId
      );
    }
    if (isExceptionGroup(error)) {
      error.errors.forEach((childError, i) => {
        if (isError(childError)) {
          applyExceptionGroupFieldsForParentException(exception, exceptionId, error);
          const newException = exceptionFromErrorImplementation(parser, childError);
          const newExceptionId = newExceptions.length;
          applyExceptionGroupFieldsForChildException(newException, `errors[${i}]`, newExceptionId, exceptionId);
          newExceptions = aggregateExceptionsFromError(
            exceptionFromErrorImplementation,
            parser,
            limit,
            childError,
            key,
            [newException, ...newExceptions],
            newException,
            newExceptionId
          );
        }
      });
    }
    return newExceptions;
  }
  function isExceptionGroup(error) {
    return Array.isArray(error.errors);
  }
  function applyExceptionGroupFieldsForParentException(exception, exceptionId, error) {
    exception.mechanism = {
      handled: true,
      type: "auto.core.linked_errors",
      ...isExceptionGroup(error) && { is_exception_group: true },
      ...exception.mechanism,
      exception_id: exceptionId
    };
  }
  function applyExceptionGroupFieldsForChildException(exception, source, exceptionId, parentId) {
    exception.mechanism = {
      handled: true,
      ...exception.mechanism,
      type: "chained",
      source,
      exception_id: exceptionId,
      parent_id: parentId
    };
  }

  function hasSentryFetchUrlHost(error) {
    return isError(error) && "__sentry_fetch_url_host__" in error && typeof error.__sentry_fetch_url_host__ === "string";
  }
  function _enhanceErrorWithSentryInfo(error) {
    if (hasSentryFetchUrlHost(error)) {
      return `${error.message} (${error.__sentry_fetch_url_host__})`;
    }
    return error.message;
  }

  const _filter = /* @__PURE__ */ new Set([]);
  function addConsoleInstrumentationHandler(handler) {
    const type = "console";
    const removeHandler = addHandler$1(type, handler);
    maybeInstrument(type, instrumentConsole);
    return removeHandler;
  }
  function addConsoleInstrumentationFilter(filter) {
    for (const f of filter) {
      _filter.add(f);
    }
    return () => {
      for (const f of filter) {
        _filter.delete(f);
      }
    };
  }
  const instrumentedLevels = /* @__PURE__ */ new Set();
  function instrumentConsole() {
    if (!("console" in GLOBAL_OBJ)) {
      return;
    }
    CONSOLE_LEVELS.forEach(function(level) {
      if (instrumentedLevels.has(level) || !(level in GLOBAL_OBJ.console)) {
        return;
      }
      instrumentedLevels.add(level);
      fill(GLOBAL_OBJ.console, level, function(originalConsoleMethod) {
        originalConsoleMethods[level] = originalConsoleMethod;
        return function(...args) {
          const firstArg = args[0];
          const log = originalConsoleMethods[level];
          const isFiltered = _filter.size && typeof firstArg === "string" && stringMatchesSomePattern(firstArg, _filter);
          if (!isFiltered) {
            triggerHandlers$1("console", { args, level });
          }
          if (!isFiltered || debug.isEnabled()) {
            log?.apply(GLOBAL_OBJ.console, args);
          }
        };
      });
    });
  }

  function severityLevelFromString(level) {
    return level === "warn" ? "warning" : ["fatal", "error", "warning", "log", "info", "debug"].includes(level) ? level : "log";
  }

  const INTEGRATION_NAME$7 = "Dedupe";
  const _dedupeIntegration = (() => {
    let previousEvent;
    return {
      name: INTEGRATION_NAME$7,
      processEvent(currentEvent) {
        if (currentEvent.type) {
          return currentEvent;
        }
        try {
          if (_shouldDropEvent(currentEvent, previousEvent)) {
            debug.warn("Event dropped due to being a duplicate of previously captured event.");
            return null;
          }
        } catch {
        }
        return previousEvent = currentEvent;
      }
    };
  });
  const dedupeIntegration = defineIntegration(_dedupeIntegration);
  function _shouldDropEvent(currentEvent, previousEvent) {
    if (!previousEvent) {
      return false;
    }
    if (_isSameMessageEvent(currentEvent, previousEvent)) {
      return true;
    }
    if (_isSameExceptionEvent(currentEvent, previousEvent)) {
      return true;
    }
    return false;
  }
  function _isSameMessageEvent(currentEvent, previousEvent) {
    const currentMessage = currentEvent.message;
    const previousMessage = previousEvent.message;
    if (!currentMessage && !previousMessage) {
      return false;
    }
    if (currentMessage && !previousMessage || !currentMessage && previousMessage) {
      return false;
    }
    if (currentMessage !== previousMessage) {
      return false;
    }
    if (!_isSameFingerprint(currentEvent, previousEvent)) {
      return false;
    }
    if (!_isSameStacktrace(currentEvent, previousEvent)) {
      return false;
    }
    return true;
  }
  function _isSameExceptionEvent(currentEvent, previousEvent) {
    const previousException = _getExceptionFromEvent(previousEvent);
    const currentException = _getExceptionFromEvent(currentEvent);
    if (!previousException || !currentException) {
      return false;
    }
    if (previousException.type !== currentException.type || previousException.value !== currentException.value) {
      return false;
    }
    if (!_isSameFingerprint(currentEvent, previousEvent)) {
      return false;
    }
    if (!_isSameStacktrace(currentEvent, previousEvent)) {
      return false;
    }
    return true;
  }
  function _isSameStacktrace(currentEvent, previousEvent) {
    const currentFrames = getFramesFromEvent(currentEvent);
    const previousFrames = getFramesFromEvent(previousEvent);
    if (!currentFrames || !previousFrames) {
      return !currentFrames && !previousFrames;
    }
    if (previousFrames.length !== currentFrames.length) {
      return false;
    }
    for (let i = 0; i < previousFrames.length; i++) {
      const frameA = previousFrames[i];
      const frameB = currentFrames[i];
      if (frameA.filename !== frameB.filename || frameA.lineno !== frameB.lineno || frameA.colno !== frameB.colno || frameA.function !== frameB.function) {
        return false;
      }
    }
    return true;
  }
  function _isSameFingerprint(currentEvent, previousEvent) {
    const currentFingerprint = currentEvent.fingerprint;
    const previousFingerprint = previousEvent.fingerprint;
    if (!currentFingerprint || !previousFingerprint) {
      return !currentFingerprint && !previousFingerprint;
    }
    try {
      return !!(currentFingerprint.join("") === previousFingerprint.join(""));
    } catch {
      return false;
    }
  }
  function _getExceptionFromEvent(event) {
    return event.exception?.values?.[0];
  }

  const INTEGRATION_NAME$6 = "Console";
  const consoleIntegration = defineIntegration((options = {}) => {
    const levels = new Set(options.levels || CONSOLE_LEVELS);
    return {
      name: INTEGRATION_NAME$6,
      setup(client) {
        const unsubscribe = addConsoleInstrumentationHandler(({ args, level }) => {
          if (getClient() !== client || !levels.has(level)) {
            return;
          }
          addConsoleBreadcrumb(level, args);
        });
        client.registerCleanup(unsubscribe);
        if (options.filter) {
          const unsubscribe2 = addConsoleInstrumentationFilter(options.filter);
          client.registerCleanup(unsubscribe2);
        }
      }
    };
  });
  function addConsoleBreadcrumb(level, args) {
    const breadcrumb = {
      category: "console",
      data: {
        arguments: args,
        logger: "console"
      },
      level: severityLevelFromString(level),
      message: formatConsoleArgs(args)
    };
    if (level === "assert") {
      if (args[0] === false) {
        const assertionArgs = args.slice(1);
        breadcrumb.message = assertionArgs.length > 0 ? `Assertion failed: ${formatConsoleArgs(assertionArgs)}` : "Assertion failed";
        breadcrumb.data.arguments = assertionArgs;
      } else {
        return;
      }
    }
    addBreadcrumb(breadcrumb, {
      input: args,
      level
    });
  }
  function formatConsoleArgs(values) {
    return "util" in GLOBAL_OBJ && typeof GLOBAL_OBJ.util.format === "function" ? GLOBAL_OBJ.util.format(...values) : safeJoin(values, " ");
  }

  const INTEGRATION_NAME$5 = "ConversationId";
  const _conversationIdIntegration = (() => {
    return {
      name: INTEGRATION_NAME$5,
      setup(client) {
        client.on("spanStart", (span) => {
          const scopeData = getCurrentScope().getScopeData();
          const isolationScopeData = getIsolationScope().getScopeData();
          const conversationId = scopeData.conversationId || isolationScopeData.conversationId;
          if (conversationId) {
            const { op, data: attributes, description: name } = spanToStaticSpanJSON(span);
            if (!op?.startsWith("gen_ai.") && !attributes["ai.operationId"] && !name?.startsWith("ai.")) {
              return;
            }
            span.setAttribute(GEN_AI_CONVERSATION_ID_ATTRIBUTE, conversationId);
          }
        });
      }
    };
  });
  const conversationIdIntegration = defineIntegration(_conversationIdIntegration);

  function instrumentFetchRequest(handlerData, shouldCreateSpan, shouldAttachHeaders, spans, instrumentFetchRequestOptions) {
    if (!handlerData.fetchData) {
      return void 0;
    }
    const { method, url } = handlerData.fetchData;
    const shouldCreateSpanResult = hasSpansEnabled() && shouldCreateSpan(url);
    if (handlerData.endTimestamp) {
      const spanId = handlerData.fetchData.__span;
      if (!spanId) return;
      const span2 = spans[spanId];
      if (span2) {
        if (shouldCreateSpanResult) {
          endSpan(span2, handlerData);
          _callOnRequestSpanEnd(span2, handlerData, instrumentFetchRequestOptions);
        }
        delete spans[spanId];
      }
      return void 0;
    }
    const {
      spanOrigin = "auto.http.browser",
      propagateTraceparent = false,
      urlBase
    } = instrumentFetchRequestOptions ?? {};
    const client = getClient();
    const hasParent = !!getActiveSpan();
    const shouldEmitSpan = hasParent || !!client && hasSpanStreamingEnabled(client);
    const span = shouldCreateSpanResult && shouldEmitSpan ? startInactiveSpan$1(getSpanStartOptions(url, method, spanOrigin, client, urlBase)) : new SentryNonRecordingSpan();
    const spanForTraceHeaders = spanIsIgnored(span) && hasParent ? void 0 : span;
    if (shouldCreateSpanResult && !shouldEmitSpan) {
      client?.recordDroppedEvent("no_parent_span", "span");
    }
    handlerData.fetchData.__span = span.spanContext().spanId;
    spans[span.spanContext().spanId] = span;
    if (shouldAttachHeaders(handlerData.fetchData.url)) {
      const request = handlerData.args[0];
      const options = { ...handlerData.args[1] || {} };
      const headers = _INTERNAL_getTracingHeadersForFetchRequest(
        request,
        options,
        // If performance is disabled (TWP) or there's no active root span (pageload/navigation/interaction),
        // we do not want to use the span as base for the trace headers,
        // which means that the headers will be generated from the scope and the sampling decision is deferred
        hasSpansEnabled() && shouldEmitSpan ? spanForTraceHeaders : void 0,
        propagateTraceparent
      );
      if (headers) {
        handlerData.args[1] = options;
        options.headers = headers;
      }
    }
    if (client) {
      const fetchHint = {
        input: handlerData.args,
        response: handlerData.response,
        startTimestamp: handlerData.startTimestamp,
        endTimestamp: handlerData.endTimestamp
      };
      client.emit("beforeOutgoingRequestSpan", span, fetchHint);
    }
    return span;
  }
  function _callOnRequestSpanEnd(span, handlerData, instrumentFetchRequestOptions) {
    instrumentFetchRequestOptions?.onRequestSpanEnd?.(span, {
      headers: handlerData.response?.headers,
      error: handlerData.error
    });
  }
  function _INTERNAL_getTracingHeadersForFetchRequest(request, fetchOptionsObj, span, propagateTraceparent) {
    const traceHeaders = getTraceData({ span, propagateTraceparent });
    const sentryTrace = traceHeaders["sentry-trace"];
    const baggage = traceHeaders.baggage;
    const traceparent = traceHeaders.traceparent;
    if (!sentryTrace) {
      return void 0;
    }
    const originalHeaders = fetchOptionsObj.headers || (isRequest(request) ? request.headers : void 0);
    if (!originalHeaders) {
      return {
        "sentry-trace": sentryTrace,
        ...baggage && { baggage },
        ...traceparent && { traceparent }
      };
    } else if (isHeaders(originalHeaders)) {
      const newHeaders = new Headers(originalHeaders);
      if (!newHeaders.get("sentry-trace")) {
        newHeaders.set("sentry-trace", sentryTrace);
      }
      if (propagateTraceparent && traceparent && !newHeaders.get("traceparent")) {
        newHeaders.set("traceparent", traceparent);
      }
      if (baggage) {
        const prevBaggageHeader = newHeaders.get("baggage");
        if (!prevBaggageHeader) {
          newHeaders.set("baggage", baggage);
        } else if (!baggageHeaderHasSentryBaggageValues(prevBaggageHeader)) {
          newHeaders.set("baggage", `${prevBaggageHeader},${baggage}`);
        }
      }
      return newHeaders;
    } else if (isHeadersInitTupleArray(originalHeaders)) {
      const newHeaders = [...originalHeaders];
      if (!newHeaders.find((header) => header[0] === "sentry-trace")) {
        newHeaders.push(["sentry-trace", sentryTrace]);
      }
      if (propagateTraceparent && traceparent && !newHeaders.find((header) => header[0] === "traceparent")) {
        newHeaders.push(["traceparent", traceparent]);
      }
      const prevBaggageHeaderWithSentryValues = originalHeaders.find(
        (header) => header[0] === "baggage" && typeof header[1] === "string" && baggageHeaderHasSentryBaggageValues(header[1])
      );
      if (baggage && !prevBaggageHeaderWithSentryValues) {
        newHeaders.push(["baggage", baggage]);
      }
      return newHeaders;
    } else {
      const existingSentryTraceHeader = "sentry-trace" in originalHeaders ? originalHeaders["sentry-trace"] : void 0;
      const existingTraceparentHeader = "traceparent" in originalHeaders ? originalHeaders.traceparent : void 0;
      const existingBaggageHeader = "baggage" in originalHeaders ? originalHeaders.baggage : void 0;
      const newBaggageHeaders = existingBaggageHeader ? Array.isArray(existingBaggageHeader) ? [...existingBaggageHeader] : [existingBaggageHeader] : [];
      const prevBaggageHeaderWithSentryValues = existingBaggageHeader && (Array.isArray(existingBaggageHeader) ? existingBaggageHeader.find((headerItem) => baggageHeaderHasSentryBaggageValues(headerItem)) : baggageHeaderHasSentryBaggageValues(existingBaggageHeader));
      if (baggage && !prevBaggageHeaderWithSentryValues) {
        newBaggageHeaders.push(baggage);
      }
      const newHeaders = Object.assign({}, originalHeaders, {
        "sentry-trace": existingSentryTraceHeader ?? sentryTrace,
        ...newBaggageHeaders.length > 0 && { baggage: newBaggageHeaders.join(",") }
      });
      if (propagateTraceparent && traceparent && !existingTraceparentHeader) {
        newHeaders.traceparent = traceparent;
      }
      return newHeaders;
    }
  }
  function endSpan(span, handlerData) {
    if (handlerData.response) {
      setHttpStatus(span, handlerData.response.status);
      const contentLength = handlerData.response?.headers?.get("content-length");
      if (contentLength) {
        const contentLengthNum = parseInt(contentLength);
        if (contentLengthNum > 0) {
          span.setAttribute(Ao, contentLengthNum);
        }
      }
    } else if (handlerData.error) {
      span.setStatus({ code: SPAN_STATUS_ERROR, message: "internal_error" });
    }
    span.end();
  }
  function baggageHeaderHasSentryBaggageValues(baggageHeader) {
    if (typeof baggageHeader !== "string") {
      return false;
    }
    return baggageHeader.split(",").some((baggageEntry) => baggageEntry.trim().startsWith(SENTRY_BAGGAGE_KEY_PREFIX));
  }
  function isHeaders(headers) {
    return typeof Headers !== "undefined" && isInstanceOf(headers, Headers);
  }
  function isHeadersInitTupleArray(headers) {
    if (!Array.isArray(headers)) {
      return false;
    }
    return headers.every(
      (item) => Array.isArray(item) && item.length === 2 && typeof item[0] === "string"
    );
  }
  function getSpanStartOptions(url, method, spanOrigin, client, urlBase) {
    const isStreamed = !!client && hasSpanStreamingEnabled(client);
    const domain = getUrlDomain(url, urlBase);
    if (url.startsWith("data:")) {
      const sanitizedUrl2 = stripDataUrlContent(url);
      return {
        name: isStreamed ? method : `${method} ${sanitizedUrl2}`,
        attributes: getFetchSpanAttributes(url, void 0, method, spanOrigin, client, domain)
      };
    }
    const parsedUrl = parseStringToURLObject(url);
    const sanitizedUrl = parsedUrl ? getSanitizedUrlStringFromUrlObject(parsedUrl) : url;
    return {
      name: isStreamed ? domain ? `${method} ${domain}` : method : `${method} ${sanitizedUrl}`,
      attributes: getFetchSpanAttributes(url, parsedUrl, method, spanOrigin, client, domain)
    };
  }
  function getFetchSpanAttributes(url, parsedUrl, method, spanOrigin, client, domain) {
    const attributes = {
      [zg]: filterCollectedUrl(stripDataUrlContent(url), client),
      type: "fetch",
      // oxlint-disable-next-line typescript/no-deprecated
      [bo]: method,
      [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: spanOrigin,
      [cd]: rE,
      [Ug]: domain
    };
    if (parsedUrl) {
      if (!isURLObjectRelative(parsedUrl)) {
        attributes[zg] = filterCollectedUrl(stripDataUrlContent(parsedUrl.href), client);
        attributes[Zd] = parsedUrl.hostname;
        attributes[eg] = parsedUrl.port ? Number(parsedUrl.port) : void 0;
      }
      attributes[Kg] = filterCollectedUrlQuery(getUrlQuery(parsedUrl.search), client);
      attributes[Gg] = getUrlFragment(parsedUrl.hash);
    }
    return attributes;
  }

  const WINDOW$2 = GLOBAL_OBJ;
  function _isFetchSupported() {
    if (!("fetch" in WINDOW$2)) {
      return false;
    }
    try {
      new Headers();
      new Request("data:,");
      new Response();
      return true;
    } catch {
      return false;
    }
  }
  function isNativeFunction(func) {
    return func && /^function\s+\w+\(\)\s+\{\s+\[native code\]\s+\}$/.test(func.toString());
  }
  function supportsNativeFetch() {
    if (typeof EdgeRuntime === "string") {
      return true;
    }
    if (!_isFetchSupported()) {
      return false;
    }
    if (isNativeFunction(WINDOW$2.fetch)) {
      return true;
    }
    let result = false;
    const doc = WINDOW$2.document;
    if (doc && typeof doc.createElement === "function") {
      try {
        const sandbox = doc.createElement("iframe");
        sandbox.hidden = true;
        doc.head.appendChild(sandbox);
        if (sandbox.contentWindow?.fetch) {
          result = isNativeFunction(sandbox.contentWindow.fetch);
        }
        doc.head.removeChild(sandbox);
      } catch (err) {
        debug.warn("Could not create sandbox iframe for pure fetch check, bailing to window.fetch: ", err);
      }
    }
    return result;
  }

  function addFetchInstrumentationHandler(handler) {
    const type = "fetch";
    const removeHandler = addHandler$1(type, handler);
    maybeInstrument(type, () => instrumentFetch());
    return removeHandler;
  }
  function addFetchEndInstrumentationHandler(handler) {
    const type = "fetch-body-resolved";
    const removeHandler = addHandler$1(type, handler);
    maybeInstrument(type, () => instrumentFetch(streamHandler));
    return removeHandler;
  }
  function instrumentFetch(onFetchResolved) {
    if (isBrowser() && !supportsNativeFetch()) {
      return;
    }
    fill(GLOBAL_OBJ, "fetch", function(originalFetch) {
      return new Proxy(originalFetch, {
        apply(target, _thisArg, args) {
          const virtualError = new Error();
          const { method, url } = parseFetchArgs(args);
          const handlerData = {
            args,
            fetchData: {
              method,
              url
            },
            startTimestamp: timestampInSeconds() * 1e3,
            // // Adding the error to be able to fingerprint the failed fetch event in HttpClient instrumentation
            virtualError,
            headers: getHeadersFromFetchArgs(args)
          };
          if (!onFetchResolved) {
            triggerHandlers$1("fetch", {
              ...handlerData
            });
          }
          return Reflect.apply(target, GLOBAL_OBJ, args).then(
            async (response) => {
              if (onFetchResolved) {
                onFetchResolved(response);
              } else {
                triggerHandlers$1("fetch", {
                  ...handlerData,
                  endTimestamp: timestampInSeconds() * 1e3,
                  response
                });
              }
              return response;
            },
            (error) => {
              triggerHandlers$1("fetch", {
                ...handlerData,
                endTimestamp: timestampInSeconds() * 1e3,
                error
              });
              if (isError(error) && error.stack === void 0) {
                error.stack = virtualError.stack;
                addNonEnumerableProperty(error, "framesToPop", 1);
              }
              const client = getClient();
              const enhanceOption = client?.getOptions().enhanceFetchErrorMessages ?? "always";
              const shouldEnhance = enhanceOption !== false;
              if (shouldEnhance && isError(error) && error.name === "TypeError" && (error.message === "Failed to fetch" || error.message === "Load failed" || error.message === "NetworkError when attempting to fetch resource.")) {
                try {
                  const url2 = new URL(handlerData.fetchData.url);
                  const hostname = url2.host;
                  if (enhanceOption === "always") {
                    error.message = `${error.message} (${hostname})`;
                  } else {
                    addNonEnumerableProperty(error, "__sentry_fetch_url_host__", hostname);
                  }
                } catch {
                }
              }
              throw error;
            }
          );
        }
      });
    });
  }
  async function resolveResponse(res, onFinishedResolving) {
    if (res?.body) {
      const body = res.body;
      const responseReader = body.getReader();
      const maxFetchDurationTimeout = setTimeout(
        () => {
          body.cancel().then(null, () => {
          });
        },
        90 * 1e3
        // 90s
      );
      let readingActive = true;
      while (readingActive) {
        let chunkTimeout;
        try {
          chunkTimeout = setTimeout(() => {
            body.cancel().then(null, () => {
            });
          }, 5e3);
          const { done } = await responseReader.read();
          clearTimeout(chunkTimeout);
          if (done) {
            onFinishedResolving();
            readingActive = false;
          }
        } catch {
          readingActive = false;
        } finally {
          clearTimeout(chunkTimeout);
        }
      }
      clearTimeout(maxFetchDurationTimeout);
      responseReader.releaseLock();
      body.cancel().then(null, () => {
      });
    }
  }
  function streamHandler(response) {
    let clonedResponseForResolving;
    try {
      clonedResponseForResolving = response.clone();
    } catch {
      return;
    }
    resolveResponse(clonedResponseForResolving, () => {
      triggerHandlers$1("fetch-body-resolved", {
        endTimestamp: timestampInSeconds() * 1e3,
        response
      });
    });
  }
  function hasProp(obj, prop) {
    return isObjectLike(obj) && !!obj[prop];
  }
  function getUrlFromResource(resource) {
    if (typeof resource === "string") {
      return resource;
    }
    if (!resource) {
      return "";
    }
    if (hasProp(resource, "url")) {
      return resource.url;
    }
    if (resource.toString) {
      return resource.toString();
    }
    return "";
  }
  function parseFetchArgs(fetchArgs) {
    if (fetchArgs.length === 0) {
      return { method: "GET", url: "" };
    }
    if (fetchArgs.length === 2) {
      const [resource, options] = fetchArgs;
      return {
        url: getUrlFromResource(resource),
        method: hasProp(options, "method") ? String(options.method).toUpperCase() : (
          // Request object as first argument
          isRequest(resource) && hasProp(resource, "method") ? String(resource.method).toUpperCase() : "GET"
        )
      };
    }
    const arg = fetchArgs[0];
    return {
      url: getUrlFromResource(arg),
      method: hasProp(arg, "method") ? String(arg.method).toUpperCase() : "GET"
    };
  }
  function getHeadersFromFetchArgs(fetchArgs) {
    const [requestArgument, optionsArgument] = fetchArgs;
    try {
      if (typeof optionsArgument === "object" && optionsArgument !== null && "headers" in optionsArgument && optionsArgument.headers) {
        return new Headers(optionsArgument.headers);
      }
      if (isRequest(requestArgument)) {
        return new Headers(requestArgument.headers);
      }
    } catch {
    }
    return;
  }

  function getBreadcrumbLogLevelFromHttpStatusCode(statusCode) {
    if (statusCode === void 0) {
      return void 0;
    } else if (statusCode >= 400 && statusCode < 500) {
      return "warning";
    } else if (statusCode >= 500) {
      return "error";
    } else {
      return void 0;
    }
  }

  class LRUMap {
    constructor(_maxSize) {
      this._maxSize = _maxSize;
      this._cache = /* @__PURE__ */ new Map();
    }
    /** Get the current size of the cache */
    get size() {
      return this._cache.size;
    }
    /** Get an entry or undefined if it was not in the cache. Re-inserts to update the recently used order */
    get(key) {
      const value = this._cache.get(key);
      if (value === void 0) {
        return void 0;
      }
      this._cache.delete(key);
      this._cache.set(key, value);
      return value;
    }
    /** Insert an entry and evict an older entry if we've reached maxSize */
    set(key, value) {
      if (this._cache.size >= this._maxSize) {
        const nextKey = this._cache.keys().next().value;
        this._cache.delete(nextKey);
      }
      this._cache.set(key, value);
    }
    /** Remove an entry and return the entry if it was in the cache */
    remove(key) {
      const value = this._cache.get(key);
      if (value) {
        this._cache.delete(key);
      }
      return value;
    }
    /** Clear all entries */
    clear() {
      this._cache.clear();
    }
    /** Get all the keys */
    keys() {
      return Array.from(this._cache.keys());
    }
    /** Get all the values */
    values() {
      const values = [];
      this._cache.forEach((value) => values.push(value));
      return values;
    }
  }

  function captureFeedback(params, hint = {}, scope = getCurrentScope()) {
    const { message, name, email, url, source, associatedEventId, tags } = params;
    const feedbackEvent = {
      contexts: {
        feedback: {
          contact_email: email,
          name,
          message,
          url,
          source,
          associated_event_id: associatedEventId
        }
      },
      type: "feedback",
      level: "info",
      tags
    };
    const client = scope?.getClient() || getClient();
    if (client) {
      client.emit("beforeSendFeedback", feedbackEvent, hint);
    }
    const eventId = scope.captureEvent(feedbackEvent, hint);
    return eventId;
  }

  const FAKE_FUNCTION = () => void 0;

  const FEEDBACK_INTEGRATION_METHODS = ["attachTo", "createForm", "createWidget", "remove"];
  const feedbackIntegrationShim = Object.assign(
    (_options) => {
      consoleSandbox(() => {
        console.warn("You are using feedbackIntegration() even though this bundle does not include feedback.");
      });
      return {
        name: "Feedback",
        ...FEEDBACK_INTEGRATION_METHODS.reduce((acc, method) => {
          acc[method] = FAKE_FUNCTION;
          return acc;
        }, {})
      };
    },
    {
      _isShim: true
    }
  );

  const REPLAY_INTEGRATION_METHODS = ["start", "stop", "flush"];
  function replayIntegrationShim(_options) {
    consoleSandbox(() => {
      console.warn("You are using replayIntegration() even though this bundle does not include replay.");
    });
    return {
      name: "Replay",
      ...REPLAY_INTEGRATION_METHODS.reduce((acc, method) => {
        acc[method] = FAKE_FUNCTION;
        return acc;
      }, {})
    };
  }

  const elementTimingIntegrationShim = defineIntegration(() => {
    consoleSandbox(() => {
      console.warn("You are using elementTimingIntegration() even though this bundle does not include element timing.");
    });
    return {
      name: "ElementTiming"
    };
  });

  function logShim(_message, _attributes) {
    consoleSandbox(() => {
      console.warn("You are using Sentry.logger.* even though this bundle does not include logs.");
    });
  }
  function fmtShim(_strings, ..._values) {
    consoleSandbox(() => {
      console.warn("You are using Sentry.logger.fmt even though this bundle does not include logs.");
    });
    return "";
  }
  const loggerShim = {
    trace: logShim,
    debug: logShim,
    info: logShim,
    warn: logShim,
    error: logShim,
    fatal: logShim,
    fmt: fmtShim
  };
  const consoleLoggingIntegrationShim = defineIntegration((_options) => {
    consoleSandbox(() => {
      console.warn("You are using consoleLoggingIntegration() even though this bundle does not include logs.");
    });
    return {
      name: "ConsoleLogs",
      setup: FAKE_FUNCTION
    };
  });

  function metricShim(_name, _value, _options) {
    consoleSandbox(() => {
      console.warn("You are using Sentry.metrics.* even though this bundle does not include metrics.");
    });
  }
  const metricsShim = {
    count: metricShim,
    gauge: metricShim,
    distribution: metricShim
  };

  var __defProp = Object.defineProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
  let t = -1;
  const n = () => t, e = (n2) => {
    addEventListener("pageshow", (e2) => {
      e2.persisted && (t = e2.timeStamp, n2(e2));
    }, true);
  }, i = (t2, n2, e2, i2) => {
    let o2, s2;
    return (a2) => {
      n2.value >= 0 && (a2 || i2) && (s2 = n2.value - (o2 ?? 0), (s2 || void 0 === o2) && (o2 = n2.value, n2.delta = s2, n2.rating = ((t3, n3) => t3 > n3[1] ? "poor" : t3 > n3[0] ? "needs-improvement" : "good")(n2.value, e2), t2(n2)));
    };
  }, o = (t2) => {
    requestAnimationFrame(() => requestAnimationFrame(t2));
  }, s = () => {
    const t2 = performance.getEntriesByType("navigation")[0];
    if (t2 && t2.responseStart > 0 && t2.responseStart < performance.now()) return t2;
  }, a = () => s()?.activationStart ?? 0;
  let r = -1;
  const c = /* @__PURE__ */ new Set(), f = () => "hidden" !== document.visibilityState || document.prerendering ? 1 / 0 : 0, h = (t2) => {
    if ("hidden" === document.visibilityState) {
      if ("visibilitychange" === t2.type) for (const t3 of c) t3();
      isFinite(r) || (r = "visibilitychange" === t2.type ? t2.timeStamp : 0, removeEventListener("prerenderingchange", h, true));
    }
  }, d = (t2 = false) => {
    if (t2 && (r = 1 / 0), r < 0) {
      const t3 = a(), n2 = document.prerendering ? void 0 : globalThis.performance.getEntriesByType("visibility-state").find((n3) => "hidden" === n3.name && n3.startTime >= t3)?.startTime;
      r = n2 ?? f(), addEventListener("visibilitychange", h, true), addEventListener("prerenderingchange", h, true), e(() => {
        setTimeout(() => {
          r = f();
        });
      });
    }
    return { get firstHiddenTime() {
      return r;
    }, onHidden(t3) {
      c.add(t3);
    } };
  }, l = (t2, e2 = -1, i2, o2 = 0, r2, c2, f2) => {
    const h2 = s(), d2 = h2?.navigationId || 0;
    let l2 = "navigate";
    i2 ? l2 = i2 : n() >= 0 ? l2 = "back-forward-cache" : h2 && (document.prerendering || a() > 0 ? l2 = "prerender" : document.wasDiscarded ? l2 = "restore" : h2.type && (l2 = h2.type.replace(/_/g, "-")));
    return { name: t2, value: e2, rating: "good", delta: 0, entries: [], id: `v6-${Date.now()}-${Math.floor(8999999999999 * Math.random()) + 1e12}`, navigationType: l2, navigationId: o2 || d2, navigationInteractionId: r2, navigationURL: c2 || h2?.name, navigationStartTime: f2 || 0 };
  }, g = /* @__PURE__ */ new WeakMap();
  function u(t2, n2) {
    let e2 = g.get(n2);
    return e2 || (e2 = /* @__PURE__ */ new WeakMap(), g.set(n2, e2)), e2.get(t2) || e2.set(t2, new n2()), e2.get(t2);
  }
  class v {
    constructor() {
      __publicField(this, "t");
      __publicField(this, "i", 0);
      __publicField(this, "o", []);
    }
    h(t2) {
      if (t2.hadRecentInput) return;
      const n2 = this.o[0], e2 = this.o.at(-1);
      this.i && n2 && e2 && t2.startTime - e2.startTime < 1e3 && t2.startTime - n2.startTime < 5e3 ? (this.i += t2.value, this.o.push(t2)) : (this.i = t2.value, this.o = [t2]), this.t?.(t2);
    }
  }
  const p = (t2, n2, e2 = {}) => {
    try {
      const i2 = t2.filter((t3) => PerformanceObserver.supportedEntryTypes.includes(t3));
      if (i2.length > 0) {
        const t3 = new PerformanceObserver((t4) => {
          queueMicrotask(() => {
            const e3 = t4.getEntries();
            i2.length > 1 && e3.sort((t5, n3) => t5.startTime + t5.duration - (n3.startTime + n3.duration)), n2(e3);
          });
        });
        for (const n3 of i2) t3.observe({ type: n3, buffered: true, ...e2 });
        return t3;
      }
    } catch {
    }
  }, m = (t2) => globalThis.PerformanceObserver?.supportedEntryTypes.includes("soft-navigation") && "function" == typeof globalThis.PerformanceSoftNavigation?.prototype?.getLargestInteractionContentfulPaint && t2 && t2.reportSoftNavs, b = (t2, n2) => {
    if (t2.set(n2.navigationId, n2), t2.size > 2) {
      const n3 = t2.keys().next().value;
      void 0 !== n3 && t2.delete(n3);
    }
  }, T = (t2) => {
    let n2 = false;
    return () => {
      n2 || (t2(), n2 = true);
    };
  };
  class y {
    constructor() {
      __publicField(this, "l");
    }
  }
  const _ = (t2) => {
    document.prerendering ? addEventListener("prerenderingchange", t2, true) : t2();
  }, E = [1800, 3e3], M = (t2, s2 = {}) => {
    const r2 = m(s2);
    _(() => {
      const c2 = u(s2, y), f2 = d();
      let h2, g2 = l("FCP");
      const v2 = p(["paint"], (t3) => {
        for (const n2 of t3) "first-contentful-paint" === n2.name && (v2.disconnect(), n2.startTime < f2.firstHiddenTime && (g2.value = Math.max(n2.startTime - a(), 0), g2.entries.push(n2), g2.navigationId = n2.navigationId || g2.navigationId, h2(true)));
      });
      if (v2 && (h2 = i(t2, g2, E, s2.reportAllChanges), e((e2) => {
        g2 = l("FCP", -1, "back-forward-cache", g2.navigationId, g2.navigationInteractionId, g2.navigationURL, n()), h2 = i(t2, g2, E, s2.reportAllChanges), o(() => {
          g2.value = performance.now() - e2.timeStamp, h2(true);
        });
      })), r2) {
        p(["soft-navigation"], (n2) => {
          n2.forEach((n3) => {
            c2.l && n3.navigationId && b(c2.l, n3);
            const e2 = Math.max((n3.presentationTime || n3.paintTime || 0) - n3.startTime, 0);
            g2 = l("FCP", e2, "soft-navigation", n3.navigationId, n3.interactionId, n3.name, n3.startTime), h2 = i(t2, g2, E, s2.reportAllChanges), h2(true);
          });
        }, s2);
      }
    });
  }, L = [0.1, 0.25], P = (t2, s2 = {}) => {
    const a2 = d();
    M(T(() => {
      let r2, c2 = l("CLS", 0);
      const f2 = u(s2, v), h2 = (n2, e2, o2, a3, h3) => {
        c2 = l("CLS", 0, n2, e2, o2, a3, h3), f2.i = 0, r2 = i(t2, c2, L, s2.reportAllChanges);
      }, d2 = (t3 = false) => {
        f2.i > c2.value && (c2.value = f2.i, c2.entries = f2.o), r2(t3);
      }, g2 = (t3) => {
        d2(true), h2("soft-navigation", t3.navigationId, t3.interactionId, t3.name, t3.startTime);
      }, b2 = (t3) => {
        for (const n2 of t3) "soft-navigation" !== n2.entryType ? f2.h(n2) : g2(n2);
        d2();
      }, T2 = ["layout-shift"];
      m(s2) && T2.push("soft-navigation");
      const y2 = p(T2, b2);
      y2 && (r2 = i(t2, c2, L, s2.reportAllChanges), a2.onHidden(() => {
        b2(y2.takeRecords()), r2(true);
      }), e(() => {
        h2("back-forward-cache", c2.navigationId, c2.navigationInteractionId, c2.navigationURL, n()), o(r2);
      }), setTimeout(r2));
    }));
  };
  let w = 0, I = 1 / 0, k = 0;
  const C = (t2) => {
    for (const n2 of t2) n2.interactionId && (I = Math.min(I, n2.interactionId), k = Math.max(k, n2.interactionId), w = k ? (k - I) / 7 + 1 : 0);
  };
  let F;
  const N = () => F ? w : performance.interactionCount ?? 0, B = () => {
    "interactionCount" in performance || F || (F = p(["event"], C, { durationThreshold: 0 }));
  };
  class S {
    constructor() {
      __publicField(this, "u", 0);
      __publicField(this, "v", []);
      __publicField(this, "p", /* @__PURE__ */ new Map());
      __publicField(this, "m");
      __publicField(this, "T");
    }
    _() {
      return N() - this.u;
    }
    M() {
      this.u = N(), this.v.length = 0, this.p.clear();
    }
    L(t2) {
      const n2 = this._(), e2 = Math.min(this.v.length - 1, Math.floor(n2 / 50));
      return !n2 || -1 !== e2 || "soft-navigation" !== t2 && "back-forward-cache" !== t2 ? this.v[e2] : { P: 8, id: -1, entries: [] };
    }
    h(t2) {
      if (this.m?.(t2), !t2.interactionId && "first-input" !== t2.entryType) return;
      const n2 = this.v.at(-1);
      let e2 = this.p.get(t2.interactionId);
      if (e2 || this.v.length < 10 || t2.duration > n2.P) {
        if (e2 ? t2.duration > e2.P ? (e2.entries = [t2], e2.P = t2.duration) : t2.duration === e2.P && t2.startTime === e2.entries[0].startTime && e2.entries.push(t2) : (e2 = { id: t2.interactionId, entries: [t2], P: t2.duration }, this.p.set(e2.id, e2), this.v.push(e2)), this.v.sort((t3, n3) => n3.P - t3.P), this.v.length > 10) {
          const t3 = this.v.splice(10);
          for (const n3 of t3) this.p.delete(n3.id);
        }
        this.T?.(e2);
      }
    }
  }
  const q = (t2) => {
    const n2 = "requestIdleCallback" in globalThis ? 1e3 : 0, e2 = globalThis.requestIdleCallback || setTimeout, i2 = globalThis.cancelIdleCallback || clearTimeout;
    if ("hidden" === document.visibilityState) t2();
    else {
      const o2 = T(t2);
      let s2 = -1;
      const a2 = () => {
        i2(s2), o2();
      };
      addEventListener("visibilitychange", a2, { once: true, capture: true }), s2 = e2(() => {
        removeEventListener("visibilitychange", a2, { capture: true }), o2();
      }, { timeout: n2 });
    }
  }, A = [200, 500], x = (t2, o2 = {}) => {
    if (!globalThis.PerformanceEventTiming || !("interactionId" in PerformanceEventTiming.prototype)) return;
    const s2 = d();
    _(() => {
      B();
      let a2, r2 = l("INP");
      const c2 = u(o2, S), f2 = (n2, e2, s3, f3, h3) => {
        c2.M(), r2 = l("INP", -1, n2, e2, s3, f3, h3), a2 = i(t2, r2, A, o2.reportAllChanges);
      }, h2 = () => {
        const t3 = c2.L(r2.navigationType);
        t3 && t3.P !== r2.value && (r2.value = t3.P, r2.entries = t3.entries, a2());
      }, d2 = (t3) => {
        h2(), a2(true), f2("soft-navigation", t3.navigationId, t3.interactionId, t3.name, t3.startTime);
      }, g2 = (t3, n2 = false) => {
        q(() => {
          for (const n3 of t3) "soft-navigation" !== n3.entryType ? c2.h(n3) : d2(n3);
          h2(), n2 && a2(true);
        });
      }, v2 = ["event", "first-input"];
      m(o2) && v2.push("soft-navigation");
      const b2 = p(v2, g2, { ...o2, durationThreshold: o2.durationThreshold ?? 40 });
      a2 = i(t2, r2, A, o2.reportAllChanges), b2 && (s2.onHidden(() => {
        g2(b2.takeRecords(), true);
      }), e(() => {
        f2("back-forward-cache", r2.navigationId, r2.navigationInteractionId, r2.navigationURL, n());
      }));
    });
  };
  class H {
    constructor() {
      __publicField(this, "m");
      __publicField(this, "l");
    }
    h(t2) {
      this.m?.(t2);
    }
  }
  const O = [2500, 4e3], U = (t2, s2 = {}) => {
    let r2 = false;
    const c2 = m(s2);
    _(() => {
      let f2, h2 = d(), g2 = l("LCP");
      const v2 = u(s2, H), m2 = (n2, e2, o2, a2, c3) => {
        g2 = l("LCP", -1, n2, e2, o2, a2, c3), f2 = i(t2, g2, O, s2.reportAllChanges), r2 = false, "soft-navigation" === n2 && (h2 = d(true));
      }, T2 = (t3) => {
        v2.l && t3.navigationId && b(v2.l, t3), r2 || f2(true), m2("soft-navigation", t3.navigationId, t3.interactionId, t3.name, t3.startTime);
        const n2 = t3.getLargestInteractionContentfulPaint?.();
        n2 && y2([n2]);
      }, y2 = (t3) => {
        s2.reportAllChanges || c2 || (t3 = t3.slice(-1));
        for (const n2 of t3) {
          if (!n2) continue;
          if ("soft-navigation" === n2.entryType) {
            T2(n2);
            continue;
          }
          let t4 = 0, e2 = [], i2 = n2.startTime;
          if ("largest-contentful-paint" === n2.entryType) t4 = Math.max(n2.startTime - a(), 0), v2.h(n2), e2 = [n2];
          else if ("interaction-contentful-paint" === n2.entryType) {
            const o2 = n2;
            if (!g2.navigationId) continue;
            if ("interactionId" in o2 && o2.interactionId != g2.navigationInteractionId) continue;
            i2 = o2.largestContentfulPaint?.renderTime || 0, t4 = Math.max(i2 - n2.startTime, 0), o2.largestContentfulPaint && (v2.h(o2.largestContentfulPaint), e2 = [o2.largestContentfulPaint]);
          }
          i2 < h2.firstHiddenTime && (g2.value = t4, g2.entries = e2, f2());
        }
      }, _2 = ["largest-contentful-paint"];
      c2 && _2.push("interaction-contentful-paint", "soft-navigation");
      const E2 = p(_2, y2);
      if (E2) {
        f2 = i(t2, g2, O, s2.reportAllChanges);
        const a2 = ["keydown", "click", "visibilitychange"], h3 = (t3) => {
          if (t3.isTrusted && !r2) {
            const t4 = g2.id;
            q(() => {
              if (!r2) {
                if (!c2) {
                  E2.disconnect();
                  for (const t5 of a2) removeEventListener(t5, h3, { capture: true });
                }
                t4 === g2.id && (r2 = true, f2(true));
              }
            });
          }
        };
        for (const t3 of a2) addEventListener(t3, h3, { capture: true });
        e((e2) => {
          m2("back-forward-cache", g2.navigationId, g2.navigationInteractionId, g2.navigationURL, n()), f2 = i(t2, g2, O, s2.reportAllChanges), o(() => {
            g2.value = performance.now() - e2.timeStamp, r2 = true, f2(true);
          });
        });
      }
    });
  }, W = [800, 1800], $ = (t2) => {
    document.prerendering ? _(() => $(t2)) : "complete" !== document.readyState ? addEventListener("load", () => $(t2), true) : setTimeout(t2);
  }, D = (t2, o2 = {}) => {
    const r2 = m(o2);
    let c2 = l("TTFB"), f2 = i(t2, c2, W, o2.reportAllChanges);
    $(() => {
      const h2 = s();
      if (h2) {
        const s2 = h2.responseStart;
        if (c2.value = Math.max(s2 - a(), 0), c2.entries = [h2], f2(true), e(() => {
          c2 = l("TTFB", 0, "back-forward-cache", c2.navigationId, c2.navigationInteractionId, c2.navigationURL, n()), f2 = i(t2, c2, W, o2.reportAllChanges), f2(true);
        }), r2) {
          p(["soft-navigation"], (n2) => {
            n2.forEach((n3) => {
              n3.navigationId && (c2 = l("TTFB", 0, "soft-navigation", n3.navigationId, n3.interactionId, n3.name, n3.startTime), c2.entries = [n3], f2 = i(t2, c2, W, o2.reportAllChanges), f2(true));
            });
          }, o2);
        }
      }
    });
  };

  const handlers = {};
  const instrumented = {};
  let _previousCls;
  let _previousLcp;
  let _previousTtfb;
  let _previousInp;
  let _previousFcp;
  const stopListeners = {};
  let _reportSoftNavs = false;
  let _reportBfcache = false;
  function enableSoftNavigationReporting() {
    _reportSoftNavs = true;
  }
  function enableBfcacheReporting() {
    _reportBfcache = true;
  }
  function addClsInstrumentationHandler(callback, stopOnCallback = false) {
    return addMetricObserver("cls", callback, instrumentCls, _previousCls, stopOnCallback);
  }
  function addLcpInstrumentationHandler(callback, stopOnCallback = false) {
    return addMetricObserver("lcp", callback, instrumentLcp, _previousLcp, stopOnCallback);
  }
  function addTtfbInstrumentationHandler(callback) {
    return addMetricObserver("ttfb", callback, instrumentTtfb, _previousTtfb);
  }
  function addFcpInstrumentationHandler(callback) {
    return addMetricObserver("fcp", callback, instrumentFcp, _previousFcp);
  }
  function addInpInstrumentationHandler(callback) {
    return addMetricObserver("inp", callback, instrumentInp, _previousInp);
  }
  function addPerformanceInstrumentationHandler(type, callback) {
    addHandler(type, callback);
    if (!instrumented[type]) {
      instrumentPerformanceObserver(type);
      instrumented[type] = true;
    }
    return getCleanupCallback(type, callback);
  }
  function triggerHandlers(type, data) {
    const typeHandlers = handlers[type];
    if (!typeHandlers?.length) {
      return;
    }
    for (const handler of typeHandlers) {
      try {
        handler(data);
      } catch (e) {
        debug.error(
          `Error while triggering instrumentation handler.
Type: ${type}
Name: ${getFunctionName(handler)}
Error:`,
          e
        );
      }
    }
  }
  function unlessBfcacheDisabled(callback) {
    return (metric) => {
      if (!_reportBfcache && metric.navigationType === "back-forward-cache") {
        return;
      }
      callback(metric);
    };
  }
  function instrumentCls() {
    return P(
      unlessBfcacheDisabled((metric) => {
        triggerHandlers("cls", {
          metric
        });
        _previousCls = metric;
      }),
      // We want the callback to be called whenever the CLS value updates.
      // By default, the callback is only called when the tab goes to the background.
      { reportAllChanges: !_reportSoftNavs && !_reportBfcache, reportSoftNavs: _reportSoftNavs }
    );
  }
  function instrumentLcp() {
    return U(
      unlessBfcacheDisabled((metric) => {
        triggerHandlers("lcp", {
          metric
        });
        _previousLcp = metric;
      }),
      // We want the callback to be called whenever the LCP value updates.
      // By default, the callback is only called when the tab goes to the background.
      { reportAllChanges: !_reportSoftNavs && !_reportBfcache, reportSoftNavs: _reportSoftNavs }
    );
  }
  function instrumentTtfb() {
    return D(
      unlessBfcacheDisabled((metric) => {
        triggerHandlers("ttfb", {
          metric
        });
        _previousTtfb = metric;
      })
    );
  }
  function instrumentFcp() {
    return M(
      unlessBfcacheDisabled((metric) => {
        triggerHandlers("fcp", {
          metric
        });
        _previousFcp = metric;
      })
    );
  }
  function instrumentInp() {
    return x(
      unlessBfcacheDisabled((metric) => {
        triggerHandlers("inp", {
          metric
        });
        _previousInp = metric;
      }),
      { reportSoftNavs: _reportSoftNavs }
    );
  }
  function addMetricObserver(type, callback, instrumentFn, previousValue, stopOnCallback = false) {
    addHandler(type, callback);
    if (!instrumented[type]) {
      instrumented[type] = true;
      void Promise.resolve().then(() => {
        stopListeners[type] = instrumentFn();
      });
    }
    if (previousValue) {
      callback({ metric: previousValue });
    }
    return getCleanupCallback(type, callback, stopOnCallback);
  }
  function instrumentPerformanceObserver(type) {
    const options = { type, buffered: true };
    if (type === "event") {
      options.durationThreshold = 0;
    }
    try {
      if (PerformanceObserver.supportedEntryTypes.includes(type)) {
        const po = new PerformanceObserver((list) => {
          void Promise.resolve().then(() => {
            triggerHandlers(type, { entries: list.getEntries() });
          });
        });
        po.observe(options);
      }
    } catch {
    }
  }
  function addHandler(type, handler) {
    handlers[type] = handlers[type] || [];
    handlers[type].push(handler);
  }
  function getCleanupCallback(type, callback, stopOnCleanup = false) {
    return () => {
      if (stopOnCleanup) {
        stopListeners[type]?.();
      }
      const typeHandlers = handlers[type];
      if (!typeHandlers) {
        return;
      }
      const index = typeHandlers.indexOf(callback);
      if (index !== -1) {
        typeHandlers.splice(index, 1);
      }
    };
  }
  function isPerformanceEventTiming(entry) {
    return "duration" in entry;
  }

  const WINDOW$1 = GLOBAL_OBJ;

  const MAX_TRACKED_NAVIGATIONS = 5;
  const INTERACTION_MATCH_TOLERANCE_MS = 5;
  let _pendingNavigation;
  let _pendingInteraction;
  let _lastInteractionTimestamp;
  const _interactionIdToNavigationSpan = new LRUMap(MAX_TRACKED_NAVIGATIONS);
  const _navigationIdToNavigationSpan = new LRUMap(MAX_TRACKED_NAVIGATIONS);
  let _correlationStarted = false;
  function interactionMatches(entryStartTime, interactionTimestamp) {
    return Math.abs(entryStartTime - interactionTimestamp) <= INTERACTION_MATCH_TOLERANCE_MS;
  }
  function supportsSoftNavigations() {
    try {
      return PerformanceObserver.supportedEntryTypes.includes("soft-navigation") && // Older implementations exposed this as an attribute rather than a method. Only the method
      // form shipped unflagged, so it's what web-vitals gates on.
      typeof WINDOW$1.PerformanceSoftNavigation?.prototype?.getLargestInteractionContentfulPaint === "function";
    } catch {
      return false;
    }
  }
  function startSoftNavigationCorrelation(client) {
    if (_correlationStarted || !supportsSoftNavigations()) {
      return;
    }
    _correlationStarted = true;
    const onInteraction = (event) => {
      if (event.isTrusted) {
        _lastInteractionTimestamp = event.timeStamp;
      }
    };
    WINDOW$1.addEventListener("click", onInteraction, { capture: true, passive: true });
    WINDOW$1.addEventListener("keydown", onInteraction, { capture: true, passive: true });
    client.on("spanStart", (span) => {
      if (spanToJSON(span).attributes?.[SEMANTIC_ATTRIBUTE_SENTRY_OP] !== "navigation") {
        return;
      }
      _pendingNavigation = void 0;
      const interactionTimestamp = _lastInteractionTimestamp;
      if (interactionTimestamp == null) {
        return;
      }
      if (_pendingInteraction?.interactionTimestamp === interactionTimestamp) {
        _interactionIdToNavigationSpan.set(_pendingInteraction.interactionId, span);
        _pendingInteraction = void 0;
        return;
      }
      _pendingNavigation = { span, interactionTimestamp };
    });
    const bindInteractionToNavigationSpan = ({ entries }) => {
      for (const entry of entries) {
        if (!isPerformanceEventTiming(entry) || !entry.interactionId) {
          continue;
        }
        const pending = _pendingNavigation;
        if (pending && interactionMatches(entry.startTime, pending.interactionTimestamp)) {
          _interactionIdToNavigationSpan.set(entry.interactionId, pending.span);
          _pendingNavigation = void 0;
          continue;
        }
        if (_interactionIdToNavigationSpan.get(entry.interactionId)) {
          continue;
        }
        if (_lastInteractionTimestamp != null && interactionMatches(entry.startTime, _lastInteractionTimestamp)) {
          _pendingInteraction = { interactionId: entry.interactionId, interactionTimestamp: _lastInteractionTimestamp };
        }
      }
    };
    addPerformanceInstrumentationHandler("event", bindInteractionToNavigationSpan);
    addPerformanceInstrumentationHandler("first-input", bindInteractionToNavigationSpan);
    addPerformanceInstrumentationHandler("soft-navigation", ({ entries }) => {
      for (const entry of entries) {
        const span = _interactionIdToNavigationSpan.get(entry.interactionId);
        if (!span) {
          debug.log(`[SoftNav] No navigation span found for soft navigation ${entry.navigationId}`, entry);
          continue;
        }
        _navigationIdToNavigationSpan.set(entry.navigationId, span);
        span.setAttribute(Li, entry.navigationId);
      }
    });
  }
  function getNavigationSpanForMetric(metric) {
    if (metric.navigationType !== "soft-navigation") {
      return void 0;
    }
    const span = _navigationIdToNavigationSpan.get(metric.navigationId);
    if (span) {
      return span;
    }
    return metric.navigationInteractionId != null ? _interactionIdToNavigationSpan.get(metric.navigationInteractionId) : void 0;
  }

  function isMeasurementValue(value) {
    return typeof value === "number" && isFinite(value);
  }
  function startAndEndSpan(parentSpan, startTimeInSeconds, endTime, { ...ctx }) {
    const parentStartTime = spanToStaticSpanJSON(parentSpan).start_timestamp;
    if (parentStartTime && parentStartTime > startTimeInSeconds) {
      if (typeof parentSpan.updateStartTime === "function") {
        parentSpan.updateStartTime(startTimeInSeconds);
      }
    }
    return withActiveSpan(parentSpan, () => {
      const span = startInactiveSpan({
        startTime: startTimeInSeconds,
        ...ctx
      });
      if (span) {
        span.end(endTime);
      }
      return span;
    });
  }
  function getBrowserPerformanceAPI() {
    return WINDOW$1.addEventListener && WINDOW$1.performance;
  }
  function msToSec(time) {
    return time / 1e3;
  }
  function extractNetworkProtocol(nextHopProtocol) {
    let name = "unknown";
    let version = "unknown";
    let _name = "";
    for (const char of nextHopProtocol) {
      if (char === "/") {
        [name, version] = nextHopProtocol.split("/");
        break;
      }
      if (!isNaN(Number(char))) {
        name = _name === "h" ? "http" : _name;
        version = nextHopProtocol.split(_name)[1];
        break;
      }
      _name += char;
    }
    if (_name === nextHopProtocol) {
      name = _name;
    }
    return { name, version };
  }
  function supportsWebVital(entryType) {
    try {
      return PerformanceObserver.supportedEntryTypes.includes(entryType);
    } catch {
      return false;
    }
  }

  function getAbsoluteTime(time) {
    return time ? ((browserPerformanceTimeOrigin() || performance.timeOrigin) + time) / 1e3 : time;
  }
  function resourceTimingToSpanAttributes(resourceTiming) {
    const timingSpanData = {};
    if (resourceTiming.nextHopProtocol != void 0) {
      const { name, version } = extractNetworkProtocol(resourceTiming.nextHopProtocol);
      timingSpanData["network.protocol.version"] = version;
      timingSpanData["network.protocol.name"] = name;
    }
    if (!(browserPerformanceTimeOrigin() || getBrowserPerformanceAPI()?.timeOrigin)) {
      return timingSpanData;
    }
    return dropUndefinedKeysFromObject({
      ...timingSpanData,
      "http.request.redirect_start": getAbsoluteTime(resourceTiming.redirectStart),
      "http.request.redirect_end": getAbsoluteTime(resourceTiming.redirectEnd),
      "http.request.worker_start": getAbsoluteTime(resourceTiming.workerStart),
      "http.request.fetch_start": getAbsoluteTime(resourceTiming.fetchStart),
      "http.request.domain_lookup_start": getAbsoluteTime(resourceTiming.domainLookupStart),
      "http.request.domain_lookup_end": getAbsoluteTime(resourceTiming.domainLookupEnd),
      "http.request.connect_start": getAbsoluteTime(resourceTiming.connectStart),
      "http.request.secure_connection_start": getAbsoluteTime(resourceTiming.secureConnectionStart),
      "http.request.connection_end": getAbsoluteTime(resourceTiming.connectEnd),
      "http.request.request_start": getAbsoluteTime(resourceTiming.requestStart),
      "http.request.response_start": getAbsoluteTime(resourceTiming.responseStart),
      "http.request.response_end": getAbsoluteTime(resourceTiming.responseEnd),
      // For TTFB we actually want the relative time from timeOrigin to responseStart
      // This way, TTFB always measures the "first page load" experience.
      // see: https://web.dev/articles/ttfb#measure-resource-requests
      "http.request.time_to_first_byte": resourceTiming.responseStart != null ? resourceTiming.responseStart / 1e3 : void 0
    });
  }
  function dropUndefinedKeysFromObject(attrs) {
    return Object.fromEntries(Object.entries(attrs).filter(([, value]) => value != null));
  }

  const MAX_INT_AS_BYTES = 2147483647;
  let _performanceCursor = 0;
  function startTrackingLongTasks() {
    addPerformanceInstrumentationHandler("longtask", ({ entries }) => {
      const parent = getActiveSpan();
      if (!parent) {
        return;
      }
      const { attributes: parentAttributes, start_timestamp: parentStartTimestamp } = spanToJSON(parent);
      for (const entry of entries) {
        const startTime = msToSec(browserPerformanceTimeOrigin() + entry.startTime);
        const duration = msToSec(entry.duration);
        if (parentAttributes[cd] === "navigation" && parentStartTimestamp && startTime < parentStartTimestamp) {
          continue;
        }
        startAndEndSpan(parent, startTime, startTime + duration, {
          name: UI_LONG_TASK_SPAN_NAME_FALLBACK,
          op: W$1,
          attributes: {
            [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "auto.ui.browser.metrics"
          }
        });
      }
    });
  }
  function startTrackingLongAnimationFrames() {
    const observer = new PerformanceObserver((list) => {
      const parent = getActiveSpan();
      if (!parent) {
        return;
      }
      for (const entry of list.getEntries()) {
        if (!entry.scripts[0]) {
          continue;
        }
        const startTime = msToSec(browserPerformanceTimeOrigin() + entry.startTime);
        const {
          start_timestamp: parentStartTimestamp,
          attributes: { [cd]: parentOp }
        } = spanToJSON(parent);
        if (parentOp === "navigation" && parentStartTimestamp && startTime < parentStartTimestamp) {
          continue;
        }
        const duration = msToSec(entry.duration);
        const attributes = {
          [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "auto.ui.browser.metrics"
        };
        const initialScript = entry.scripts[0];
        const { invoker, invokerType, sourceURL, sourceFunctionName, sourceCharPosition } = initialScript;
        attributes["browser.script.invoker"] = invoker;
        attributes["browser.script.invoker_type"] = invokerType;
        if (sourceURL) {
          attributes[Qt] = sourceURL;
        }
        if (sourceFunctionName) {
          attributes[Jt] = sourceFunctionName;
        }
        if (sourceCharPosition !== -1) {
          attributes["browser.script.source_char_position"] = sourceCharPosition;
        }
        startAndEndSpan(parent, startTime, startTime + duration, {
          name: UI_LONG_TASK_SPAN_NAME_FALLBACK,
          op: h$1,
          attributes
        });
      }
    });
    observer.observe({ type: "long-animation-frame", buffered: true });
  }
  function addPerformanceEntries(span, options) {
    const performance = getBrowserPerformanceAPI();
    const origin = browserPerformanceTimeOrigin();
    if (!performance?.getEntries || !origin) {
      return;
    }
    const { spanStreamingEnabled, ignoreResourceSpans } = options;
    const timeOrigin = msToSec(origin);
    const performanceEntries = performance.getEntries();
    const { attributes, start_timestamp: transactionStartTime } = spanToJSON(span);
    performanceEntries.slice(_performanceCursor).forEach((entry) => {
      const startTime = msToSec(entry.startTime);
      const duration = msToSec(
        // Inexplicably, Chrome sometimes emits a negative duration. We need to work around this.
        // There is a SO post attempting to explain this, but it leaves one with open questions: https://stackoverflow.com/questions/23191918/peformance-getentries-and-negative-duration-display
        // The way we clamp the value is probably not accurate, since we have observed this happen for things that may take a while to load, like for example the replay worker.
        // TODO: Investigate why this happens and how to properly mitigate. For now, this is a workaround to prevent transactions being dropped due to negative duration spans.
        Math.max(0, entry.duration)
      );
      if (attributes[cd] === "navigation" && transactionStartTime && timeOrigin + startTime < transactionStartTime) {
        return;
      }
      switch (entry.entryType) {
        case "navigation": {
          _addNavigationSpans(span, entry, timeOrigin, spanStreamingEnabled);
          break;
        }
        case "paint": {
          _addPaintSpan(span, entry, startTime, duration, timeOrigin);
          break;
        }
        case "resource": {
          _addResourceSpans(
            span,
            entry,
            entry.name,
            startTime,
            duration,
            timeOrigin,
            ignoreResourceSpans,
            spanStreamingEnabled
          );
          break;
        }
      }
    });
    _performanceCursor = Math.max(performanceEntries.length - 1, 0);
    _trackNavigator(span, spanStreamingEnabled);
  }
  function _addPaintSpan(span, entry, startTime, duration, timeOrigin) {
    const startTimestamp = timeOrigin + startTime;
    startAndEndSpan(span, startTimestamp, startTimestamp + duration, {
      // The entry name (`first-paint`, `first-contentful-paint`) is already the low-cardinality name
      // the conventions ask for, so only the attribute backing it has to be added.
      name: entry.name,
      attributes: {
        [cd]: s$1,
        [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "auto.resource.browser.metrics",
        [Ui]: entry.name
      }
    });
  }
  function _addNavigationSpans(span, entry, timeOrigin, spanStreamingEnabled) {
    _addPerformanceNavigationTiming(span, entry, "unloadEvent", timeOrigin, spanStreamingEnabled);
    _addPerformanceNavigationTiming(span, entry, "redirect", timeOrigin, spanStreamingEnabled);
    _addPerformanceNavigationTiming(span, entry, "domContentLoadedEvent", timeOrigin, spanStreamingEnabled);
    _addPerformanceNavigationTiming(span, entry, "loadEvent", timeOrigin, spanStreamingEnabled);
    _addPerformanceNavigationTiming(span, entry, "connect", timeOrigin, spanStreamingEnabled);
    _addPerformanceNavigationTiming(span, entry, "secureConnection", timeOrigin, spanStreamingEnabled);
    _addPerformanceNavigationTiming(span, entry, "fetch", timeOrigin, spanStreamingEnabled);
    _addPerformanceNavigationTiming(span, entry, "domainLookup", timeOrigin, spanStreamingEnabled);
    _addRequest(span, entry, timeOrigin, spanStreamingEnabled);
  }
  const NAVIGATION_TIMING_SPAN_OPS = {
    secureConnection: b$1,
    fetch: d$1,
    domainLookup: B$1,
    unloadEvent: S$1,
    redirect: l$1,
    connect: P$1,
    domContentLoadedEvent: p$1,
    loadEvent: L$1
  };
  function _addPerformanceNavigationTiming(span, entry, event, timeOrigin, spanStreamingEnabled) {
    const eventEnd = _getEndPropertyNameForNavigationTiming(event);
    const end = entry[eventEnd];
    const start = entry[`${event}Start`];
    if (!start || !end) {
      return;
    }
    const op = NAVIGATION_TIMING_SPAN_OPS[event];
    startAndEndSpan(span, timeOrigin + msToSec(start), timeOrigin + msToSec(end), {
      // With span streaming, span names have to be low cardinality, so we can't fall back to the
      // document URL. `url.full` keeps it, and is what Relay derives the description from.
      name: spanStreamingEnabled ? BROWSER_NAVIGATION_TIMING_SPAN_NAMES[op] : entry.name,
      attributes: {
        [cd]: op,
        [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "auto.ui.browser.metrics",
        [zg]: filterCollectedUrl(entry.name),
        ...event === "redirect" && entry.redirectCount != null ? { "http.redirect_count": entry.redirectCount } : {}
      }
    });
  }
  function _getEndPropertyNameForNavigationTiming(event) {
    if (event === "secureConnection") {
      return "connectEnd";
    }
    if (event === "fetch") {
      return "domainLookupStart";
    }
    return `${event}End`;
  }
  function _addRequest(span, entry, timeOrigin, spanStreamingEnabled) {
    const requestStartTimestamp = timeOrigin + msToSec(entry.requestStart);
    const responseEndTimestamp = timeOrigin + msToSec(entry.responseEnd);
    const responseStartTimestamp = timeOrigin + msToSec(entry.responseStart);
    if (entry.responseEnd) {
      const url = filterCollectedUrl(entry.name);
      startAndEndSpan(span, requestStartTimestamp, responseEndTimestamp, {
        name: spanStreamingEnabled ? BROWSER_NAVIGATION_TIMING_SPAN_NAMES[D$1] : entry.name,
        attributes: {
          [cd]: D$1,
          [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "auto.ui.browser.metrics",
          [zg]: url
        }
      });
      startAndEndSpan(span, responseStartTimestamp, responseEndTimestamp, {
        name: spanStreamingEnabled ? BROWSER_NAVIGATION_TIMING_SPAN_NAMES[m$1] : entry.name,
        attributes: {
          [cd]: m$1,
          [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "auto.ui.browser.metrics",
          [zg]: url
        }
      });
    }
  }
  function _addResourceSpans(span, entry, resourceUrl, startTime, duration, timeOrigin, ignoredResourceSpanOps, spanStreamingEnabled) {
    if (entry.initiatorType === "xmlhttprequest" || entry.initiatorType === "fetch") {
      return;
    }
    const op = entry.initiatorType ? `resource.${entry.initiatorType}` : o$1;
    if (ignoredResourceSpanOps?.includes(op)) {
      return;
    }
    const attributes = {
      [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "auto.resource.browser.metrics"
    };
    const parsedUrl = parseUrl(resourceUrl);
    if (parsedUrl.protocol) {
      attributes[Qg] = parsedUrl.protocol.split(":").pop();
    }
    const host = parsedUrl.host?.replace(/^.*@/, "");
    if (host) {
      attributes[Zd] = host;
    }
    const domain = host?.replace(/:\d+$/, "");
    if (domain) {
      attributes[Ug] = domain;
    }
    attributes[So] = resourceUrl.includes(WINDOW$1.location.origin);
    attributes[zg] = filterCollectedUrl(resourceUrl);
    _setResourceRequestAttributes(entry, attributes, [
      // https://developer.mozilla.org/en-US/docs/Web/API/PerformanceResourceTiming/responseStatus
      ["responseStatus", Do],
      ["transferSize", Po],
      ["encodedBodySize", Ao],
      ["decodedBodySize", "http.response.body.decoded_size"],
      // https://developer.mozilla.org/en-US/docs/Web/API/PerformanceResourceTiming/renderBlockingStatus
      ["renderBlockingStatus", "resource.render_blocking_status"],
      // https://developer.mozilla.org/en-US/docs/Web/API/PerformanceResourceTiming/deliveryType
      ["deliveryType", "http.response_delivery_type"]
    ]);
    const attributesWithResourceTiming = { ...attributes, ...resourceTimingToSpanAttributes(entry) };
    const startTimestamp = timeOrigin + startTime;
    const endTimestamp = startTimestamp + duration;
    startAndEndSpan(span, startTimestamp, endTimestamp, {
      // With span streaming, span names have to be low cardinality, so we can't fall back to the URL.
      name: spanStreamingEnabled ? domain || RESOURCE_SPAN_NAME_FALLBACK : resourceUrl.replace(WINDOW$1.location.origin, ""),
      op,
      attributes: attributesWithResourceTiming
    });
  }
  function _trackNavigator(span, spanStreamingEnabled) {
    const navigator = WINDOW$1.navigator;
    if (!navigator) {
      return;
    }
    const connection = navigator.connection;
    if (connection) {
      if (connection.effectiveType) {
        span.setAttribute(
          spanStreamingEnabled ? Mp : "effectiveConnectionType",
          connection.effectiveType
        );
      }
      if (connection.type) {
        span.setAttribute(spanStreamingEnabled ? Gp : "connectionType", connection.type);
      }
      if (isMeasurementValue(connection.rtt)) {
        if (spanStreamingEnabled) {
          span.setAttribute(Up, connection.rtt);
        } else if (spanToJSON(span).attributes[cd] === "pageload") {
          setMeasurement("connection.rtt", connection.rtt, "millisecond");
        }
      }
    }
    if (isMeasurementValue(navigator.deviceMemory)) {
      if (spanStreamingEnabled) {
        span.setAttribute("device.memory.estimated_capacity", navigator.deviceMemory);
      } else {
        span.setAttribute("deviceMemory", `${navigator.deviceMemory} GB`);
      }
    }
    if (isMeasurementValue(navigator.hardwareConcurrency)) {
      if (spanStreamingEnabled) {
        span.setAttribute("device.processor_count", navigator.hardwareConcurrency);
      } else {
        span.setAttribute("hardwareConcurrency", String(navigator.hardwareConcurrency));
      }
    }
  }
  function _setResourceRequestAttributes(entry, attributes, properties) {
    properties.forEach(([entryKey, attributeKey]) => {
      const entryVal = entry[entryKey];
      if (entryVal != null && (typeof entryVal === "number" && entryVal < MAX_INT_AS_BYTES || typeof entryVal === "string")) {
        attributes[attributeKey] = entryVal;
      }
    });
  }

  const DEFAULT_MAX_STRING_LENGTH = 80;
  const accessors = {};
  try {
    if (typeof Node !== "undefined") {
      accessors.parentNode = Object.getOwnPropertyDescriptor(Node.prototype, "parentNode").get;
    }
    if (typeof Element !== "undefined") {
      accessors.tagName = Object.getOwnPropertyDescriptor(Element.prototype, "tagName").get;
      accessors.id = Object.getOwnPropertyDescriptor(Element.prototype, "id").get;
      accessors.className = Object.getOwnPropertyDescriptor(Element.prototype, "className").get;
      accessors.getAttribute = Element.prototype.getAttribute;
    }
    if (typeof HTMLElement !== "undefined") {
      accessors.dataset = Object.getOwnPropertyDescriptor(HTMLElement.prototype, "dataset").get;
    }
  } catch {
  }
  function _safeRead(el, prop, arg) {
    const fn = accessors[prop];
    if (fn) {
      try {
        return fn.call(el, arg);
      } catch {
      }
    }
    const val = el[prop];
    return typeof val === "function" ? val.call(el, arg) : val;
  }
  function htmlTreeAsString(elem, options = {}) {
    if (!elem) {
      return "<unknown>";
    }
    try {
      let currentElem = elem;
      const MAX_TRAVERSE_HEIGHT = 5;
      const out = [];
      let height = 0;
      let len = 0;
      const separator = " > ";
      const sepLength = separator.length;
      let nextStr;
      const keyAttrs = Array.isArray(options) ? options : options.keyAttrs;
      const maxStringLength = !Array.isArray(options) && options.maxStringLength || DEFAULT_MAX_STRING_LENGTH;
      while (currentElem && height++ < MAX_TRAVERSE_HEIGHT) {
        nextStr = _htmlElementAsString(currentElem, keyAttrs);
        if (nextStr === "html" || height > 1 && len + out.length * sepLength + nextStr.length >= maxStringLength) {
          break;
        }
        out.push(nextStr);
        len += nextStr.length;
        currentElem = _safeRead(currentElem, "parentNode");
      }
      return out.reverse().join(separator);
    } catch {
      return "<unknown>";
    }
  }
  function _htmlElementAsString(el, keyAttrs) {
    const out = [];
    const tagName = _safeRead(el, "tagName");
    if (!tagName) {
      return "";
    }
    if (typeof HTMLElement !== "undefined") {
      if (el instanceof HTMLElement) {
        const dataset = _safeRead(el, "dataset");
        if (dataset) {
          if (dataset["sentryComponent"]) {
            return dataset["sentryComponent"];
          }
          if (dataset["sentryElement"]) {
            return dataset["sentryElement"];
          }
        }
      }
    }
    out.push(tagName.toLowerCase());
    const keyAttrPairs = keyAttrs?.length ? keyAttrs.filter((keyAttr) => _safeRead(el, "getAttribute", keyAttr)).map((keyAttr) => [keyAttr, _safeRead(el, "getAttribute", keyAttr)]) : null;
    if (keyAttrPairs?.length) {
      keyAttrPairs.forEach((keyAttrPair) => {
        out.push(`[${keyAttrPair[0]}="${keyAttrPair[1]}"]`);
      });
    } else {
      const id = _safeRead(el, "id");
      if (id) {
        out.push(`#${id}`);
      }
      const className = _safeRead(el, "className");
      if (className && isString(className)) {
        const classes = className.split(/\s+/);
        for (const c of classes) {
          out.push(`.${c}`);
        }
      }
    }
    for (const k of ["aria-label", "type", "name", "title", "alt"]) {
      const attr = _safeRead(el, "getAttribute", k);
      if (attr) {
        out.push(`[${k}="${attr}"]`);
      }
    }
    return out.join("");
  }

  const MAX_PLAUSIBLE_LCP_DURATION = 6e4;
  function isValidLcpMetric(lcpValue) {
    return lcpValue != null && lcpValue > 0 && lcpValue <= MAX_PLAUSIBLE_LCP_DURATION;
  }

  function addPageListener(type, listener, options) {
    if (WINDOW$1.document) {
      WINDOW$1.addEventListener(type, listener, options);
    }
  }
  function removePageListener(type, listener, options) {
    if (WINDOW$1.document) {
      WINDOW$1.removeEventListener(type, listener, options);
    }
  }
  const getNavigationEntry = (checkResponseStart = true) => {
    const navigationEntry = WINDOW$1.performance?.getEntriesByType?.("navigation")[0];
    if (
      // sentry-specific change:
      // We don't want to check for responseStart for our own use of `getNavigationEntry`
      !checkResponseStart || navigationEntry && navigationEntry.responseStart > 0 && navigationEntry.responseStart < performance.now()
    ) {
      return navigationEntry;
    }
  };
  const getActivationStart = () => {
    const navEntry = getNavigationEntry();
    return navEntry?.activationStart ?? 0;
  };
  const onHidden = (cb) => {
    const onHiddenCallback = (event) => {
      if (WINDOW$1.document?.visibilityState === "hidden") {
        cb(event);
      }
    };
    addPageListener("visibilitychange", onHiddenCallback, { capture: true });
  };
  let firstHiddenTime = -1;
  const onHiddenFunctions = /* @__PURE__ */ new Set();
  const initHiddenTime = () => {
    return WINDOW$1.document?.visibilityState === "hidden" && !WINDOW$1.document?.prerendering ? 0 : Infinity;
  };
  const onVisibilityUpdate = (event) => {
    if (WINDOW$1.document?.visibilityState === "hidden" && firstHiddenTime > -1) {
      if (event.type === "visibilitychange") {
        for (const onHiddenFunction of onHiddenFunctions) {
          onHiddenFunction();
        }
      }
      if (!isFinite(firstHiddenTime)) {
        firstHiddenTime = event.type === "visibilitychange" ? event.timeStamp : 0;
        removePageListener("prerenderingchange", onVisibilityUpdate, true);
      }
    }
  };
  const getVisibilityWatcher = () => {
    if (WINDOW$1.document && firstHiddenTime < 0) {
      const activationStart = getActivationStart();
      const firstVisibilityStateHiddenTime = !WINDOW$1.document.prerendering ? globalThis.performance.getEntriesByType("visibility-state").filter((e) => e.name === "hidden" && e.startTime > activationStart)[0]?.startTime : void 0;
      firstHiddenTime = firstVisibilityStateHiddenTime ?? initHiddenTime();
      addPageListener("visibilitychange", onVisibilityUpdate, true);
      addPageListener("prerenderingchange", onVisibilityUpdate, true);
    }
    return {
      get firstHiddenTime() {
        return firstHiddenTime;
      },
      onHidden(cb) {
        onHiddenFunctions.add(cb);
      }
    };
  };
  const whenIdleOrHidden = (cb) => {
    const rIC = WINDOW$1.requestIdleCallback || WINDOW$1.setTimeout;
    if (WINDOW$1.document?.visibilityState === "hidden") {
      cb();
    } else {
      let called = false;
      const runOnce = () => {
        if (!called) {
          cb();
          called = true;
        }
      };
      addPageListener("visibilitychange", runOnce, { once: true, capture: true });
      rIC(() => {
        runOnce();
        removePageListener("visibilitychange", runOnce, { capture: true });
      });
    }
  };

  let _measurements = {};
  let _lcpEntry;
  let _clsEntry;
  let _navigationType;
  function startTrackingWebVitals({ trackCls, trackLcp }) {
    const performance = getBrowserPerformanceAPI();
    if (performance && browserPerformanceTimeOrigin()) {
      const lcpCleanupCallback = trackLcp ? _trackLCP() : void 0;
      const clsCleanupCallback = trackCls ? _trackCLS() : void 0;
      const ttfbCleanupCallback = _trackTtfb();
      const fcpCleanupCallback = _trackFcp();
      const fpCleanupCallback = _trackFp();
      return () => {
        ttfbCleanupCallback();
        fcpCleanupCallback();
        fpCleanupCallback();
        lcpCleanupCallback?.();
        clsCleanupCallback?.();
      };
    }
    return () => void 0;
  }
  function _trackCLS() {
    return addClsInstrumentationHandler(({ metric }) => {
      const entry = metric.entries[metric.entries.length - 1];
      if (!entry) {
        return;
      }
      _measurements["cls"] = { value: metric.value, unit: "" };
      _clsEntry = entry;
    }, true);
  }
  function _trackLCP() {
    return addLcpInstrumentationHandler(({ metric }) => {
      const entry = metric.entries[metric.entries.length - 1];
      if (!entry || !isValidLcpMetric(metric.value)) {
        return;
      }
      _measurements["lcp"] = { value: metric.value, unit: "millisecond" };
      _lcpEntry = entry;
    }, true);
  }
  function _trackTtfb() {
    return addTtfbInstrumentationHandler(({ metric }) => {
      _navigationType = metric.navigationType;
      const entry = metric.entries[metric.entries.length - 1];
      if (!entry) {
        return;
      }
      _measurements["ttfb"] = { value: metric.value, unit: "millisecond" };
    });
  }
  function _trackFcp() {
    return addFcpInstrumentationHandler(({ metric }) => {
      _navigationType = metric.navigationType;
      _measurements["fcp"] = { value: metric.value, unit: "millisecond" };
    });
  }
  function _trackFp() {
    return addPerformanceInstrumentationHandler("paint", ({ entries }) => {
      const firstHidden = getVisibilityWatcher();
      for (const entry of entries) {
        if (entry.name === "first-paint" && entry.startTime < firstHidden.firstHiddenTime) {
          _measurements["fp"] = { value: entry.startTime, unit: "millisecond" };
        }
      }
    });
  }
  function addWebVitalsToSpan(span, options) {
    const origin = browserPerformanceTimeOrigin();
    if (!getBrowserPerformanceAPI()?.getEntries || !origin) {
      resetWebVitalState();
      return;
    }
    const { spanStreamingEnabled, recordClsOnPageloadSpan, recordLcpOnPageloadSpan } = options;
    const timeOrigin = msToSec(origin);
    if (spanToJSON(span).attributes[cd] === "pageload") {
      _addTtfbRequestTimeToMeasurements(_measurements);
      _rebaseFpAgainstActivationStart(_measurements);
      if (spanStreamingEnabled) {
        const setAttr = (shortWebVitalName, value, customAttrName) => {
          const attrKey = customAttrName ?? `browser.web_vital.${shortWebVitalName}.value`;
          span.setAttribute(attrKey, value);
          debug.log("Setting web vital attribute", { [attrKey]: value }, "on pageload span");
        };
        ["ttfb", "fp", "fcp"].forEach((measurementName) => {
          if (_measurements[measurementName]) {
            setAttr(measurementName, _measurements[measurementName].value);
          }
        });
        if (_measurements["ttfb.requestTime"]) {
          setAttr("ttfb.requestTime", _measurements["ttfb.requestTime"].value, "browser.web_vital.ttfb.request_time");
        }
      } else {
        if (!recordClsOnPageloadSpan) {
          delete _measurements.cls;
        }
        if (!recordLcpOnPageloadSpan) {
          delete _measurements.lcp;
        }
        Object.entries(_measurements).forEach(([measurementName, measurement]) => {
          setMeasurement(measurementName, measurement.value, measurement.unit, span);
        });
        _setWebVitalAttributes(span, options);
      }
      if (_navigationType) {
        span.setAttribute(Mi, _navigationType);
      }
      span.setAttribute(spanStreamingEnabled ? "browser.performance.time_origin" : "performance.timeOrigin", timeOrigin);
      span.setAttribute(
        spanStreamingEnabled ? "browser.performance.navigation.activation_start" : "performance.activationStart",
        getActivationStart()
      );
    }
    resetWebVitalState();
  }
  function resetWebVitalState() {
    _lcpEntry = void 0;
    _clsEntry = void 0;
    _navigationType = void 0;
    _measurements = {};
  }
  function _setWebVitalAttributes(span, options) {
    if (_lcpEntry && options.recordLcpOnPageloadSpan) {
      if (_lcpEntry.element) {
        span.setAttribute("lcp.element", htmlTreeAsString(_lcpEntry.element));
      }
      if (_lcpEntry.id) {
        span.setAttribute("lcp.id", _lcpEntry.id);
      }
      if (_lcpEntry.url) {
        span.setAttribute("lcp.url", _lcpEntry.url.trim().slice(0, 200));
      }
      if (_lcpEntry.loadTime != null) {
        span.setAttribute("lcp.loadTime", _lcpEntry.loadTime);
      }
      if (_lcpEntry.renderTime != null) {
        span.setAttribute("lcp.renderTime", _lcpEntry.renderTime);
      }
      span.setAttribute("lcp.size", _lcpEntry.size);
    }
    if (_clsEntry?.sources && options.recordClsOnPageloadSpan) {
      _clsEntry.sources.forEach(
        (source, index) => span.setAttribute(`cls.source.${index + 1}`, htmlTreeAsString(source.node))
      );
    }
  }
  function _rebaseFpAgainstActivationStart(measurements) {
    const fp = measurements["fp"];
    if (fp) {
      fp.value = Math.max(fp.value - getActivationStart(), 0);
    }
  }
  function _addTtfbRequestTimeToMeasurements(_measurements2) {
    const navEntry = getNavigationEntry(false);
    if (!navEntry) {
      return;
    }
    const { responseStart, requestStart } = navEntry;
    if (requestStart <= responseStart) {
      _measurements2["ttfb.requestTime"] = {
        value: responseStart - requestStart,
        unit: "millisecond"
      };
    }
  }

  const LAST_INTERACTIONS = [];
  const INTERACTIONS_SPAN_MAP = /* @__PURE__ */ new Map();
  const UNKNOWN_ELEMENT_NAME = "<unknown>";
  const ELEMENT_NAME_TIMESTAMP_MAP = /* @__PURE__ */ new Map();
  const MAX_PLAUSIBLE_INP_DURATION = 60;
  const INP_ENTRY_MAP = {
    click: "click",
    pointerdown: "click",
    pointerup: "click",
    mousedown: "click",
    mouseup: "click",
    touchstart: "click",
    touchend: "click",
    mouseover: "hover",
    mouseout: "hover",
    mouseenter: "hover",
    mouseleave: "hover",
    pointerover: "hover",
    pointerout: "hover",
    pointerenter: "hover",
    pointerleave: "hover",
    dragstart: "drag",
    dragend: "drag",
    drag: "drag",
    dragenter: "drag",
    dragleave: "drag",
    dragover: "drag",
    drop: "drag",
    keydown: "press",
    keyup: "press",
    keypress: "press",
    input: "press"
  };
  function getCachedInteractionContext(interactionId) {
    return interactionId != null ? INTERACTIONS_SPAN_MAP.get(interactionId) : void 0;
  }
  function registerInpInteractionListener() {
    const interactionEvents = Object.keys(INP_ENTRY_MAP);
    if (isBrowser()) {
      interactionEvents.forEach((eventType) => {
        WINDOW$1.addEventListener(eventType, captureElementFromEvent, { capture: true, passive: true });
      });
    }
    function captureElementFromEvent(event) {
      const target = event.target;
      if (!target) {
        return;
      }
      const elementName = htmlTreeAsString(target);
      const timestamp = Math.round(event.timeStamp);
      if (!elementName || elementName === UNKNOWN_ELEMENT_NAME) {
        return;
      }
      if (ELEMENT_NAME_TIMESTAMP_MAP.has(timestamp)) {
        return;
      }
      ELEMENT_NAME_TIMESTAMP_MAP.set(timestamp, elementName);
      if (ELEMENT_NAME_TIMESTAMP_MAP.size > 50) {
        const firstKey = ELEMENT_NAME_TIMESTAMP_MAP.keys().next().value;
        if (firstKey !== void 0) {
          ELEMENT_NAME_TIMESTAMP_MAP.delete(firstKey);
        }
      }
    }
    function resolveElementNameFromEntry(entry) {
      const timestamp = Math.round(entry.startTime);
      let elementName = ELEMENT_NAME_TIMESTAMP_MAP.get(timestamp);
      if (!elementName) {
        for (let offset = -5; offset <= 5; offset++) {
          const nearbyName = ELEMENT_NAME_TIMESTAMP_MAP.get(timestamp + offset);
          if (nearbyName) {
            elementName = nearbyName;
            break;
          }
        }
      }
      return elementName || UNKNOWN_ELEMENT_NAME;
    }
    const handleEntries = ({ entries }) => {
      const activeSpan = getActiveSpan();
      const activeRootSpan = activeSpan && getRootSpan(activeSpan);
      entries.forEach((entry) => {
        if (!isPerformanceEventTiming(entry)) {
          return;
        }
        const interactionId = entry.interactionId;
        if (interactionId == null) {
          return;
        }
        if (INTERACTIONS_SPAN_MAP.has(interactionId)) {
          return;
        }
        const elementName = entry.target ? htmlTreeAsString(entry.target) : resolveElementNameFromEntry(entry);
        if (LAST_INTERACTIONS.length > 10) {
          const last = LAST_INTERACTIONS.shift();
          INTERACTIONS_SPAN_MAP.delete(last);
        }
        LAST_INTERACTIONS.push(interactionId);
        INTERACTIONS_SPAN_MAP.set(interactionId, {
          span: activeRootSpan,
          elementName
        });
      });
    };
    addPerformanceInstrumentationHandler("event", handleEntries);
    addPerformanceInstrumentationHandler("first-input", handleEntries);
  }

  const BOT_USER_AGENT_RE = /Googlebot|Google-InspectionTool|Storebot-Google|Bingbot|Slurp|DuckDuckBot|Baiduspider|YandexBot|Facebot|facebookexternalhit|LinkedInBot|Twitterbot|Applebot/i;
  function isBotUserAgent() {
    const nav = WINDOW$1.navigator;
    if (!nav?.userAgent) {
      return false;
    }
    return BOT_USER_AGENT_RE.test(nav.userAgent);
  }

  function getComponentName(elem, maxTraverseHeight = 5) {
    if (!GLOBAL_OBJ.HTMLElement) {
      return null;
    }
    let currentElem = elem;
    for (let i = 0; i < maxTraverseHeight; i++) {
      if (!currentElem) {
        return null;
      }
      if (currentElem instanceof HTMLElement) {
        if (currentElem.dataset["sentryComponent"]) {
          return currentElem.dataset["sentryComponent"];
        }
        if (currentElem.dataset["sentryElement"]) {
          return currentElem.dataset["sentryElement"];
        }
      }
      currentElem = currentElem.parentNode;
    }
    return null;
  }

  function getLocationHref() {
    try {
      return WINDOW$1.document?.location.href ?? "";
    } catch {
      return "";
    }
  }

  function _emitWebVitalSpan(options) {
    const {
      name,
      op,
      origin,
      metricName,
      value,
      attributes: passedAttributes,
      parentSpan,
      startTime,
      endTime,
      standalone,
      softNavigationId,
      navigationType
    } = options;
    const segmentSpan = parentSpan && getRootSpan(parentSpan);
    const segmentName = segmentSpan ? spanToJSON(segmentSpan).name : getCurrentScope().getScopeData().transactionName;
    const attributes = {
      [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: origin,
      [SEMANTIC_ATTRIBUTE_SENTRY_OP]: op,
      [SEMANTIC_ATTRIBUTE_EXCLUSIVE_TIME]: 0,
      [`browser.web_vital.${metricName}.value`]: value,
      // oxlint-disable-next-line typescript-eslint/no-deprecated
      [Fd]: segmentName,
      [Ad]: segmentName,
      // Web vital score calculation relies on the user agent
      [Jg]: WINDOW$1.navigator?.userAgent,
      ...passedAttributes
    };
    if (parentSpan && spanToJSON(parentSpan).attributes[SEMANTIC_ATTRIBUTE_SENTRY_OP] === "pageload") {
      attributes["sentry.pageload.span_id"] = parentSpan.spanContext().spanId;
    }
    if (softNavigationId != null) {
      attributes[Li] = softNavigationId;
    }
    if (navigationType) {
      attributes[Mi] = navigationType;
    }
    if (standalone) {
      Object.assign(attributes, getReplayAttributes());
    }
    const span = startInactiveSpan({
      name,
      attributes,
      startTime,
      parentSpan,
      // oxlint-disable-next-line typescript/no-deprecated -- intentional during the v1/v2 transition; see the TODO(standalone) above
      experimental: standalone ? { standalone: true } : void 0
    });
    if (span) {
      span.end(endTime ?? startTime);
    }
  }
  function getReplayAttributes() {
    const replay = getClient()?.getIntegrationByName("Replay");
    const replayId = replay?.getReplayId(true);
    if (!replayId) {
      return {};
    }
    return {
      [fd]: replayId,
      // Not the `SENTRY_REPLAY_IS_BUFFERING` convention: that one has no `sentry._internal.` prefix, and
      // the rest of the SDK sets the prefixed key (see `logs/internal.ts`, `metrics/internal.ts`).
      "sentry._internal.replay_is_buffering": replay.getRecordingMode() === "buffer" ? true : void 0
    };
  }

  function listenForWebVitalReportEvents(client, collectorCallback) {
    let pageloadSpan;
    let collected = false;
    function _runCollectorCallbackOnce() {
      if (!collected && pageloadSpan) {
        collectorCallback(pageloadSpan);
      }
      collected = true;
    }
    onHidden(() => {
      _runCollectorCallbackOnce();
    });
    const unsubscribeStartNavigation = client.on("beforeStartNavigationSpan", (_, options) => {
      if (!options?.isRedirect) {
        _runCollectorCallbackOnce();
        unsubscribeStartNavigation();
        unsubscribeAfterStartPageLoadSpan();
      }
    });
    const unsubscribeAfterStartPageLoadSpan = client.on("afterStartPageLoadSpan", (span) => {
      pageloadSpan = span;
      unsubscribeAfterStartPageLoadSpan();
    });
  }

  const INTERACTION_TYPE_TO_SPAN_OP = {
    click: v$1,
    hover: H$1,
    drag: V,
    press: k$1
  };
  const INTERACTION_TYPE_TO_SPAN_NAME_FALLBACK = {
    click: UI_INTERACTION_CLICK_SPAN_NAME_FALLBACK,
    hover: UI_INTERACTION_HOVER_SPAN_NAME_FALLBACK,
    drag: UI_INTERACTION_DRAG_SPAN_NAME_FALLBACK,
    press: UI_INTERACTION_PRESS_SPAN_NAME_FALLBACK
  };
  function trackWebVitalPerNavigation(client, addInstrumentationHandler, send) {
    let pageloadSpan;
    client.on("afterStartPageLoadSpan", (span) => {
      pageloadSpan = span;
    });
    let bfcacheNavigationSpan;
    client.on("spanStart", (span) => {
      const attributes = spanToJSON(span).attributes;
      if (attributes?.[SEMANTIC_ATTRIBUTE_SENTRY_OP] === E$1 && attributes[Mi] === "back-forward-cache") {
        bfcacheNavigationSpan = span;
      }
    });
    addInstrumentationHandler(({ metric }) => {
      const navigationSpan = getNavigationSpanForMetric(metric);
      if (metric.navigationType === "soft-navigation") {
        if (navigationSpan) {
          send(metric, navigationSpan, metric.navigationId);
        } else {
          debug.log(`[SoftNav] Dropping ${metric.name} for uncorrelated soft navigation ${metric.navigationId}`);
        }
        return;
      }
      if (metric.navigationType === "back-forward-cache") {
        send(metric, bfcacheNavigationSpan, void 0);
        return;
      }
      send(metric, pageloadSpan, void 0);
    });
  }
  function trackLcpAsSpan(client, perNavigation = false) {
    if (!supportsWebVital("largest-contentful-paint")) {
      return;
    }
    if (perNavigation) {
      trackWebVitalPerNavigation(client, addLcpInstrumentationHandler, (metric, parentSpan, softNavigationId) => {
        const entry = metric.entries[metric.entries.length - 1];
        _sendLcpSpan(
          metric.value,
          entry,
          parentSpan,
          softNavigationId,
          metric.navigationType,
          metric.navigationStartTime
        );
      });
      return;
    }
    let lcpValue = 0;
    let lcpEntry;
    let lcpNavigationType;
    const cleanupLcpHandler = addLcpInstrumentationHandler(({ metric }) => {
      lcpNavigationType = metric.navigationType;
      const entry = metric.entries[metric.entries.length - 1];
      if (!entry || !isValidLcpMetric(metric.value)) {
        return;
      }
      lcpValue = metric.value;
      lcpEntry = entry;
    }, true);
    listenForWebVitalReportEvents(client, (pageloadSpan) => {
      _sendLcpSpan(lcpValue, lcpEntry, pageloadSpan, void 0, lcpNavigationType);
      cleanupLcpHandler();
    });
  }
  function _sendLcpSpan(lcpValue, entry, pageloadSpan, softNavigationId, navigationType, navigationStartTime) {
    if (!isValidLcpMetric(lcpValue)) {
      return;
    }
    debug.log(`Sending LCP span (${lcpValue})`);
    const performanceTimeOrigin = browserPerformanceTimeOrigin() || 0;
    const startTime = msToSec(performanceTimeOrigin + (navigationStartTime || 0));
    const endTime = entry ? msToSec(performanceTimeOrigin + entry.startTime) : startTime + msToSec(lcpValue);
    const selector = entry ? htmlTreeAsString(entry.element) : void 0;
    const componentName = entry?.element ? getComponentName(entry.element) : null;
    const client = getClient();
    const hasSpanStreaming = !!client && hasSpanStreamingEnabled(client);
    const name = hasSpanStreaming ? componentName || UI_WEBVITAL_LCP_SPAN_NAME_FALLBACK : selector ?? UI_WEBVITAL_LCP_SPAN_NAME_FALLBACK;
    const attributes = {};
    if (selector) {
      attributes["browser.web_vital.lcp.element"] = selector;
    }
    if (componentName) {
      attributes[Ig] = componentName;
    }
    entry?.id && (attributes["browser.web_vital.lcp.id"] = entry.id);
    entry?.url && (attributes["browser.web_vital.lcp.url"] = entry.url);
    entry?.loadTime != null && (attributes["browser.web_vital.lcp.load_time"] = entry.loadTime);
    entry?.renderTime != null && (attributes["browser.web_vital.lcp.render_time"] = entry.renderTime);
    entry?.size != null && (attributes["browser.web_vital.lcp.size"] = entry.size);
    _emitWebVitalSpan({
      name,
      op: K,
      origin: "auto.http.browser.lcp",
      metricName: "lcp",
      value: lcpValue,
      attributes,
      parentSpan: pageloadSpan,
      startTime,
      endTime,
      softNavigationId,
      navigationType
    });
  }
  function trackClsAsSpan(client, perNavigation = false) {
    if (!supportsWebVital("layout-shift")) {
      return;
    }
    if (perNavigation) {
      trackWebVitalPerNavigation(client, addClsInstrumentationHandler, (metric, parentSpan, softNavigationId) => {
        const entry = metric.entries[metric.entries.length - 1];
        _sendClsSpan(
          metric.value,
          entry,
          parentSpan,
          softNavigationId,
          metric.navigationType,
          metric.navigationStartTime
        );
      });
      return;
    }
    let clsValue = 0;
    let clsEntry;
    let clsNavigationType;
    const cleanupClsHandler = addClsInstrumentationHandler(({ metric }) => {
      clsNavigationType = metric.navigationType;
      const entry = metric.entries[metric.entries.length - 1];
      if (!entry) {
        return;
      }
      clsValue = metric.value;
      clsEntry = entry;
    }, true);
    listenForWebVitalReportEvents(client, (pageloadSpan) => {
      _sendClsSpan(clsValue, clsEntry, pageloadSpan, void 0, clsNavigationType);
      cleanupClsHandler();
    });
  }
  function _sendClsSpan(clsValue, entry, pageloadSpan, softNavigationId, navigationType, navigationStartTime) {
    debug.log(`Sending CLS span (${clsValue})`);
    const performanceTimeOrigin = browserPerformanceTimeOrigin();
    const offset = entry?.startTime ?? navigationStartTime ?? 0;
    const startTime = performanceTimeOrigin ? msToSec(performanceTimeOrigin + offset) : timestampInSeconds();
    const firstSourceNode = entry?.sources[0]?.node;
    const selector = entry ? htmlTreeAsString(firstSourceNode) : void 0;
    const componentName = firstSourceNode ? getComponentName(firstSourceNode) : null;
    const client = getClient();
    const hasSpanStreaming = !!client && hasSpanStreamingEnabled(client);
    const name = hasSpanStreaming ? componentName || UI_WEBVITAL_CLS_SPAN_NAME_FALLBACK : selector ?? UI_WEBVITAL_CLS_SPAN_NAME_FALLBACK;
    const attributes = {};
    if (componentName) {
      attributes[Ig] = componentName;
    }
    if (entry?.sources) {
      entry.sources.forEach((source, index) => {
        attributes[`browser.web_vital.cls.source.${index + 1}`] = htmlTreeAsString(source.node);
      });
    }
    _emitWebVitalSpan({
      name,
      op: f$1,
      origin: "auto.http.browser.cls",
      metricName: "cls",
      value: clsValue,
      attributes,
      parentSpan: pageloadSpan,
      startTime,
      softNavigationId,
      navigationType
    });
  }
  function trackInpAsSpan(client, perNavigation = false) {
    const performance = getBrowserPerformanceAPI();
    if (!performance || !browserPerformanceTimeOrigin()) {
      return;
    }
    const standalone = !hasSpanStreamingEnabled(client);
    if (perNavigation) {
      trackWebVitalPerNavigation(client, addInpInstrumentationHandler, (metric, parentSpan, softNavigationId) => {
        if (isPlausibleInp(metric)) {
          _sendInpSpan(metric.value, findInpEntry(metric), standalone, parentSpan, softNavigationId, metric);
        }
      });
      return;
    }
    const onInp = ({ metric }) => {
      if (isPlausibleInp(metric)) {
        _sendInpSpan(metric.value, findInpEntry(metric), standalone, void 0, void 0, metric);
      }
    };
    addInpInstrumentationHandler(onInp);
  }
  function isPlausibleInp(metric) {
    return metric.value != null && msToSec(metric.value) <= MAX_PLAUSIBLE_INP_DURATION;
  }
  function findInpEntry(metric) {
    return metric.entries.find((e) => e.duration === metric.value && INP_ENTRY_MAP[e.name]);
  }
  function _sendInpSpan(inpValue, entry, standalone = false, attributedSpan, softNavigationId, metric) {
    debug.log(`Sending INP span (${inpValue})`);
    const startTime = msToSec(
      browserPerformanceTimeOrigin() + (entry?.startTime ?? metric?.navigationStartTime ?? 0)
    );
    const duration = msToSec(inpValue);
    const entryInteractionType = entry && INP_ENTRY_MAP[entry.name];
    const interactionType = entryInteractionType || "click";
    const cachedContext = entry && getCachedInteractionContext(entry.interactionId);
    const activeSpan = getActiveSpan();
    const rootSpan = activeSpan ? getRootSpan(activeSpan) : void 0;
    const spanToUse = attributedSpan || cachedContext?.span || rootSpan;
    const selector = cachedContext?.elementName || (entry ? htmlTreeAsString(entry.target) : void 0);
    const componentName = entry?.target ? getComponentName(entry.target) : null;
    const client = getClient();
    const hasSpanStreaming = !!client && hasSpanStreamingEnabled(client);
    const fallbackName = INTERACTION_TYPE_TO_SPAN_NAME_FALLBACK[interactionType];
    const name = hasSpanStreaming ? componentName || fallbackName : selector ?? "Interaction to next paint";
    const attributes = {
      [SEMANTIC_ATTRIBUTE_EXCLUSIVE_TIME]: entry?.duration ?? inpValue
    };
    selector && selector !== UNKNOWN_ELEMENT_NAME && (attributes["browser.web_vital.inp.target"] = selector);
    entryInteractionType && (attributes["browser.web_vital.inp.interaction_type"] = entryInteractionType);
    if (componentName) {
      attributes[Ig] = componentName;
    }
    _emitWebVitalSpan({
      name,
      op: INTERACTION_TYPE_TO_SPAN_OP[interactionType],
      origin: "auto.http.browser.inp",
      metricName: "inp",
      value: inpValue,
      attributes,
      startTime,
      endTime: startTime + duration,
      navigationType: metric?.navigationType,
      parentSpan: spanToUse,
      standalone,
      softNavigationId
    });
  }

  const DEBOUNCE_DURATION = 1e3;
  let debounceTimerID;
  let lastCapturedEventType;
  let lastCapturedEventTargetId;
  function addClickKeypressInstrumentationHandler(handler) {
    const type = "dom";
    addHandler$1(type, handler);
    maybeInstrument(type, instrumentDOM);
  }
  function instrumentDOM() {
    if (!WINDOW$1.document) {
      return;
    }
    const triggerDOMHandler = triggerHandlers$1.bind(null, "dom");
    const globalDOMEventHandler = makeDOMEventHandler(triggerDOMHandler, true);
    WINDOW$1.document.addEventListener("click", globalDOMEventHandler, false);
    WINDOW$1.document.addEventListener("keypress", globalDOMEventHandler, false);
    ["EventTarget", "Node"].forEach((target) => {
      const globalObject = WINDOW$1;
      const proto = globalObject[target]?.prototype;
      if (!proto?.hasOwnProperty?.("addEventListener")) {
        return;
      }
      fill(proto, "addEventListener", function(originalAddEventListener) {
        return function(type, listener, options) {
          if (type === "click" || type == "keypress") {
            try {
              const handlers = this.__sentry_instrumentation_handlers__ = this.__sentry_instrumentation_handlers__ || {};
              const handlerForType = handlers[type] = handlers[type] || { refCount: 0 };
              if (!handlerForType.handler) {
                const handler = makeDOMEventHandler(triggerDOMHandler);
                handlerForType.handler = handler;
                originalAddEventListener.call(this, type, handler, options);
              }
              handlerForType.refCount++;
            } catch {
            }
          }
          return originalAddEventListener.call(this, type, listener, options);
        };
      });
      fill(
        proto,
        "removeEventListener",
        function(originalRemoveEventListener) {
          return function(type, listener, options) {
            if (type === "click" || type == "keypress") {
              try {
                const handlers = this.__sentry_instrumentation_handlers__ || {};
                const handlerForType = handlers[type];
                if (handlerForType) {
                  handlerForType.refCount--;
                  if (handlerForType.refCount <= 0) {
                    originalRemoveEventListener.call(this, type, handlerForType.handler, options);
                    handlerForType.handler = void 0;
                    delete handlers[type];
                  }
                  if (Object.keys(handlers).length === 0) {
                    delete this.__sentry_instrumentation_handlers__;
                  }
                }
              } catch {
              }
            }
            return originalRemoveEventListener.call(this, type, listener, options);
          };
        }
      );
    });
  }
  function isSimilarToLastCapturedEvent(event) {
    if (event.type !== lastCapturedEventType) {
      return false;
    }
    try {
      if (!event.target || event.target._sentryId !== lastCapturedEventTargetId) {
        return false;
      }
    } catch {
    }
    return true;
  }
  function shouldSkipDOMEvent(eventType, target) {
    if (eventType !== "keypress") {
      return false;
    }
    if (!target?.tagName) {
      return true;
    }
    if (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable) {
      return false;
    }
    return true;
  }
  function makeDOMEventHandler(handler, globalListener = false) {
    return (event) => {
      if (!event || event["_sentryCaptured"]) {
        return;
      }
      const target = getEventTarget(event);
      if (shouldSkipDOMEvent(event.type, target)) {
        return;
      }
      addNonEnumerableProperty(event, "_sentryCaptured", true);
      if (target && !target._sentryId) {
        addNonEnumerableProperty(target, "_sentryId", uuid4());
      }
      const name = event.type === "keypress" ? "input" : event.type;
      if (!isSimilarToLastCapturedEvent(event)) {
        const handlerData = { event, name, global: globalListener };
        handler(handlerData);
        lastCapturedEventType = event.type;
        lastCapturedEventTargetId = target ? target._sentryId : void 0;
      }
      clearTimeout(debounceTimerID);
      debounceTimerID = WINDOW$1.setTimeout(() => {
        lastCapturedEventTargetId = void 0;
        lastCapturedEventType = void 0;
      }, DEBOUNCE_DURATION);
    };
  }
  function getEventTarget(event) {
    try {
      return event.target;
    } catch {
      return null;
    }
  }

  let lastHref;
  function supportsHistory() {
    return "history" in WINDOW$1 && !!WINDOW$1.history;
  }
  function addHistoryInstrumentationHandler(handler) {
    const type = "history";
    addHandler$1(type, handler);
    maybeInstrument(type, instrumentHistory);
  }
  function instrumentHistory() {
    WINDOW$1.addEventListener("popstate", () => {
      const to = WINDOW$1.location.href;
      const from = lastHref;
      lastHref = to;
      if (from === to) {
        return;
      }
      const handlerData = { from, to };
      triggerHandlers$1("history", handlerData);
    });
    if (!supportsHistory()) {
      return;
    }
    function historyReplacementFunction(originalHistoryFunction) {
      return function(...args) {
        const url = args.length > 2 ? args[2] : void 0;
        if (url) {
          const from = lastHref;
          const to = getAbsoluteUrl(String(url));
          lastHref = to;
          if (from === to) {
            return originalHistoryFunction.apply(this, args);
          }
          const handlerData = { from, to };
          triggerHandlers$1("history", handlerData);
        }
        return originalHistoryFunction.apply(this, args);
      };
    }
    fill(WINDOW$1.history, "pushState", historyReplacementFunction);
    fill(WINDOW$1.history, "replaceState", historyReplacementFunction);
  }
  function getAbsoluteUrl(urlOrPath) {
    try {
      const url = new URL(urlOrPath, WINDOW$1.location.origin);
      return url.toString();
    } catch {
      return urlOrPath;
    }
  }

  const cachedImplementations = {};
  function getNativeImplementation(name) {
    const cached = cachedImplementations[name];
    if (cached) {
      return cached;
    }
    let impl = WINDOW$1[name];
    if (isNativeFunction(impl)) {
      return cachedImplementations[name] = impl.bind(WINDOW$1);
    }
    const document = WINDOW$1.document;
    if (document && typeof document.createElement === "function") {
      try {
        const sandbox = document.createElement("iframe");
        sandbox.hidden = true;
        document.head.appendChild(sandbox);
        const contentWindow = sandbox.contentWindow;
        if (contentWindow?.[name]) {
          impl = contentWindow[name];
        }
        document.head.removeChild(sandbox);
      } catch (e) {
        debug.warn(`Could not create sandbox iframe for ${name} check, bailing to window.${name}: `, e);
      }
    }
    if (!impl) {
      return impl;
    }
    return cachedImplementations[name] = impl.bind(WINDOW$1);
  }
  function clearCachedImplementation(name) {
    cachedImplementations[name] = void 0;
  }

  const SENTRY_XHR_DATA_KEY = "__sentry_xhr_v3__";
  function addXhrInstrumentationHandler(handler) {
    const type = "xhr";
    addHandler$1(type, handler);
    maybeInstrument(type, instrumentXHR);
  }
  function instrumentXHR() {
    if (!WINDOW$1.XMLHttpRequest) {
      return;
    }
    const xhrproto = XMLHttpRequest.prototype;
    xhrproto.open = new Proxy(xhrproto.open, {
      apply(originalOpen, xhrOpenThisArg, xhrOpenArgArray) {
        let virtualError = new Error();
        const startTimestamp = timestampInSeconds() * 1e3;
        const method = isString(xhrOpenArgArray[0]) ? xhrOpenArgArray[0].toUpperCase() : void 0;
        const url = parseXhrUrlArg(xhrOpenArgArray[1]);
        if (!method || !url) {
          return originalOpen.apply(xhrOpenThisArg, xhrOpenArgArray);
        }
        xhrOpenThisArg[SENTRY_XHR_DATA_KEY] = {
          method,
          url,
          request_headers: {}
        };
        if (method === "POST" && url.match(/sentry_key/)) {
          xhrOpenThisArg.__sentry_own_request__ = true;
        }
        const onreadystatechangeHandler = () => {
          const xhrInfo = xhrOpenThisArg[SENTRY_XHR_DATA_KEY];
          if (!xhrInfo) {
            return;
          }
          if (xhrOpenThisArg.readyState === 4) {
            try {
              xhrInfo.status_code = xhrOpenThisArg.status;
            } catch {
            }
            const handlerData = {
              endTimestamp: timestampInSeconds() * 1e3,
              startTimestamp,
              xhr: xhrOpenThisArg,
              virtualError
            };
            triggerHandlers$1("xhr", handlerData);
            virtualError = void 0;
            xhrOpenThisArg.removeEventListener("readystatechange", onreadystatechangeHandler);
          }
        };
        if ("onreadystatechange" in xhrOpenThisArg && typeof xhrOpenThisArg.onreadystatechange === "function") {
          xhrOpenThisArg.onreadystatechange = new Proxy(xhrOpenThisArg.onreadystatechange, {
            apply(originalOnreadystatechange, onreadystatechangeThisArg, onreadystatechangeArgArray) {
              onreadystatechangeHandler();
              return originalOnreadystatechange.apply(onreadystatechangeThisArg, onreadystatechangeArgArray);
            }
          });
        } else {
          xhrOpenThisArg.addEventListener("readystatechange", onreadystatechangeHandler);
        }
        xhrOpenThisArg.setRequestHeader = new Proxy(xhrOpenThisArg.setRequestHeader, {
          apply(originalSetRequestHeader, setRequestHeaderThisArg, setRequestHeaderArgArray) {
            const [header, value] = setRequestHeaderArgArray;
            const xhrInfo = setRequestHeaderThisArg[SENTRY_XHR_DATA_KEY];
            if (xhrInfo && isString(header) && isString(value)) {
              xhrInfo.request_headers[header.toLowerCase()] = value;
            }
            return originalSetRequestHeader.apply(setRequestHeaderThisArg, setRequestHeaderArgArray);
          }
        });
        return originalOpen.apply(xhrOpenThisArg, xhrOpenArgArray);
      }
    });
    xhrproto.send = new Proxy(xhrproto.send, {
      apply(originalSend, sendThisArg, sendArgArray) {
        const sentryXhrData = sendThisArg[SENTRY_XHR_DATA_KEY];
        if (!sentryXhrData) {
          return originalSend.apply(sendThisArg, sendArgArray);
        }
        if (sendArgArray[0] !== void 0) {
          sentryXhrData.body = sendArgArray[0];
        }
        const handlerData = {
          startTimestamp: timestampInSeconds() * 1e3,
          xhr: sendThisArg
        };
        triggerHandlers$1("xhr", handlerData);
        return originalSend.apply(sendThisArg, sendArgArray);
      }
    });
  }
  function parseXhrUrlArg(url) {
    if (isString(url)) {
      return url;
    }
    try {
      return url.toString();
    } catch {
    }
    return void 0;
  }

  function parseXhrResponseHeaders(xhr) {
    let headers;
    try {
      headers = xhr.getAllResponseHeaders();
    } catch (error) {
      debug.error(error, "Failed to get xhr response headers", xhr);
      return {};
    }
    if (!headers) {
      return {};
    }
    return headers.split("\r\n").reduce((acc, line) => {
      const [key, value] = line.split(": ");
      if (value) {
        acc[key.toLowerCase()] = value;
      }
      return acc;
    }, {});
  }

  function isElement(wat) {
    if (typeof Element === "undefined") {
      return false;
    }
    try {
      return wat instanceof Element;
    } catch {
      return false;
    }
  }

  const WINDOW = GLOBAL_OBJ;
  let ignoreOnError = 0;
  const ignoredErrorReports = [];
  function shouldIgnoreOnError(data) {
    if (ignoreOnError > 0) {
      return true;
    }
    const index = data ? ignoredErrorReports.findIndex((report) => isSameErrorReport(report, data)) : -1;
    if (index === -1) {
      return false;
    }
    ignoredErrorReports.splice(index, 1);
    return true;
  }
  function isSameErrorReport(a, b) {
    return a.msg === b.msg && a.url === b.url && a.line === b.line && a.column === b.column;
  }
  function ignoreNextOnError() {
    ignoreOnError++;
    setTimeout(() => {
      ignoreOnError--;
    });
  }
  function wrap(fn, options = {}) {
    function isFunction(fn2) {
      return typeof fn2 === "function";
    }
    if (!isFunction(fn)) {
      return fn;
    }
    try {
      const hasOwnWrapper = Object.prototype.hasOwnProperty.call(fn, "__sentry_wrapped__");
      if (hasOwnWrapper) {
        const wrapper = fn.__sentry_wrapped__;
        if (typeof wrapper === "function") {
          return wrapper;
        } else {
          return fn;
        }
      }
      if (getOriginalFunction(fn)) {
        return fn;
      }
    } catch {
      return fn;
    }
    const sentryWrapped = function(...args) {
      GLOBAL_OBJ._sentryWrappedDepth = (GLOBAL_OBJ._sentryWrappedDepth || 0) + 1;
      try {
        const wrappedArguments = args.map((arg) => wrap(arg, options));
        return fn.apply(this, wrappedArguments);
      } catch (ex) {
        ignoreNextOnError();
        withScope((scope) => {
          scope.addEventProcessor((event) => {
            if (options.mechanism) {
              addExceptionTypeValue(event, void 0);
              addExceptionMechanism(event, options.mechanism);
            }
            event.extra = {
              ...event.extra,
              arguments: args
            };
            return event;
          });
          captureException(ex);
        });
        throw ex;
      } finally {
        GLOBAL_OBJ._sentryWrappedDepth = (GLOBAL_OBJ._sentryWrappedDepth || 0) - 1;
      }
    };
    try {
      for (const property in fn) {
        if (Object.prototype.hasOwnProperty.call(fn, property)) {
          sentryWrapped[property] = fn[property];
        }
      }
    } catch {
    }
    markFunctionWrapped(sentryWrapped, fn);
    addNonEnumerableProperty(fn, "__sentry_wrapped__", sentryWrapped);
    try {
      const descriptor = Object.getOwnPropertyDescriptor(sentryWrapped, "name");
      if (descriptor.configurable) {
        Object.defineProperty(sentryWrapped, "name", {
          get() {
            return fn.name;
          }
        });
      }
    } catch {
    }
    return sentryWrapped;
  }
  function getHttpRequestData() {
    const url = getLocationHref();
    const { referrer } = WINDOW.document || {};
    const { userAgent } = WINDOW.navigator || {};
    const headers = {
      ...referrer && { Referer: referrer },
      ...userAgent && { "User-Agent": userAgent }
    };
    const request = {
      url,
      headers
    };
    return request;
  }

  function exceptionFromError(stackParser, ex) {
    const frames = parseStackFrames(stackParser, ex);
    const exception = {
      type: extractType(ex),
      value: extractMessage(ex)
    };
    if (frames.length) {
      exception.stacktrace = { frames };
    }
    if (exception.type === void 0 && exception.value === "") {
      exception.value = "Unrecoverable error caught";
    }
    return exception;
  }
  function eventFromPlainObject(stackParser, exception, syntheticException, isUnhandledRejection) {
    const client = getClient();
    const normalizeDepth = client?.getOptions().normalizeDepth;
    const errorFromProp = getErrorPropertyFromObject(exception);
    const extra = {
      __serialized__: normalizeToSize(exception, normalizeDepth)
    };
    if (errorFromProp) {
      return {
        exception: {
          values: [exceptionFromError(stackParser, errorFromProp)]
        },
        extra
      };
    }
    const exceptionValue = {
      type: isEvent(exception) ? exception.constructor.name : isUnhandledRejection ? "UnhandledRejection" : "Error",
      value: getNonErrorObjectExceptionValue(exception, { isUnhandledRejection })
    };
    const event = {
      exception: {
        values: [exceptionValue]
      },
      extra
    };
    if (syntheticException) {
      const frames = parseStackFrames(stackParser, syntheticException);
      if (frames.length) {
        event.exception.values[0].stacktrace = { frames };
      }
    }
    return event;
  }
  function eventFromError(stackParser, ex) {
    return {
      exception: {
        values: [exceptionFromError(stackParser, ex)]
      }
    };
  }
  function parseStackFrames(stackParser, ex) {
    const stacktrace = ex.stacktrace || ex.stack || "";
    const skipLines = getSkipFirstStackStringLines(ex);
    const framesToPop = getPopFirstTopFrames(ex);
    try {
      return stackParser(stacktrace, skipLines, framesToPop);
    } catch {
    }
    return [];
  }
  const reactMinifiedRegexp = /Minified React error #\d+;/i;
  function getSkipFirstStackStringLines(ex) {
    if (ex && reactMinifiedRegexp.test(ex.message)) {
      return 1;
    }
    return 0;
  }
  function getPopFirstTopFrames(ex) {
    if (typeof ex.framesToPop === "number") {
      return ex.framesToPop;
    }
    return 0;
  }
  function isWebAssemblyException(exception) {
    if (typeof WebAssembly !== "undefined" && typeof WebAssembly.Exception !== "undefined") {
      return exception instanceof WebAssembly.Exception;
    } else {
      return false;
    }
  }
  function extractType(ex) {
    const name = ex?.name;
    if (!name && isWebAssemblyException(ex)) {
      const hasTypeInMessage = ex.message && Array.isArray(ex.message) && ex.message.length == 2;
      return hasTypeInMessage ? ex.message[0] : "WebAssembly.Exception";
    }
    return name;
  }
  function extractMessage(ex) {
    const message = ex?.message;
    if (isWebAssemblyException(ex)) {
      if (Array.isArray(ex.message) && ex.message.length == 2) {
        return ex.message[1];
      }
      return "wasm exception";
    }
    if (!message) {
      return "No error message";
    }
    if (message.error && typeof message.error.message === "string") {
      return _enhanceErrorWithSentryInfo(message.error);
    }
    return _enhanceErrorWithSentryInfo(ex);
  }
  function eventFromException(stackParser, exception, hint, attachStacktrace) {
    const syntheticException = hint?.syntheticException || void 0;
    const event = eventFromUnknownInput(stackParser, exception, syntheticException, attachStacktrace);
    addExceptionMechanism(event);
    event.level = "error";
    if (hint?.event_id) {
      event.event_id = hint.event_id;
    }
    return resolvedSyncPromise(event);
  }
  function eventFromMessage(stackParser, message, level = "info", hint, attachStacktrace) {
    const syntheticException = hint?.syntheticException || void 0;
    const event = eventFromString(stackParser, message, syntheticException, attachStacktrace);
    event.level = level;
    if (hint?.event_id) {
      event.event_id = hint.event_id;
    }
    return resolvedSyncPromise(event);
  }
  function eventFromUnknownInput(stackParser, exception, syntheticException, attachStacktrace, isUnhandledRejection) {
    let event;
    if (isErrorEvent$1(exception) && exception.error) {
      const errorEvent = exception;
      return eventFromError(stackParser, errorEvent.error);
    }
    if (isDOMError(exception) || isDOMException(exception)) {
      const domException = exception;
      if ("stack" in exception) {
        event = eventFromError(stackParser, exception);
        const firstException = event.exception?.values?.[0];
        if (attachStacktrace && syntheticException && firstException && !firstException.stacktrace) {
          const frames = parseStackFrames(stackParser, syntheticException);
          if (frames.length) {
            firstException.stacktrace = { frames };
            addExceptionMechanism(event, { synthetic: true });
          }
        }
      } else {
        const name = domException.name || (isDOMError(domException) ? "DOMError" : "DOMException");
        const message = domException.message ? `${name}: ${domException.message}` : name;
        event = eventFromString(stackParser, message, syntheticException, attachStacktrace);
        addExceptionTypeValue(event, message);
      }
      return event;
    }
    if (isError(exception)) {
      return eventFromError(stackParser, exception);
    }
    if (isPlainObject(exception) || isEvent(exception)) {
      const objectException = exception;
      event = eventFromPlainObject(stackParser, objectException, syntheticException, isUnhandledRejection);
      addExceptionMechanism(event, {
        synthetic: true
      });
      return event;
    }
    const stringifiedException = String(exception);
    event = eventFromString(stackParser, stringifiedException, syntheticException, attachStacktrace);
    addExceptionTypeValue(event, stringifiedException);
    addExceptionMechanism(event, {
      synthetic: true
    });
    return event;
  }
  function eventFromString(stackParser, message, syntheticException, attachStacktrace) {
    const event = {};
    if (attachStacktrace && syntheticException) {
      const frames = parseStackFrames(stackParser, syntheticException);
      if (frames.length) {
        event.exception = {
          values: [{ value: message, stacktrace: { frames } }]
        };
      }
      addExceptionMechanism(event, { synthetic: true });
    }
    if (isParameterizedString(message)) {
      const { __sentry_template_string__, __sentry_template_values__ } = message;
      event.logentry = {
        message: __sentry_template_string__,
        params: __sentry_template_values__
      };
      return event;
    }
    event.message = message;
    return event;
  }
  function getNonErrorObjectExceptionValue(exception, { isUnhandledRejection }) {
    const keys = extractExceptionKeysForMessage(exception);
    const captureType = isUnhandledRejection ? "promise rejection" : "exception";
    if (isErrorEvent$1(exception)) {
      return `Event \`ErrorEvent\` captured as ${captureType} with message \`${exception.message}\``;
    }
    if (isEvent(exception)) {
      const className = getObjectClassName(exception);
      return `Event \`${className}\` (type=${exception.type}) captured as ${captureType}`;
    }
    return `Object captured as ${captureType} with keys: ${keys}`;
  }
  function getObjectClassName(obj) {
    try {
      const prototype = Object.getPrototypeOf(obj);
      return prototype ? prototype.constructor.name : void 0;
    } catch {
    }
  }
  function getErrorPropertyFromObject(obj) {
    return Object.values(obj).find(isError);
  }

  class BrowserClient extends Client {
    /**
     * Creates a new Browser SDK instance.
     *
     * @param options Configuration options for this SDK.
     */
    constructor(options) {
      const opts = applyDefaultOptions(options);
      const sdkSource = WINDOW.SENTRY_SDK_SOURCE || getSDKSource();
      applySdkMetadata(opts, "browser", ["browser"], sdkSource);
      super(opts);
      this._unhandledSessionStatus = "unhandled";
      const { userInfo } = this.getDataCollectionOptions();
      if (opts._metadata?.sdk) {
        opts._metadata.sdk.settings = {
          // Only allow IP inferral by Relay if the user opted in via dataCollection
          infer_ip: userInfo ? "auto" : "never",
          // purposefully allowing already passed settings to override the default
          ...opts._metadata.sdk.settings
        };
      }
      const { sendClientReports } = this._options;
      if (WINDOW.document) {
        WINDOW.document.addEventListener("visibilitychange", () => {
          if (WINDOW.document.visibilityState === "hidden") {
            if (sendClientReports) {
              this._flushOutcomes();
            }
            queueMicrotask(() => {
              void this.flush();
            });
          }
        });
      }
      if (userInfo) {
        this.on("beforeSendSession", addAutoIpAddressToSession);
      }
    }
    /**
     * @inheritDoc
     */
    eventFromException(exception, hint) {
      return eventFromException(this._options.stackParser, exception, hint, this._options.attachStacktrace);
    }
    /**
     * @inheritDoc
     */
    eventFromMessage(message, level = "info", hint) {
      return eventFromMessage(this._options.stackParser, message, level, hint, this._options.attachStacktrace);
    }
    /**
     * @inheritDoc
     */
    _prepareEvent(event, hint, currentScope, isolationScope) {
      event.platform = event.platform || "javascript";
      return super._prepareEvent(event, hint, currentScope, isolationScope);
    }
  }
  function applyDefaultOptions(optionsArg) {
    return {
      release: typeof __SENTRY_RELEASE__ === "string" ? __SENTRY_RELEASE__ : WINDOW.SENTRY_RELEASE?.id,
      // This supports the variable that sentry-webpack-plugin injects
      sendClientReports: true,
      // We default this to true, as it is the safer scenario
      parentSpanIsAlwaysRootSpan: true,
      ...optionsArg
    };
  }

  const DEFAULT_BROWSER_TRANSPORT_BUFFER_SIZE = 40;
  function makeFetchTransport(options, nativeFetch = getNativeImplementation("fetch")) {
    let pendingBodySize = 0;
    let pendingCount = 0;
    async function makeRequest(request) {
      const requestSize = request.body.length;
      pendingBodySize += requestSize;
      pendingCount++;
      const requestOptions = {
        body: request.body,
        method: "POST",
        referrerPolicy: "strict-origin",
        headers: options.headers,
        // Outgoing requests are usually cancelled when navigating to a different page, causing a "TypeError: Failed to
        // fetch" error and sending a "network_error" client-outcome - in Chrome, the request status shows "(cancelled)".
        // The `keepalive` flag keeps outgoing requests alive, even when switching pages. We want this since we're
        // frequently sending events right before the user is switching pages (eg. when finishing navigation transactions).
        // Gotchas:
        // - `keepalive` isn't supported by Firefox
        // - As per spec (https://fetch.spec.whatwg.org/#http-network-or-cache-fetch):
        //   If the sum of contentLength and inflightKeepaliveBytes is greater than 64 kibibytes, then return a network error.
        //   We will therefore only activate the flag when we're below that limit.
        // There is also a limit of requests that can be open at the same time, so we also limit this to 15
        // See https://github.com/getsentry/sentry-javascript/pull/7553 for details
        keepalive: pendingBodySize <= 6e4 && pendingCount < 15,
        ...options.fetchOptions
      };
      try {
        const response = await nativeFetch(options.url, requestOptions);
        return {
          statusCode: response.status,
          headers: {
            "x-sentry-rate-limits": response.headers.get("X-Sentry-Rate-Limits"),
            "retry-after": response.headers.get("Retry-After")
          }
        };
      } catch (e) {
        clearCachedImplementation("fetch");
        throw e;
      } finally {
        pendingBodySize -= requestSize;
        pendingCount--;
      }
    }
    return createTransport(
      options,
      makeRequest,
      makePromiseBuffer(options.bufferSize || DEFAULT_BROWSER_TRANSPORT_BUFFER_SIZE)
    );
  }

  function startProfiler() {
    const client = getClient();
    if (!client) {
      debug.warn("No Sentry client available, profiling is not started");
      return;
    }
    const integration = client.getIntegrationByName("BrowserProfiling");
    if (!integration) {
      debug.warn("BrowserProfiling integration is not available");
      return;
    }
    client.emit("startUIProfiler");
  }
  function stopProfiler() {
    const client = getClient();
    if (!client) {
      debug.warn("No Sentry client available, profiling is not started");
      return;
    }
    const integration = client.getIntegrationByName("BrowserProfiling");
    if (!integration) {
      debug.warn("ProfilingIntegration is not available");
      return;
    }
    client.emit("stopUIProfiler");
  }
  const uiProfiler = {
    startProfiler,
    stopProfiler
  };

  const OPERA10_PRIORITY = 10;
  const OPERA11_PRIORITY = 20;
  const CHROME_PRIORITY = 30;
  const WINJS_PRIORITY = 40;
  const GECKO_PRIORITY = 50;
  function createFrame(filename, func, lineno, colno) {
    const frame = {
      filename,
      function: func === "<anonymous>" ? UNKNOWN_FUNCTION : func,
      in_app: true
      // All browser frames are considered in_app
    };
    if (lineno !== void 0) {
      frame.lineno = lineno;
    }
    if (colno !== void 0) {
      frame.colno = colno;
    }
    return frame;
  }
  const chromeRegexNoFnName = /^\s*at (\S+?)(?::(\d+))(?::(\d+))\s*$/i;
  const chromeRegex = /^\s*at (?:(.+?\)(?: \[.+\])?|.*?) ?\((?:address at )?)?(?:async )?((?:<anonymous>|[-a-z]+:|.*bundle|\/)?.*?)(?::(\d+))?(?::(\d+))?\)?\s*$/i;
  const chromeEvalRegex = /\((\S*)(?::(\d+))(?::(\d+))\)/;
  const chromeDataUriRegex = /at (.+?) ?\(data:(.+?),/;
  const chromeStackParserFn = (line) => {
    const dataUriMatch = line.match(chromeDataUriRegex);
    if (dataUriMatch) {
      return {
        filename: `<data:${dataUriMatch[2]}>`,
        function: dataUriMatch[1]
      };
    }
    const noFnParts = chromeRegexNoFnName.exec(line);
    if (noFnParts) {
      const [, filename, line2, col] = noFnParts;
      return createFrame(filename, UNKNOWN_FUNCTION, +line2, +col);
    }
    const parts = chromeRegex.exec(line);
    if (parts) {
      const isEval = parts[2]?.indexOf("eval") === 0;
      if (isEval) {
        const subMatch = chromeEvalRegex.exec(parts[2]);
        if (subMatch) {
          parts[2] = subMatch[1];
          parts[3] = subMatch[2];
          parts[4] = subMatch[3];
        }
      }
      const [func, filename] = extractSafariExtensionDetails(parts[1] || UNKNOWN_FUNCTION, parts[2]);
      return createFrame(filename, func, parts[3] ? +parts[3] : void 0, parts[4] ? +parts[4] : void 0);
    }
    return;
  };
  const chromeStackLineParser = [CHROME_PRIORITY, chromeStackParserFn];
  const geckoREgex = /^\s*(.*?)(?:\((.*?)\))?(?:^|@)?((?:[-a-z]+)?:\/.*?|\[native code\]|[^@]*(?:bundle|\d+\.js)|\/[\w\-. /=]+)(?::(\d+))?(?::(\d+))?\s*$/i;
  const geckoEvalRegex = /(\S+) line (\d+)(?: > eval line \d+)* > eval/i;
  const gecko = (line) => {
    const parts = geckoREgex.exec(line);
    if (parts) {
      const isEval = parts[3] && parts[3].indexOf(" > eval") > -1;
      if (isEval) {
        const subMatch = geckoEvalRegex.exec(parts[3]);
        if (subMatch) {
          parts[1] = parts[1] || "eval";
          parts[3] = subMatch[1];
          parts[4] = subMatch[2];
          parts[5] = "";
        }
      }
      let filename = parts[3];
      let func = parts[1] || UNKNOWN_FUNCTION;
      [func, filename] = extractSafariExtensionDetails(func, filename);
      return createFrame(filename, func, parts[4] ? +parts[4] : void 0, parts[5] ? +parts[5] : void 0);
    }
    return;
  };
  const geckoStackLineParser = [GECKO_PRIORITY, gecko];
  const winjsRegex = /^\s*at (?:((?:\[object object\])?.+) )?\(?((?:[-a-z]+):.*?):(\d+)(?::(\d+))?\)?\s*$/i;
  const winjs = (line) => {
    const parts = winjsRegex.exec(line);
    return parts ? createFrame(parts[2], parts[1] || UNKNOWN_FUNCTION, +parts[3], parts[4] ? +parts[4] : void 0) : void 0;
  };
  const winjsStackLineParser = [WINJS_PRIORITY, winjs];
  const opera10Regex = / line (\d+).*script (?:in )?(\S+)(?:: in function (\S+))?$/i;
  const opera10 = (line) => {
    const parts = opera10Regex.exec(line);
    return parts ? createFrame(parts[2], parts[3] || UNKNOWN_FUNCTION, +parts[1]) : void 0;
  };
  const opera10StackLineParser = [OPERA10_PRIORITY, opera10];
  const opera11Regex = / line (\d+), column (\d+)\s*(?:in (?:<anonymous function: ([^>]+)>|([^)]+))\(.*\))? in (.*):\s*$/i;
  const opera11 = (line) => {
    const parts = opera11Regex.exec(line);
    return parts ? createFrame(parts[5], parts[3] || parts[4] || UNKNOWN_FUNCTION, +parts[1], +parts[2]) : void 0;
  };
  const opera11StackLineParser = [OPERA11_PRIORITY, opera11];
  const defaultStackLineParsers = [chromeStackLineParser, geckoStackLineParser];
  const defaultStackParser = createStackParser(...defaultStackLineParsers);
  const extractSafariExtensionDetails = (func, filename) => {
    const isSafariExtension = func.indexOf("safari-extension") !== -1;
    const isSafariWebExtension = func.indexOf("safari-web-extension") !== -1;
    return isSafariExtension || isSafariWebExtension ? [
      func.indexOf("@") !== -1 ? func.split("@")[0] : UNKNOWN_FUNCTION,
      isSafariExtension ? `safari-extension:${filename}` : `safari-web-extension:${filename}`
    ] : [func, filename];
  };

  function createUserFeedbackEnvelope(feedback, {
    metadata,
    tunnel,
    dsn
  }) {
    const headers = {
      event_id: feedback.event_id,
      sent_at: (/* @__PURE__ */ new Date()).toISOString(),
      ...metadata?.sdk && {
        sdk: {
          name: metadata.sdk.name,
          version: metadata.sdk.version
        }
      },
      ...!!tunnel && !!dsn && { dsn: dsnToString(dsn) }
    };
    const item = createUserFeedbackEnvelopeItem(feedback);
    return createEnvelope(headers, [item]);
  }
  function createUserFeedbackEnvelopeItem(feedback) {
    const feedbackHeaders = {
      type: "user_report"
    };
    return [feedbackHeaders, feedback];
  }

  const MAX_ALLOWED_STRING_LENGTH = 1024;
  const INTEGRATION_NAME$4 = "Breadcrumbs";
  const _breadcrumbsIntegration = ((options = {}) => {
    const _options = {
      dom: true,
      fetch: true,
      history: true,
      sentry: true,
      xhr: true,
      ...options
    };
    return {
      name: INTEGRATION_NAME$4,
      setup(client) {
        if (_options.dom) {
          addClickKeypressInstrumentationHandler(_getDomBreadcrumbHandler(client, _options.dom));
        }
        if (_options.xhr) {
          addXhrInstrumentationHandler(_getXhrBreadcrumbHandler(client));
        }
        if (_options.fetch) {
          addFetchInstrumentationHandler(_getFetchBreadcrumbHandler(client));
        }
        if (_options.history) {
          addHistoryInstrumentationHandler(_getHistoryBreadcrumbHandler(client));
        }
        if (_options.sentry) {
          client.on("beforeSendEvent", _getSentryBreadcrumbHandler(client));
        }
      }
    };
  });
  const breadcrumbsIntegration = defineIntegration(_breadcrumbsIntegration);
  function _getSentryBreadcrumbHandler(client) {
    return function addSentryBreadcrumb(event) {
      if (getClient() !== client) {
        return;
      }
      addBreadcrumb(
        {
          category: `sentry.${event.type === "transaction" ? "transaction" : "event"}`,
          event_id: event.event_id,
          level: event.level,
          message: getEventDescription(event)
        },
        {
          event
        }
      );
    };
  }
  function _getDomBreadcrumbHandler(client, dom) {
    return function _innerDomBreadcrumb(handlerData) {
      if (getClient() !== client) {
        return;
      }
      let target;
      let componentName;
      let keyAttrs = typeof dom === "object" ? dom.serializeAttribute : void 0;
      let maxStringLength = typeof dom === "object" && typeof dom.maxStringLength === "number" ? dom.maxStringLength : void 0;
      if (maxStringLength && maxStringLength > MAX_ALLOWED_STRING_LENGTH) {
        debug.warn(
          `\`dom.maxStringLength\` cannot exceed ${MAX_ALLOWED_STRING_LENGTH}, but a value of ${maxStringLength} was configured. Sentry will use ${MAX_ALLOWED_STRING_LENGTH} instead.`
        );
        maxStringLength = MAX_ALLOWED_STRING_LENGTH;
      }
      if (typeof keyAttrs === "string") {
        keyAttrs = [keyAttrs];
      }
      try {
        const event = handlerData.event;
        const element = _isEvent(event) ? event.target : event;
        target = htmlTreeAsString(element, { keyAttrs, maxStringLength });
        componentName = getComponentName(element);
      } catch {
        target = "<unknown>";
      }
      if (target.length === 0) {
        return;
      }
      const breadcrumb = {
        category: `ui.${handlerData.name}`,
        message: target
      };
      if (componentName) {
        breadcrumb.data = { "ui.component_name": componentName };
      }
      addBreadcrumb(breadcrumb, {
        event: handlerData.event,
        name: handlerData.name,
        global: handlerData.global
      });
    };
  }
  function _getXhrBreadcrumbHandler(client) {
    return function _xhrBreadcrumb(handlerData) {
      if (getClient() !== client) {
        return;
      }
      const { startTimestamp, endTimestamp } = handlerData;
      const sentryXhrData = handlerData.xhr[SENTRY_XHR_DATA_KEY];
      if (!startTimestamp || !endTimestamp || !sentryXhrData) {
        return;
      }
      const { method, url, status_code, body } = sentryXhrData;
      const data = {
        method,
        url,
        status_code
      };
      const hint = {
        xhr: handlerData.xhr,
        input: body,
        startTimestamp,
        endTimestamp
      };
      const breadcrumb = {
        category: "xhr",
        data,
        type: "http",
        level: getBreadcrumbLogLevelFromHttpStatusCode(status_code)
      };
      client.emit("beforeOutgoingRequestBreadcrumb", breadcrumb, hint);
      addBreadcrumb(breadcrumb, hint);
    };
  }
  function _getFetchBreadcrumbHandler(client) {
    return function _fetchBreadcrumb(handlerData) {
      if (getClient() !== client) {
        return;
      }
      const { startTimestamp, endTimestamp } = handlerData;
      if (!endTimestamp) {
        return;
      }
      if (handlerData.fetchData.url.match(/sentry_key/) && handlerData.fetchData.method === "POST") {
        return;
      }
      if (handlerData.error) {
        const hint = {
          data: handlerData.error,
          input: handlerData.args,
          startTimestamp,
          endTimestamp
        };
        const breadcrumb = {
          category: "fetch",
          data: handlerData.fetchData,
          level: "error",
          type: "http"
        };
        client.emit("beforeOutgoingRequestBreadcrumb", breadcrumb, hint);
        addBreadcrumb(breadcrumb, hint);
      } else {
        const response = handlerData.response;
        const data = {
          ...handlerData.fetchData,
          status_code: response?.status
        };
        const hint = {
          input: handlerData.args,
          response,
          startTimestamp,
          endTimestamp
        };
        const breadcrumb = {
          category: "fetch",
          data,
          type: "http",
          level: getBreadcrumbLogLevelFromHttpStatusCode(data.status_code)
        };
        client.emit("beforeOutgoingRequestBreadcrumb", breadcrumb, hint);
        addBreadcrumb(breadcrumb, hint);
      }
    };
  }
  function _getHistoryBreadcrumbHandler(client) {
    return function _historyBreadcrumb(handlerData) {
      if (getClient() !== client) {
        return;
      }
      let from = handlerData.from;
      let to = handlerData.to;
      const parsedLoc = parseUrl(WINDOW.location.href);
      let parsedFrom = from ? parseUrl(from) : void 0;
      const parsedTo = parseUrl(to);
      if (!parsedFrom?.path) {
        parsedFrom = parsedLoc;
      }
      if (parsedLoc.protocol === parsedTo.protocol && parsedLoc.host === parsedTo.host) {
        to = parsedTo.relative;
      }
      if (parsedLoc.protocol === parsedFrom.protocol && parsedLoc.host === parsedFrom.host) {
        from = parsedFrom.relative;
      }
      addBreadcrumb({
        category: "navigation",
        data: {
          from,
          to
        }
      });
    };
  }
  function _isEvent(event) {
    return !!event && !!event.target;
  }

  const DEFAULT_EVENT_TARGET = "EventTarget,Window,Node,ApplicationCache,AudioTrackList,BroadcastChannel,ChannelMergerNode,CryptoOperation,EventSource,FileReader,HTMLUnknownElement,IDBDatabase,IDBRequest,IDBTransaction,KeyOperation,MediaController,MessagePort,ModalWindow,Notification,SVGElementInstance,Screen,SharedWorker,TextTrack,TextTrackCue,TextTrackList,WebSocket,WebSocketWorker,Worker,XMLHttpRequest,XMLHttpRequestEventTarget,XMLHttpRequestUpload".split(
    ","
  );
  const INTEGRATION_NAME$3 = "BrowserApiErrors";
  const _browserApiErrorsIntegration = ((options = {}) => {
    const _options = {
      XMLHttpRequest: true,
      eventTarget: true,
      requestAnimationFrame: true,
      setInterval: true,
      setTimeout: true,
      unregisterOriginalCallbacks: false,
      ...options
    };
    return {
      name: INTEGRATION_NAME$3,
      // TODO: This currently only works for the first client this is setup
      // We may want to adjust this to check for client etc.
      setupOnce() {
        if (_options.setTimeout) {
          fill(WINDOW, "setTimeout", _wrapTimeFunction);
        }
        if (_options.setInterval) {
          fill(WINDOW, "setInterval", _wrapTimeFunction);
        }
        if (_options.requestAnimationFrame) {
          fill(WINDOW, "requestAnimationFrame", _wrapRAF);
        }
        if (_options.XMLHttpRequest && "XMLHttpRequest" in WINDOW) {
          fill(XMLHttpRequest.prototype, "send", _wrapXHR);
        }
        const eventTargetOption = _options.eventTarget;
        if (eventTargetOption) {
          const eventTarget = Array.isArray(eventTargetOption) ? eventTargetOption : DEFAULT_EVENT_TARGET;
          eventTarget.forEach((target) => _wrapEventTarget(target, _options));
        }
      }
    };
  });
  const browserApiErrorsIntegration = defineIntegration(_browserApiErrorsIntegration);
  function _wrapTimeFunction(original) {
    return function(...args) {
      const originalCallback = args[0];
      args[0] = wrap(originalCallback, {
        mechanism: {
          handled: false,
          type: `auto.browser.browserapierrors.${getFunctionName(original)}`
        }
      });
      return original.apply(this, args);
    };
  }
  function _wrapRAF(original) {
    return function(callback) {
      return original.apply(this, [
        wrap(callback, {
          mechanism: {
            data: {
              handler: getFunctionName(original)
            },
            handled: false,
            type: "auto.browser.browserapierrors.requestAnimationFrame"
          }
        })
      ]);
    };
  }
  function _wrapXHR(originalSend) {
    return function(...args) {
      const xhr = this;
      const xmlHttpRequestProps = ["onload", "onerror", "onprogress", "onreadystatechange"];
      xmlHttpRequestProps.forEach((prop) => {
        if (prop in xhr && typeof xhr[prop] === "function") {
          fill(xhr, prop, function(original) {
            const wrapOptions = {
              mechanism: {
                data: {
                  handler: getFunctionName(original)
                },
                handled: false,
                type: `auto.browser.browserapierrors.xhr.${prop}`
              }
            };
            const originalFunction = getOriginalFunction(original);
            if (originalFunction) {
              wrapOptions.mechanism.data.handler = getFunctionName(originalFunction);
            }
            return wrap(original, wrapOptions);
          });
        }
      });
      return originalSend.apply(this, args);
    };
  }
  function _wrapEventTarget(target, integrationOptions) {
    const globalObject = WINDOW;
    const proto = globalObject[target]?.prototype;
    if (!proto?.hasOwnProperty?.("addEventListener")) {
      return;
    }
    fill(proto, "addEventListener", function(original) {
      return function(eventName, fn, options) {
        try {
          if (isEventListenerObject(fn)) {
            fn.handleEvent = wrap(fn.handleEvent, {
              mechanism: {
                data: {
                  handler: getFunctionName(fn),
                  target
                },
                handled: false,
                type: "auto.browser.browserapierrors.handleEvent"
              }
            });
          }
        } catch {
        }
        if (integrationOptions.unregisterOriginalCallbacks) {
          unregisterOriginalCallback(this, eventName, fn);
        }
        return original.apply(this, [
          eventName,
          wrap(fn, {
            mechanism: {
              data: {
                handler: getFunctionName(fn),
                target
              },
              handled: false,
              type: "auto.browser.browserapierrors.addEventListener"
            }
          }),
          options
        ]);
      };
    });
    fill(proto, "removeEventListener", function(originalRemoveEventListener) {
      return function(eventName, fn, options) {
        try {
          if (Object.prototype.hasOwnProperty.call(fn, "__sentry_wrapped__")) {
            const originalEventHandler = fn.__sentry_wrapped__;
            if (originalEventHandler) {
              originalRemoveEventListener.call(this, eventName, originalEventHandler, options);
            }
          }
        } catch {
        }
        return originalRemoveEventListener.call(this, eventName, fn, options);
      };
    });
  }
  function isEventListenerObject(obj) {
    return typeof obj.handleEvent === "function";
  }
  function unregisterOriginalCallback(target, eventName, fn) {
    if (target && typeof target === "object" && "removeEventListener" in target && typeof target.removeEventListener === "function") {
      target.removeEventListener(eventName, fn);
    }
  }

  const browserSessionIntegration = defineIntegration((options = {}) => {
    const lifecycle = options.lifecycle ?? "page";
    return {
      name: "BrowserSession",
      setupOnce() {
        if (typeof WINDOW.document === "undefined") {
          debug.warn("Using the `browserSessionIntegration` in non-browser environments is not supported.");
          return;
        }
        startSession({ ignoreDuration: true });
        let initialSessionSent = false;
        whenIdleOrHidden(() => {
          if (!initialSessionSent) {
            captureSession();
            initialSessionSent = true;
          }
        });
        const isolationScope = getIsolationScope();
        let previousUser = isolationScope.getUser();
        isolationScope.addScopeListener((scope) => {
          const maybeNewUser = scope.getUser();
          if (previousUser?.id !== maybeNewUser?.id || previousUser?.ip_address !== maybeNewUser?.ip_address) {
            previousUser = maybeNewUser;
            if (initialSessionSent) {
              captureSession();
            }
          }
        });
        if (lifecycle === "route") {
          addHistoryInstrumentationHandler(({ from, to }) => {
            if (from !== to) {
              startSession({ ignoreDuration: true });
              captureSession();
              initialSessionSent = true;
            }
          });
        }
      }
    };
  });

  const INTEGRATION_NAME$2 = "CultureContext";
  const _cultureContextIntegration = (() => {
    return {
      name: INTEGRATION_NAME$2,
      preprocessEvent(event) {
        const culture = getCultureContext();
        if (culture) {
          event.contexts = {
            ...event.contexts,
            culture: { ...culture, ...event.contexts?.culture }
          };
        }
      },
      processSegmentSpan(span) {
        const culture = getCultureContext();
        if (culture) {
          safeSetSpanJSONAttributes(span, {
            "culture.locale": culture.locale,
            "culture.timezone": culture.timezone,
            "culture.calendar": culture.calendar
          });
        }
      }
    };
  });
  const cultureContextIntegration = defineIntegration(_cultureContextIntegration);
  function getCultureContext() {
    try {
      const intl = WINDOW.Intl;
      if (!intl) {
        return void 0;
      }
      const options = intl.DateTimeFormat().resolvedOptions();
      return {
        locale: options.locale,
        timezone: options.timeZone,
        calendar: options.calendar
      };
    } catch {
      return void 0;
    }
  }

  const INTEGRATION_NAME$1 = "GlobalHandlers";
  const _globalHandlersIntegration = ((options = {}) => {
    const _options = {
      onerror: true,
      onunhandledrejection: true,
      ...options
    };
    return {
      name: INTEGRATION_NAME$1,
      setupOnce() {
        Error.stackTraceLimit = 50;
      },
      setup(client) {
        if (_options.onerror) {
          _installGlobalOnErrorHandler(client);
          globalHandlerLog("onerror");
        }
        if (_options.onunhandledrejection) {
          _installGlobalOnUnhandledRejectionHandler(client);
          globalHandlerLog("onunhandledrejection");
        }
      }
    };
  });
  const globalHandlersIntegration = defineIntegration(_globalHandlersIntegration);
  function _installGlobalOnErrorHandler(client) {
    addGlobalErrorInstrumentationHandler((data) => {
      const { stackParser, attachStacktrace } = getOptions();
      if (getClient() !== client || shouldIgnoreOnError(data)) {
        return;
      }
      const { msg, url, line, column, error } = data;
      const event = _enhanceEventWithInitialFrame(
        eventFromUnknownInput(stackParser, error || msg, void 0, attachStacktrace, false),
        url,
        line,
        column
      );
      event.level = "error";
      captureEvent(event, {
        originalException: error,
        mechanism: {
          handled: false,
          type: "auto.browser.global_handlers.onerror"
        }
      });
    });
  }
  function _installGlobalOnUnhandledRejectionHandler(client) {
    addGlobalUnhandledRejectionInstrumentationHandler((e) => {
      const { stackParser, attachStacktrace } = getOptions();
      if (getClient() !== client || shouldIgnoreOnError()) {
        return;
      }
      const error = _getUnhandledRejectionError(e);
      const event = isPrimitive(error) ? _eventFromRejectionWithPrimitive(error) : eventFromUnknownInput(stackParser, error, void 0, attachStacktrace, true);
      event.level = "error";
      captureEvent(event, {
        originalException: error,
        mechanism: {
          handled: false,
          type: "auto.browser.global_handlers.onunhandledrejection"
        }
      });
    });
  }
  function _getUnhandledRejectionError(error) {
    if (isPrimitive(error)) {
      return error;
    }
    try {
      if ("reason" in error) {
        return error.reason;
      }
      if ("detail" in error && "reason" in error.detail) {
        return error.detail.reason;
      }
    } catch {
    }
    return error;
  }
  function _eventFromRejectionWithPrimitive(reason) {
    return {
      exception: {
        values: [
          {
            type: "UnhandledRejection",
            // String() is needed because the Primitive type includes symbols (which can't be automatically stringified)
            value: `Non-Error promise rejection captured with value: ${String(reason)}`
          }
        ]
      }
    };
  }
  function _enhanceEventWithInitialFrame(event, url, lineno, colno) {
    const e = event.exception = event.exception || {};
    const ev = e.values = e.values || [];
    const ev0 = ev[0] = ev[0] || {};
    const ev0s = ev0.stacktrace = ev0.stacktrace || {};
    const ev0sf = ev0s.frames = ev0s.frames || [];
    if (ev0sf.length === 0) {
      ev0sf.push({
        colno,
        lineno,
        filename: getFilenameFromUrl(url) ?? getLocationHref(),
        function: UNKNOWN_FUNCTION,
        in_app: true
      });
    }
    return event;
  }
  function globalHandlerLog(type) {
    debug.log(`Global Handler attached: ${type}`);
  }
  function getOptions() {
    const client = getClient();
    const options = client?.getOptions() || {
      stackParser: () => [],
      attachStacktrace: false
    };
    return options;
  }
  function getFilenameFromUrl(url) {
    if (!isString(url) || url.length === 0) {
      return void 0;
    }
    if (url.startsWith("data:")) {
      return `<${stripDataUrlContent(url, false)}>`;
    }
    return url;
  }

  const httpContextIntegration = defineIntegration(() => {
    return {
      name: "HttpContext",
      preprocessEvent(event, _hint, client) {
        if (!WINDOW.navigator && !WINDOW.location && !WINDOW.document) {
          return;
        }
        const { url, headers: collectedHeaders } = getHttpRequestData();
        const behavior = client.getDataCollectionOptions().httpHeaders.request;
        const userHeaders = Object.entries(event.request?.headers ?? {}).filter(([key]) => !(key in collectedHeaders));
        const headers = {
          ...filterKeyValueData(collectedHeaders, behavior),
          ...Object.fromEntries(userHeaders)
        };
        event.request = {
          // The URL isn't gated by `dataCollection`, same as on the server.
          url,
          ...event.request,
          ...Object.keys(headers).length > 0 ? { headers } : { headers: void 0 }
        };
      },
      processSpan(span, client) {
        if (!WINDOW.navigator && !WINDOW.location && !WINDOW.document) {
          return;
        }
        const reqData = getHttpRequestData();
        const headers = filterKeyValueData(
          reqData.headers,
          client.getDataCollectionOptions().httpHeaders.request
        );
        const referer = headers["Referer"];
        const { hostname, protocol } = WINDOW.location || {};
        safeSetSpanJSONAttributes(span, {
          // This attribute is used by the "Filter out events from legacy browsers and crawlers" features on the Sentry backend.
          // Therefore, it's set on every span.
          [Jg]: headers["User-Agent"],
          // Likewise for the "Filter out localhost events" feature. Deliberately inlined rather than
          // sharing the server-side helper, which costs bundle size for request headers and IPs that
          // don't exist here. Mirrors Relay's localhost filter (relay-filter/src/localhost.rs).
          "sentry.is_localhost": protocol === "file:" || hostname === "localhost" || hostname === "127.0.0.1" || // `location.hostname` keeps the brackets for IPv6 hosts, so this is `[::1]`, not `::1`.
          hostname === "[::1]" || !!hostname?.endsWith(".localhost"),
          // These attributes, we only need on the segment span (analogous to the `request` context for events)
          ...span.is_segment && {
            // Coerce empty string to undefined so the helper's nullish check drops it,
            // rather than writing an empty `url.full` attribute onto the span.
            [zg]: span.attributes?.[cd] !== "http.client" ? filterCollectedUrl(reqData.url) : void 0,
            [`${go}.referer`]: referer ? [referer] : void 0
          }
        });
      }
    };
  });

  const DEFAULT_KEY = "cause";
  const DEFAULT_LIMIT = 5;
  const INTEGRATION_NAME = "LinkedErrors";
  const _linkedErrorsIntegration = ((options = {}) => {
    const limit = options.limit || DEFAULT_LIMIT;
    const key = options.key || DEFAULT_KEY;
    return {
      name: INTEGRATION_NAME,
      preprocessEvent(event, hint, client) {
        const options2 = client.getOptions();
        applyAggregateErrorsToEvent(
          // This differs from the LinkedErrors integration in core by using a different exceptionFromError function
          exceptionFromError,
          options2.stackParser,
          key,
          limit,
          event,
          hint
        );
      }
    };
  });
  const linkedErrorsIntegration = defineIntegration(_linkedErrorsIntegration);

  const HTML_ELEMENT_CONSTRUCTOR_NAME_REGEX = /^HTML(\w*)Element$/;
  function normalizeStringifyValue(value) {
    if (typeof window !== "undefined" && value === window) {
      return "[Window]";
    }
    if (typeof document !== "undefined" && value === document) {
      return "[Document]";
    }
    if (isElement(value)) {
      const objName = getConstructorName(value);
      if (HTML_ELEMENT_CONSTRUCTOR_NAME_REGEX.test(objName)) {
        return `[HTMLElement: ${htmlTreeAsString(value)}]`;
      }
    }
    return void 0;
  }
  function getConstructorName(value) {
    const prototype = Object.getPrototypeOf(value);
    return prototype?.constructor ? prototype.constructor.name : "null prototype";
  }

  function checkAndWarnIfIsEmbeddedBrowserExtension() {
    if (_isEmbeddedBrowserExtension()) {
      {
        consoleSandbox(() => {
          console.error(
            "[Sentry] You cannot use Sentry.init() in a browser extension, see: https://docs.sentry.io/platforms/javascript/best-practices/browser-extensions/"
          );
        });
      }
      return true;
    }
    return false;
  }
  function _isEmbeddedBrowserExtension() {
    if (typeof WINDOW.window === "undefined") {
      return false;
    }
    const _window = WINDOW;
    if (_window.nw) {
      return false;
    }
    const extensionObject = _window["chrome"] || _window["browser"];
    if (!extensionObject?.runtime?.id) {
      return false;
    }
    const href = getLocationHref();
    const isDedicatedExtensionPage = WINDOW === WINDOW.top && /^(?:chrome-extension|moz-extension|ms-browser-extension|safari-web-extension):\/\//.test(href);
    return !isDedicatedExtensionPage;
  }

  function getDefaultIntegrations(_options) {
    return [
      eventFiltersIntegration(),
      functionToStringIntegration(),
      conversationIdIntegration(),
      browserApiErrorsIntegration(),
      breadcrumbsIntegration(),
      consoleIntegration(),
      globalHandlersIntegration(),
      linkedErrorsIntegration(),
      dedupeIntegration(),
      httpContextIntegration(),
      cultureContextIntegration(),
      browserSessionIntegration()
    ];
  }
  function init(options = {}) {
    const shouldDisableBecauseIsBrowserExtenstion = !options.skipBrowserExtensionCheck && checkAndWarnIfIsEmbeddedBrowserExtension();
    let defaultIntegrations = options.defaultIntegrations == null ? getDefaultIntegrations() : options.defaultIntegrations;
    const integrations = getIntegrationsToSetup({
      integrations: options.integrations,
      defaultIntegrations
    });
    const clientOptions = {
      ...options,
      enabled: shouldDisableBecauseIsBrowserExtenstion ? false : options.enabled,
      stackParser: stackParserFromStackParserOptions(options.stackParser || defaultStackParser),
      integrations,
      transport: options.transport || makeFetchTransport
    };
    setNormalizeStringifier(normalizeStringifyValue);
    return initAndBind(BrowserClient, clientOptions);
  }
  function forceLoad() {
  }
  function onLoad(callback) {
    callback();
  }

  function showReportDialog(options = {}) {
    const optionalDocument = WINDOW.document;
    const injectionPoint = optionalDocument?.head || optionalDocument?.body;
    if (!injectionPoint) {
      debug.error("[showReportDialog] Global document not defined");
      return;
    }
    const scope = getCurrentScope();
    const client = getClient();
    const dsn = client?.getDsn();
    if (!dsn) {
      debug.error("[showReportDialog] DSN not configured");
      return;
    }
    const mergedOptions = {
      ...options,
      user: {
        ...scope.getUser(),
        ...options.user
      },
      eventId: options.eventId || lastEventId()
    };
    const script = WINDOW.document.createElement("script");
    script.async = true;
    script.crossOrigin = "anonymous";
    script.src = getReportDialogEndpoint(dsn, mergedOptions);
    const { onLoad, onClose } = mergedOptions;
    if (onLoad) {
      script.onload = onLoad;
    }
    if (onClose) {
      const reportDialogClosedMessageHandler = (event) => {
        if (event.data === "__sentry_reportdialog_closed__") {
          try {
            onClose();
          } finally {
            WINDOW.removeEventListener("message", reportDialogClosedMessageHandler);
          }
        }
      };
      WINDOW.addEventListener("message", reportDialogClosedMessageHandler);
    }
    injectionPoint.appendChild(script);
  }

  const LAZY_LOADABLE_NAMES = [
    "replayIntegration",
    "replayCanvasIntegration",
    "feedbackIntegration",
    "feedbackModalIntegration",
    "feedbackScreenshotIntegration",
    "captureConsoleIntegration",
    "contextLinesIntegration",
    "linkedErrorsIntegration",
    "dedupeIntegration",
    "extraErrorDataIntegration",
    "graphqlClientIntegration",
    "httpClientIntegration",
    "reportingObserverIntegration",
    "rewriteFramesIntegration",
    "browserProfilingIntegration",
    "userTimingIntegration",
    "interactionsIntegration",
    "moduleMetadataIntegration"
  ];
  const HYPHENATED_BUNDLES = {
    replayCanvasIntegration: "replay-canvas",
    feedbackModalIntegration: "feedback-modal",
    feedbackScreenshotIntegration: "feedback-screenshot"
  };
  function getBundleName(name) {
    return HYPHENATED_BUNDLES[name] || name.replace("Integration", "").toLowerCase();
  }
  const WindowWithMaybeIntegration = WINDOW;
  async function lazyLoadIntegration(name, scriptNonce) {
    const bundle = LAZY_LOADABLE_NAMES.includes(name) ? getBundleName(name) : void 0;
    const sentryOnWindow = WindowWithMaybeIntegration.Sentry = WindowWithMaybeIntegration.Sentry || {};
    if (!bundle) {
      throw new Error(`Cannot lazy load integration: ${name}`);
    }
    const existing = sentryOnWindow[name];
    if (typeof existing === "function" && !("_isShim" in existing)) {
      return existing;
    }
    const url = getScriptURL(bundle);
    const script = WINDOW.document.createElement("script");
    script.src = url;
    script.crossOrigin = "anonymous";
    script.referrerPolicy = "strict-origin";
    if (scriptNonce) {
      script.setAttribute("nonce", scriptNonce);
    }
    const waitForLoad = new Promise((resolve, reject) => {
      script.addEventListener("load", () => resolve());
      script.addEventListener("error", reject);
    });
    const currentScript = WINDOW.document.currentScript;
    const parent = WINDOW.document.body || WINDOW.document.head || currentScript?.parentElement;
    if (parent) {
      parent.appendChild(script);
    } else {
      throw new Error(`Could not find parent element to insert lazy-loaded ${name} script`);
    }
    try {
      await waitForLoad;
    } catch {
      throw new Error(`Error when loading integration: ${name}`);
    }
    const integrationFn = sentryOnWindow[name];
    if (typeof integrationFn !== "function") {
      throw new Error(`Could not load integration: ${name}`);
    }
    return integrationFn;
  }
  function getScriptURL(bundle) {
    const client = getClient();
    const baseURL = client?.getOptions()?.cdnBaseUrl || "https://browser.sentry-cdn.com";
    return new URL(`/${SDK_VERSION}/${bundle}.min.js`, baseURL).toString();
  }

  const WEB_VITALS_INTEGRATION_NAME = "WebVitals";
  const webVitalsIntegration = defineIntegration((options = {}) => {
    const { ignore = [], softNavigations = true, bfcacheNavigations = true } = options;
    const ignored = new Set(ignore);
    return {
      name: WEB_VITALS_INTEGRATION_NAME,
      setup(client) {
        const spanStreamingEnabled = hasSpanStreamingEnabled(client);
        const reportSoftNavs = softNavigations && spanStreamingEnabled && supportsSoftNavigations();
        const reportBfcache = bfcacheNavigations && spanStreamingEnabled;
        const perNavigation = reportSoftNavs || reportBfcache;
        if (reportSoftNavs) {
          enableSoftNavigationReporting();
          startSoftNavigationCorrelation(client);
        }
        if (reportBfcache) {
          enableBfcacheReporting();
        }
        const trackClsOnPageloadSpan = !spanStreamingEnabled && !ignored.has("cls");
        const trackLcpOnPageloadSpan = !spanStreamingEnabled && !ignored.has("lcp");
        const finalizeWebVitals = startTrackingWebVitals({
          trackCls: trackClsOnPageloadSpan,
          trackLcp: trackLcpOnPageloadSpan});
        const pageloadSpans = /* @__PURE__ */ new WeakSet();
        client.on("afterStartPageLoadSpan", (span) => {
          pageloadSpans.add(span);
        });
        client.on("spanEnd", (span) => {
          if (!pageloadSpans.delete(span)) {
            return;
          }
          finalizeWebVitals();
          addWebVitalsToSpan(span, {
            recordClsOnPageloadSpan: trackClsOnPageloadSpan,
            recordLcpOnPageloadSpan: trackLcpOnPageloadSpan,
            spanStreamingEnabled
          });
        });
        if (spanStreamingEnabled) {
          if (!ignored.has("lcp")) {
            trackLcpAsSpan(client, perNavigation);
          }
          if (!ignored.has("cls")) {
            trackClsAsSpan(client, perNavigation);
          }
        }
        if (!ignored.has("inp")) {
          trackInpAsSpan(client, perNavigation);
        }
      },
      afterAllSetup() {
        if (!ignored.has("inp")) {
          registerInpInteractionListener();
        }
      }
    };
  });

  function registerBackgroundTabDetection() {
    if (WINDOW.document) {
      WINDOW.document.addEventListener("visibilitychange", () => {
        const activeSpan = getActiveSpan();
        if (!activeSpan) {
          return;
        }
        const rootSpan = getRootSpan(activeSpan);
        if (WINDOW.document.hidden && rootSpan) {
          const cancelledStatus = "cancelled";
          const {
            attributes: { [cd]: op },
            status
          } = spanToJSON(rootSpan);
          {
            debug.log(`[Tracing] Transaction: ${cancelledStatus} -> since tab moved to the background, op: ${op}`);
          }
          if (status === "ok") {
            rootSpan.setStatus({ code: SPAN_STATUS_ERROR, message: cancelledStatus });
          }
          rootSpan.setAttribute("sentry.cancellation_reason", "document.hidden");
          rootSpan.end();
        }
      });
    } else {
      debug.warn("[Tracing] Could not set up background tab detection due to lack of global document");
    }
  }

  const PREVIOUS_TRACE_MAX_DURATION = 3600;
  const PREVIOUS_TRACE_KEY = "sentry_previous_trace";
  const PREVIOUS_TRACE_TMP_SPAN_ATTRIBUTE = "sentry.previous_trace";
  function linkTraces(client, {
    linkPreviousTrace,
    consistentTraceSampling
  }) {
    const useSessionStorage = linkPreviousTrace === "session-storage";
    let inMemoryPreviousTraceInfo = useSessionStorage ? getPreviousTraceFromSessionStorage() : void 0;
    client.on("spanStart", (span) => {
      if (getRootSpan(span) !== span) {
        return;
      }
      const oldPropagationContext = getCurrentScope().getPropagationContext();
      inMemoryPreviousTraceInfo = addPreviousTraceSpanLink(inMemoryPreviousTraceInfo, span, oldPropagationContext);
      if (useSessionStorage) {
        storePreviousTraceInSessionStorage(inMemoryPreviousTraceInfo);
      }
    });
    let isFirstTraceOnPageload = true;
    if (consistentTraceSampling) {
      client.on("beforeSampling", (mutableSamplingContextData) => {
        if (!inMemoryPreviousTraceInfo) {
          return;
        }
        const scope = getCurrentScope();
        const currentPropagationContext = scope.getPropagationContext();
        if (isFirstTraceOnPageload && currentPropagationContext.parentSpanId) {
          isFirstTraceOnPageload = false;
          return;
        }
        scope.setPropagationContext({
          ...currentPropagationContext,
          dsc: {
            ...currentPropagationContext.dsc,
            sample_rate: String(inMemoryPreviousTraceInfo.sampleRate),
            sampled: String(spanContextSampled(inMemoryPreviousTraceInfo.spanContext))
          },
          sampleRand: inMemoryPreviousTraceInfo.sampleRand
        });
        mutableSamplingContextData.parentSampled = spanContextSampled(inMemoryPreviousTraceInfo.spanContext);
        mutableSamplingContextData.parentSampleRate = inMemoryPreviousTraceInfo.sampleRate;
        mutableSamplingContextData.spanAttributes = {
          ...mutableSamplingContextData.spanAttributes,
          [SEMANTIC_ATTRIBUTE_SENTRY_PREVIOUS_TRACE_SAMPLE_RATE]: inMemoryPreviousTraceInfo.sampleRate
        };
      });
    }
  }
  function addPreviousTraceSpanLink(previousTraceInfo, span, oldPropagationContext) {
    const spanJson = spanToJSON(span);
    function getSampleRate() {
      try {
        const oldSampleRate = Number(
          spanJson.attributes[SEMANTIC_ATTRIBUTE_SENTRY_SAMPLE_RATE] ?? oldPropagationContext.dsc?.sample_rate
        );
        return Number.isNaN(oldSampleRate) ? 0 : oldSampleRate;
      } catch {
        return 0;
      }
    }
    const updatedPreviousTraceInfo = {
      spanContext: span.spanContext(),
      startTimestamp: spanJson.start_timestamp,
      sampleRate: getSampleRate(),
      sampleRand: oldPropagationContext.sampleRand
    };
    if (!previousTraceInfo) {
      return updatedPreviousTraceInfo;
    }
    const previousTraceSpanCtx = previousTraceInfo.spanContext;
    if (previousTraceSpanCtx.traceId === spanJson.trace_id) {
      return previousTraceInfo;
    }
    if (Date.now() / 1e3 - previousTraceInfo.startTimestamp <= PREVIOUS_TRACE_MAX_DURATION) {
      {
        debug.log(
          `Adding previous_trace \`${JSON.stringify(previousTraceSpanCtx)}\` link to span \`${JSON.stringify({
          op: spanJson.attributes[cd],
          ...span.spanContext()
        })}\``
        );
      }
      span.addLink({
        context: previousTraceSpanCtx,
        attributes: {
          [SEMANTIC_LINK_ATTRIBUTE_LINK_TYPE]: "previous_trace"
        }
      });
      span.setAttribute(
        PREVIOUS_TRACE_TMP_SPAN_ATTRIBUTE,
        `${previousTraceSpanCtx.traceId}-${previousTraceSpanCtx.spanId}-${spanContextSampled(previousTraceSpanCtx) ? 1 : 0}`
      );
    }
    return updatedPreviousTraceInfo;
  }
  function storePreviousTraceInSessionStorage(previousTraceInfo) {
    try {
      WINDOW.sessionStorage.setItem(PREVIOUS_TRACE_KEY, JSON.stringify(previousTraceInfo));
    } catch (e) {
      debug.warn("Could not store previous trace in sessionStorage", e);
    }
  }
  function getPreviousTraceFromSessionStorage() {
    try {
      const previousTraceInfo = WINDOW.sessionStorage?.getItem(PREVIOUS_TRACE_KEY);
      return JSON.parse(previousTraceInfo);
    } catch {
      return void 0;
    }
  }
  function spanContextSampled(ctx) {
    return ctx.traceFlags === 1;
  }

  function baggageHeaderHasSentryValues(baggageHeader) {
    return baggageHeader.split(",").some((value) => value.trim().startsWith("sentry-"));
  }
  function getFullURL(url) {
    try {
      const parsed = new URL(url, WINDOW.location.origin);
      return parsed.href;
    } catch {
      return void 0;
    }
  }
  function isPerformanceResourceTiming(entry) {
    return entry.entryType === "resource" && "initiatorType" in entry && typeof entry.nextHopProtocol === "string" && (entry.initiatorType === "fetch" || entry.initiatorType === "xmlhttprequest");
  }
  function createHeadersSafely(headers) {
    try {
      return new Headers(headers);
    } catch {
      return void 0;
    }
  }

  const defaultRequestInstrumentationOptions = {
    traceFetch: true,
    traceXHR: true,
    enableHTTPTimings: true
  };
  function instrumentOutgoingRequests(client, _options) {
    const {
      traceFetch,
      traceXHR,
      shouldCreateSpanForRequest,
      enableHTTPTimings,
      tracePropagationTargets,
      onRequestSpanStart,
      onRequestSpanEnd
    } = {
      ...defaultRequestInstrumentationOptions,
      ..._options
    };
    const shouldCreateSpan = typeof shouldCreateSpanForRequest === "function" ? shouldCreateSpanForRequest : (_) => true;
    const shouldAttachHeadersWithTargets = (url) => shouldAttachHeaders(url, tracePropagationTargets);
    const spans = {};
    const propagateTraceparent = client.getOptions().propagateTraceparent;
    if (traceFetch) {
      addFetchInstrumentationHandler((handlerData) => {
        const createdSpan = instrumentFetchRequest(handlerData, shouldCreateSpan, shouldAttachHeadersWithTargets, spans, {
          propagateTraceparent,
          onRequestSpanEnd,
          // The generic fetch instrumentation has no page origin to resolve relative URLs against.
          urlBase: WINDOW.location?.origin
        });
        if (createdSpan) {
          const fullUrl = getFullURL(handlerData.fetchData.url);
          const host = fullUrl ? parseUrl(fullUrl).host?.replace(/^.*@/, "") : void 0;
          const sanitizedFullUrl = fullUrl ? stripDataUrlContent(fullUrl) : void 0;
          createdSpan.setAttributes({
            [zg]: filterCollectedUrl(sanitizedFullUrl),
            [Zd]: host
          });
          if (enableHTTPTimings) {
            addHTTPTimings(createdSpan, client);
          }
          onRequestSpanStart?.(createdSpan, { headers: handlerData.headers });
        }
      });
    }
    if (traceXHR) {
      addXhrInstrumentationHandler((handlerData) => {
        const createdSpan = xhrCallback(
          handlerData,
          shouldCreateSpan,
          shouldAttachHeadersWithTargets,
          spans,
          propagateTraceparent,
          onRequestSpanEnd
        );
        if (createdSpan) {
          if (enableHTTPTimings) {
            addHTTPTimings(createdSpan, client);
          }
          onRequestSpanStart?.(createdSpan, {
            headers: createHeadersSafely(handlerData.xhr.__sentry_xhr_v3__?.request_headers)
          });
        }
      });
    }
  }
  const HTTP_TIMING_WAIT_MS = 300;
  function addHTTPTimings(span, client) {
    const url = spanToJSON(span).attributes[zg];
    if (!url || typeof url !== "string") {
      return;
    }
    let onEntryFound = () => void setTimeout(unsubscribePerformanceObsever);
    if (hasSpanStreamingEnabled(client)) {
      const originalEnd = span.end.bind(span);
      span.end = (endTimestamp) => {
        const capturedEndTimestamp = endTimestamp ?? timestampInSeconds();
        let isEnded = false;
        const endSpanAndCleanup = () => {
          if (isEnded) {
            return;
          }
          isEnded = true;
          setTimeout(unsubscribePerformanceObsever);
          originalEnd(capturedEndTimestamp);
          clearTimeout(fallbackTimeout);
        };
        onEntryFound = endSpanAndCleanup;
        const fallbackTimeout = setTimeout(endSpanAndCleanup, HTTP_TIMING_WAIT_MS);
      };
    }
    const unsubscribePerformanceObsever = addPerformanceInstrumentationHandler("resource", ({ entries }) => {
      entries.forEach((entry) => {
        if (isPerformanceResourceTiming(entry) && entry.name.endsWith(url)) {
          span.setAttributes(resourceTimingToSpanAttributes(entry));
          onEntryFound();
        }
      });
    });
  }
  function shouldAttachHeaders(targetUrl, tracePropagationTargets) {
    const href = getLocationHref();
    if (!href) {
      const isRelativeSameOriginRequest = !!targetUrl.match(/^\/(?!\/)/);
      if (!tracePropagationTargets) {
        return isRelativeSameOriginRequest;
      } else {
        return matchesTracePropagationTargets(targetUrl, tracePropagationTargets);
      }
    } else {
      let resolvedUrl;
      let currentOrigin;
      try {
        resolvedUrl = new URL(targetUrl, href);
        currentOrigin = new URL(href).origin;
      } catch {
        return false;
      }
      const isSameOriginRequest = resolvedUrl.origin === currentOrigin;
      if (!tracePropagationTargets) {
        return isSameOriginRequest;
      } else {
        return matchesTracePropagationTargets(resolvedUrl.toString(), tracePropagationTargets) || isSameOriginRequest && matchesTracePropagationTargets(resolvedUrl.pathname, tracePropagationTargets);
      }
    }
  }
  function xhrCallback(handlerData, shouldCreateSpan, shouldAttachHeaders2, spans, propagateTraceparent, onRequestSpanEnd) {
    const xhr = handlerData.xhr;
    const sentryXhrData = xhr?.[SENTRY_XHR_DATA_KEY];
    if (!xhr || xhr.__sentry_own_request__ || !sentryXhrData) {
      return void 0;
    }
    const { url, method } = sentryXhrData;
    const shouldCreateSpanResult = hasSpansEnabled() && shouldCreateSpan(url);
    if (handlerData.endTimestamp) {
      const spanId = xhr.__sentry_xhr_span_id__;
      if (!spanId) return;
      const span2 = spans[spanId];
      if (span2) {
        if (shouldCreateSpanResult && sentryXhrData.status_code !== void 0) {
          setHttpStatus(span2, sentryXhrData.status_code);
          span2.end();
          onRequestSpanEnd?.(span2, {
            headers: createHeadersSafely(parseXhrResponseHeaders(xhr)),
            error: handlerData.error
          });
        }
        delete spans[spanId];
      }
      return void 0;
    }
    const fullUrl = getFullURL(url);
    const parsedUrl = fullUrl ? parseUrl(fullUrl) : parseUrl(url);
    const sanitizedFullUrl = fullUrl ? stripDataUrlContent(fullUrl) : void 0;
    const urlForSpanName = stripDataUrlContent(stripUrlQueryAndFragment(url));
    const client = getClient();
    const hasParent = !!getActiveSpan();
    const shouldEmitSpan = hasParent || !!client && hasSpanStreamingEnabled(client);
    const host = parsedUrl?.host?.replace(/^.*@/, "");
    const domain = getUrlDomain(fullUrl || url);
    const streamedName = domain ? `${method} ${domain}` : method;
    const span = shouldCreateSpanResult && shouldEmitSpan ? startInactiveSpan({
      name: !!client && hasSpanStreamingEnabled(client) ? streamedName : `${method} ${urlForSpanName}`,
      attributes: {
        type: "xhr",
        // eslint-disable-next-line typescript/no-deprecated
        [bo]: method,
        [zg]: filterCollectedUrl(sanitizedFullUrl),
        [Zd]: host,
        [Ug]: domain,
        [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "auto.http.browser",
        [cd]: rE,
        [Kg]: filterCollectedUrlQuery(getUrlQuery(parsedUrl?.search)),
        [Gg]: getUrlFragment(parsedUrl?.hash)
      }
    }) : new SentryNonRecordingSpan();
    const spanForTraceHeaders = spanIsIgnored(span) && hasParent ? void 0 : span;
    if (shouldCreateSpanResult && !shouldEmitSpan) {
      client?.recordDroppedEvent("no_parent_span", "span");
    }
    xhr.__sentry_xhr_span_id__ = span.spanContext().spanId;
    spans[xhr.__sentry_xhr_span_id__] = span;
    if (shouldAttachHeaders2(url)) {
      addTracingHeadersToXhrRequest(
        xhr,
        // If performance is disabled (TWP) or there's no active root span (pageload/navigation/interaction),
        // we do not want to use the span as base for the trace headers,
        // which means that the headers will be generated from the scope and the sampling decision is deferred
        hasSpansEnabled() && shouldEmitSpan ? spanForTraceHeaders : void 0,
        propagateTraceparent
      );
    }
    if (client) {
      client.emit("beforeOutgoingRequestSpan", span, handlerData);
    }
    return span;
  }
  function addTracingHeadersToXhrRequest(xhr, span, propagateTraceparent) {
    const { "sentry-trace": sentryTrace, baggage, traceparent } = getTraceData({ span, propagateTraceparent });
    if (sentryTrace) {
      setHeaderOnXhr(xhr, sentryTrace, baggage, traceparent);
    }
  }
  function setHeaderOnXhr(xhr, sentryTraceHeader, sentryBaggageHeader, traceparentHeader) {
    const originalHeaders = xhr.__sentry_xhr_v3__?.request_headers;
    if (originalHeaders?.["sentry-trace"] || !xhr.setRequestHeader) {
      return;
    }
    try {
      xhr.setRequestHeader("sentry-trace", sentryTraceHeader);
      if (traceparentHeader && !originalHeaders?.["traceparent"]) {
        xhr.setRequestHeader("traceparent", traceparentHeader);
      }
      if (sentryBaggageHeader) {
        const originalBaggageHeader = originalHeaders?.["baggage"];
        if (!originalBaggageHeader || !baggageHeaderHasSentryValues(originalBaggageHeader)) {
          xhr.setRequestHeader("baggage", sentryBaggageHeader);
        }
      }
    } catch {
    }
  }

  const BROWSER_TRACING_INTEGRATION_ID = "BrowserTracing";
  const DEFAULT_BROWSER_TRACING_OPTIONS = {
    ...TRACING_DEFAULTS,
    instrumentNavigation: true,
    instrumentBfcacheRestore: true,
    instrumentPageLoad: true,
    markBackgroundSpan: true,
    enableLongTask: true,
    enableLongAnimationFrame: true,
    // oxlint-disable-next-line typescript/no-deprecated -- still honoured until it is removed
    enableInp: true,
    ignoreResourceSpans: [],
    detectRedirects: true,
    linkPreviousTrace: "in-memory",
    consistentTraceSampling: false,
    enableReportPageLoaded: false,
    ...defaultRequestInstrumentationOptions
  };
  const browserTracingIntegration = ((options = {}) => {
    if ("enableElementTiming" in options) {
      consoleSandbox(() => {
        console.warn(
          "[Sentry] `enableElementTiming` is deprecated and no longer has any effect. Use the standalone `elementTimingIntegration` instead."
        );
      });
    }
    const optionalWindowDocument = WINDOW.document;
    const {
      // oxlint-disable-next-line typescript/no-deprecated -- still honoured until it is removed
      enableInp,
      enableLongTask,
      enableLongAnimationFrame,
      webVitals,
      beforeStartSpan,
      idleTimeout,
      finalTimeout,
      childSpanTimeout,
      markBackgroundSpan,
      traceFetch,
      traceXHR,
      shouldCreateSpanForRequest,
      enableHTTPTimings,
      ignoreResourceSpans,
      instrumentPageLoad,
      instrumentNavigation,
      instrumentBfcacheRestore,
      detectRedirects,
      linkPreviousTrace,
      consistentTraceSampling,
      enableReportPageLoaded,
      onRequestSpanStart,
      onRequestSpanEnd
    } = {
      ...DEFAULT_BROWSER_TRACING_OPTIONS,
      ...options
    };
    const _isBot = isBotUserAgent();
    let lastInteractionTimestamp;
    let _pageloadSpan;
    function _createRouteSpan(client, startSpanOptions, makeActive = true, url) {
      const isPageloadSpan = startSpanOptions.op === "pageload";
      const initialSpanName = startSpanOptions.name;
      const finalStartSpanOptions = beforeStartSpan ? beforeStartSpan(startSpanOptions) : startSpanOptions;
      const urlObject = parseStringToURLObject(url || getLocationHref());
      const attributes = {
        ...urlObject?.pathname && { [Yg]: urlObject.pathname },
        ...urlObject && !isURLObjectRelative(urlObject) && { [zg]: filterCollectedUrl(urlObject.href) },
        ...finalStartSpanOptions.attributes
      };
      if (initialSpanName !== finalStartSpanOptions.name) {
        attributes[wd] = "custom";
      }
      finalStartSpanOptions.attributes = attributes;
      if (!makeActive) {
        const now = dateTimestampInSeconds();
        startInactiveSpan({
          ...finalStartSpanOptions,
          startTime: now
        }).end(now);
        return;
      }
      const idleSpan = startIdleSpan(finalStartSpanOptions, {
        idleTimeout,
        finalTimeout,
        childSpanTimeout,
        // should wait for finish signal if it's a pageload transaction
        disableAutoFinish: isPageloadSpan,
        trimIdleSpanEndTimestamp: !enableReportPageLoaded
      });
      if (isPageloadSpan && enableReportPageLoaded) {
        _pageloadSpan = idleSpan;
      }
      setActiveIdleSpan(client, idleSpan);
      function emitFinish() {
        if (optionalWindowDocument && ["interactive", "complete"].includes(optionalWindowDocument.readyState)) {
          client.emit("idleSpanEnableAutoFinish", idleSpan);
          optionalWindowDocument.removeEventListener("readystatechange", emitFinish);
        }
      }
      if (isPageloadSpan && !enableReportPageLoaded && optionalWindowDocument) {
        optionalWindowDocument.addEventListener("readystatechange", emitFinish);
        emitFinish();
      }
    }
    return {
      name: BROWSER_TRACING_INTEGRATION_ID,
      setup(client) {
        if (_isBot) {
          debug.log("[Tracing] Skipping browserTracingIntegration setup for bot user agent.");
          return;
        }
        registerSpanErrorInstrumentation();
        if (enableLongAnimationFrame && GLOBAL_OBJ.PerformanceObserver && PerformanceObserver.supportedEntryTypes?.includes("long-animation-frame")) {
          startTrackingLongAnimationFrames();
        } else if (enableLongTask) {
          startTrackingLongTasks();
        }
        if (detectRedirects && optionalWindowDocument) {
          const interactionHandler = () => {
            lastInteractionTimestamp = timestampInSeconds();
          };
          addEventListener("click", interactionHandler, { capture: true });
          addEventListener("keydown", interactionHandler, { capture: true, passive: true });
        }
        function maybeEndActiveSpan() {
          const activeSpan = getActiveIdleSpan(client);
          if (activeSpan && !spanToJSON(activeSpan).end_timestamp) {
            debug.log(
              `[Tracing] Finishing current active span with op: ${spanToJSON(activeSpan).attributes[cd]}`
            );
            activeSpan.setAttribute(ju, "cancelled");
            activeSpan.end();
          }
        }
        client.on("beforeIdleSpanEnd", (span) => {
          if (getActiveIdleSpan(client) !== span) {
            return;
          }
          addPerformanceEntries(span, {
            ignoreResourceSpans,
            spanStreamingEnabled: hasSpanStreamingEnabled(client)
          });
          setActiveIdleSpan(client, void 0);
          const scope = getCurrentScope();
          const oldPropagationContext = scope.getPropagationContext();
          scope.setPropagationContext({
            ...oldPropagationContext,
            traceId: span.spanContext().traceId,
            sampled: spanIsSampled(span),
            dsc: getDynamicSamplingContextFromSpan(span)
          });
          if (_pageloadSpan === span) {
            _pageloadSpan = void 0;
          }
        });
        client.on("startNavigationSpan", (startSpanOptions, navigationOptions) => {
          if (getClient() !== client) {
            return;
          }
          if (navigationOptions?.isRedirect) {
            debug.warn("[Tracing] Detected redirect, navigation span will not be the root span, but a child span.");
            _createRouteSpan(
              client,
              {
                op: _$1,
                ...startSpanOptions
              },
              false,
              navigationOptions.url
            );
            return;
          }
          lastInteractionTimestamp = void 0;
          maybeEndActiveSpan();
          const scope = getCurrentScope();
          scope.setPropagationContext({
            traceId: generateTraceId(),
            sampleRand: Math.random(),
            propagationSpanId: hasSpansEnabled() ? void 0 : generateSpanId()
          });
          scope.setSDKProcessingMetadata({
            normalizedRequest: void 0
          });
          _createRouteSpan(
            client,
            {
              op: E$1,
              ...startSpanOptions,
              // Navigation starts a new trace and is NOT parented under any active interaction (e.g. ui.action.click)
              parentSpan: null
            },
            true,
            navigationOptions?.url
          );
        });
        client.on("startPageLoadSpan", (startSpanOptions, traceOptions = {}) => {
          if (getClient() !== client) {
            return;
          }
          maybeEndActiveSpan();
          const sentryTrace = traceOptions.sentryTrace || getMetaContent("sentry-trace") || getServerTiming("sentry-trace");
          const baggage = traceOptions.baggage || getMetaContent("baggage") || getServerTiming("baggage");
          const propagationContext = propagationContextFromHeaders(sentryTrace, baggage);
          const scope = getCurrentScope();
          scope.setPropagationContext(propagationContext);
          if (!hasSpansEnabled()) {
            scope.getPropagationContext().propagationSpanId = generateSpanId();
          }
          scope.setSDKProcessingMetadata({
            normalizedRequest: getHttpRequestData()
          });
          _createRouteSpan(client, {
            op: e$1,
            ...startSpanOptions
          });
        });
        client.on("endPageloadSpan", () => {
          if (enableReportPageLoaded && _pageloadSpan) {
            _pageloadSpan.setAttribute(ju, "reportPageLoaded");
            _pageloadSpan.end();
          }
        });
        WINDOW.addEventListener?.("pagehide", () => {
          const activeSpan = getActiveIdleSpan(client);
          if (activeSpan && !spanToJSON(activeSpan).end_timestamp) {
            activeSpan.setAttribute(ju, "documentHidden");
            activeSpan.end();
          }
          void client.flush();
        });
      },
      afterAllSetup(client) {
        if (_isBot) {
          return;
        }
        _INTERNAL_ensureBrowserSpanStreaming(client);
        if (client.addIntegration && !client.getIntegrationByName?.(WEB_VITALS_INTEGRATION_NAME)) {
          const ignore = webVitals?.ignore ?? [];
          client.addIntegration(
            webVitalsIntegration({
              ...webVitals,
              ignore: enableInp || ignore.includes("inp") ? ignore : [...ignore, "inp"]
            })
          );
        }
        let startingUrl = getLocationHref();
        if (linkPreviousTrace !== "off") {
          linkTraces(client, { linkPreviousTrace, consistentTraceSampling });
        }
        if (WINDOW.location) {
          if (instrumentPageLoad) {
            startBrowserTracingPageLoadSpan(client, {
              // With span streaming, span names have to be low cardinality, and there is no route
              // information available here.
              name: hasSpanStreamingEnabled(client) ? PAGELOAD_SPAN_NAME_FALLBACK : WINDOW.location.pathname,
              attributes: {
                [wd]: "url",
                [ud]: "auto.pageload.browser"
              }
            });
          }
          if (instrumentNavigation) {
            addHistoryInstrumentationHandler(({ to, from }) => {
              if (from === void 0 && startingUrl !== void 0 && startingUrl.indexOf(to) !== -1) {
                startingUrl = void 0;
                return;
              }
              startingUrl = void 0;
              const parsed = parseStringToURLObject(to);
              const activeSpan = getActiveIdleSpan(client);
              const navigationIsRedirect = activeSpan && detectRedirects && isRedirect(activeSpan, lastInteractionTimestamp);
              startBrowserTracingNavigationSpan(
                client,
                {
                  // With span streaming, span names have to be low cardinality, and there is no route
                  // information available here.
                  name: hasSpanStreamingEnabled(client) ? NAVIGATION_SPAN_NAME_FALLBACK : parsed?.pathname || WINDOW.location.pathname,
                  attributes: {
                    [wd]: "url",
                    [ud]: "auto.navigation.browser"
                  }
                },
                { url: to, isRedirect: navigationIsRedirect }
              );
            });
          }
          if (instrumentBfcacheRestore) {
            WINDOW.addEventListener?.("pageshow", (event) => {
              if (!event.persisted) {
                return;
              }
              startingUrl = void 0;
              startBrowserTracingNavigationSpan(
                client,
                {
                  // Deliberately no `startTime`: the span starts now, at the restore. The
                  // `PerformanceNavigationTiming` entry still describes the original document load and
                  // would date the span to before the page was frozen.
                  //
                  // TODO(routing): resolve the parameterized route via the route provider (#23551) and set
                  // the source from it. No router event fires on a restore, so in a framework app this is
                  // the only navigation span still named from a raw pathname.
                  name: hasSpanStreamingEnabled(client) ? NAVIGATION_SPAN_NAME_FALLBACK : WINDOW.location?.pathname || "/",
                  attributes: {
                    [wd]: "url",
                    [ud]: "auto.navigation.browser.bfcache",
                    // A bfcache restore is near-instant, so these spans would otherwise drag
                    // navigation duration percentiles down with no way to tell them apart.
                    [Mi]: "back-forward-cache"
                  }
                },
                { url: WINDOW.location?.href }
              );
            });
          }
        }
        if (markBackgroundSpan) {
          registerBackgroundTabDetection();
        }
        instrumentOutgoingRequests(client, {
          traceFetch,
          traceXHR,
          tracePropagationTargets: client.getOptions().tracePropagationTargets,
          shouldCreateSpanForRequest,
          enableHTTPTimings,
          onRequestSpanStart,
          onRequestSpanEnd
        });
      }
    };
  });
  function startBrowserTracingPageLoadSpan(client, spanOptions, traceOptions) {
    const isFallbackSpanName = spanOptions.name === PAGELOAD_SPAN_NAME_FALLBACK;
    getCurrentScope().setTransactionName(isFallbackSpanName ? WINDOW.location?.pathname : spanOptions.name);
    const timeOrigin = browserPerformanceTimeOrigin();
    const pageloadSpanOptions = {
      ...spanOptions,
      // startTime needs to be in seconds, not ms
      startTime: spanOptions.startTime ?? (timeOrigin ? timeOrigin / 1e3 : void 0)
    };
    client.emit("startPageLoadSpan", pageloadSpanOptions, traceOptions);
    const pageloadSpan = getActiveIdleSpan(client);
    if (pageloadSpan) {
      client.emit("afterStartPageLoadSpan", pageloadSpan);
    }
    return pageloadSpan;
  }
  function startBrowserTracingNavigationSpan(client, spanOptions, options) {
    const { url, isRedirect: isRedirect2 } = options || {};
    client.emit("beforeStartNavigationSpan", spanOptions, { isRedirect: isRedirect2, url });
    client.emit("startNavigationSpan", spanOptions, { isRedirect: isRedirect2, url });
    const scope = getCurrentScope();
    const isFallbackSpanName = spanOptions.name === NAVIGATION_SPAN_NAME_FALLBACK;
    scope.setTransactionName(
      isFallbackSpanName ? url && parseStringToURLObject(url)?.pathname || WINDOW.location?.pathname : spanOptions.name
    );
    if (url && !isRedirect2) {
      scope.setSDKProcessingMetadata({
        normalizedRequest: {
          ...getHttpRequestData(),
          url
        }
      });
    }
    return getActiveIdleSpan(client);
  }
  function getMetaContent(metaName) {
    const optionalWindowDocument = WINDOW.document;
    const metaTag = optionalWindowDocument?.querySelector(`meta[name=${metaName}]`);
    return metaTag?.getAttribute("content") || void 0;
  }
  function getServerTiming(name) {
    const navigation = WINDOW.performance?.getEntriesByType?.("navigation")[0];
    const entry = navigation?.serverTiming?.find((entry2) => entry2.name === name);
    return entry?.description;
  }
  const ACTIVE_IDLE_SPAN_PROPERTY = "_sentry_idleSpan";
  function getActiveIdleSpan(client) {
    return client[ACTIVE_IDLE_SPAN_PROPERTY];
  }
  function setActiveIdleSpan(client, span) {
    addNonEnumerableProperty(client, ACTIVE_IDLE_SPAN_PROPERTY, span);
  }
  const REDIRECT_THRESHOLD = 1.5;
  function isRedirect(activeSpan, lastInteractionTimestamp) {
    const spanData = spanToJSON(activeSpan);
    const now = dateTimestampInSeconds();
    const startTimestamp = spanData.start_timestamp;
    if (now - startTimestamp > REDIRECT_THRESHOLD) {
      return false;
    }
    if (lastInteractionTimestamp && now - lastInteractionTimestamp <= REDIRECT_THRESHOLD) {
      return false;
    }
    return true;
  }

  function setActiveSpanInBrowser(span) {
    const maybePreviousActiveSpan = getActiveSpan();
    if (maybePreviousActiveSpan === span) {
      return;
    }
    const scope = getCurrentScope();
    span.end = new Proxy(span.end, {
      apply(target, thisArg, args) {
        _setSpanForScope(scope, maybePreviousActiveSpan);
        return Reflect.apply(target, thisArg, args);
      }
    });
    _setSpanForScope(scope, span);
  }

  function reportPageLoaded(client = getClient()) {
    client?.emit("endPageloadSpan");
  }

  const responseToStreamSpan = /* @__PURE__ */ new WeakMap();
  const responseToFallbackTimeout = /* @__PURE__ */ new WeakMap();
  const STREAM_RESOLVE_FALLBACK_MS = 9e4;
  const STREAMING_CONTENT_TYPES = ["text/event-stream", "application/x-ndjson", "application/stream+json"];
  const fetchStreamPerformanceIntegration = defineIntegration(() => {
    return {
      name: "FetchStreamPerformance",
      setup(client) {
        addFetchEndInstrumentationHandler((handlerData) => {
          if (handlerData.response) {
            const streamSpan = responseToStreamSpan.get(handlerData.response);
            if (streamSpan && handlerData.endTimestamp) {
              streamSpan.end(handlerData.endTimestamp);
              const fallbackTimeout = responseToFallbackTimeout.get(handlerData.response);
              if (fallbackTimeout) {
                clearTimeout(fallbackTimeout);
              }
            }
          }
        });
        addFetchInstrumentationHandler((handlerData) => {
          if (handlerData.endTimestamp && handlerData.response) {
            const contentType = handlerData.response.headers?.get("content-type") || "";
            if (handlerData.response.headers?.get("content-length") || !STREAMING_CONTENT_TYPES.some((t) => contentType.startsWith(t))) {
              return;
            }
            const url = handlerData.fetchData?.url || "";
            const method = handlerData.fetchData?.method || "GET";
            const parsedUrl = parseStringToURLObject(url);
            const sanitizedUrl = url.startsWith("data:") ? stripDataUrlContent(url) : parsedUrl ? getSanitizedUrlStringFromUrlObject(parsedUrl) : url;
            const domain = getUrlDomain(url, WINDOW.location?.origin);
            const streamedName = domain ? `${method} ${domain}` : method;
            const streamSpan = startInactiveSpan({
              name: hasSpanStreamingEnabled(client) ? streamedName : `${method} ${sanitizedUrl}`,
              startTime: handlerData.endTimestamp,
              attributes: {
                [zg]: filterCollectedUrl(stripDataUrlContent(url)),
                [Ug]: domain,
                [bo]: method,
                type: "fetch",
                [cd]: RE,
                [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "auto.http.browser.stream"
              }
            });
            responseToStreamSpan.set(handlerData.response, streamSpan);
            const fallbackTimeout = setTimeout(() => {
              if (streamSpan.isRecording()) {
                streamSpan.end();
              }
            }, STREAM_RESOLVE_FALLBACK_MS);
            responseToFallbackTimeout.set(handlerData.response, fallbackTimeout);
          }
        });
      }
    };
  });

  registerSpanErrorInstrumentation();

  exports.BrowserClient = BrowserClient;
  exports.SDK_VERSION = SDK_VERSION;
  exports.SEMANTIC_ATTRIBUTE_SENTRY_OP = SEMANTIC_ATTRIBUTE_SENTRY_OP;
  exports.SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN = SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN;
  exports.SEMANTIC_ATTRIBUTE_SENTRY_SAMPLE_RATE = SEMANTIC_ATTRIBUTE_SENTRY_SAMPLE_RATE;
  exports.Scope = Scope;
  exports.WINDOW = WINDOW;
  exports.addBreadcrumb = addBreadcrumb;
  exports.addEventProcessor = addEventProcessor;
  exports.addIntegration = addIntegration;
  exports.breadcrumbsIntegration = breadcrumbsIntegration;
  exports.browserApiErrorsIntegration = browserApiErrorsIntegration;
  exports.browserSessionIntegration = browserSessionIntegration;
  exports.browserTracingIntegration = browserTracingIntegration;
  exports.captureEvent = captureEvent;
  exports.captureException = captureException;
  exports.captureFeedback = captureFeedback;
  exports.captureMessage = captureMessage;
  exports.captureSession = captureSession;
  exports.chromeStackLineParser = chromeStackLineParser;
  exports.close = close;
  exports.consoleIntegration = consoleIntegration;
  exports.consoleLoggingIntegration = consoleLoggingIntegrationShim;
  exports.continueTrace = continueTrace;
  exports.createTransport = createTransport;
  exports.createUserFeedbackEnvelope = createUserFeedbackEnvelope;
  exports.dedupeIntegration = dedupeIntegration;
  exports.defaultStackLineParsers = defaultStackLineParsers;
  exports.defaultStackParser = defaultStackParser;
  exports.elementTimingIntegration = elementTimingIntegrationShim;
  exports.endSession = endSession;
  exports.eventFiltersIntegration = eventFiltersIntegration;
  exports.eventFromException = eventFromException;
  exports.eventFromMessage = eventFromMessage;
  exports.exceptionFromError = exceptionFromError;
  exports.feedbackAsyncIntegration = feedbackIntegrationShim;
  exports.feedbackIntegration = feedbackIntegrationShim;
  exports.fetchStreamPerformanceIntegration = fetchStreamPerformanceIntegration;
  exports.flush = flush;
  exports.forceLoad = forceLoad;
  exports.functionToStringIntegration = functionToStringIntegration;
  exports.geckoStackLineParser = geckoStackLineParser;
  exports.getActiveSpan = getActiveSpan;
  exports.getClient = getClient;
  exports.getCurrentScope = getCurrentScope;
  exports.getDefaultIntegrations = getDefaultIntegrations;
  exports.getGlobalScope = getGlobalScope;
  exports.getIsolationScope = getIsolationScope;
  exports.getRootSpan = getRootSpan;
  exports.getSpanDescendants = getSpanDescendants;
  exports.getTraceData = getTraceData;
  exports.globalHandlersIntegration = globalHandlersIntegration;
  exports.httpContextIntegration = httpContextIntegration;
  exports.init = init;
  exports.isBotUserAgent = isBotUserAgent;
  exports.isEnabled = isEnabled;
  exports.isInitialized = isInitialized;
  exports.lastEventId = lastEventId;
  exports.lazyLoadIntegration = lazyLoadIntegration;
  exports.linkedErrorsIntegration = linkedErrorsIntegration;
  exports.logger = loggerShim;
  exports.makeFetchTransport = makeFetchTransport;
  exports.metrics = metricsShim;
  exports.onLoad = onLoad;
  exports.opera10StackLineParser = opera10StackLineParser;
  exports.opera11StackLineParser = opera11StackLineParser;
  exports.parameterize = parameterize;
  exports.replayIntegration = replayIntegrationShim;
  exports.reportPageLoaded = reportPageLoaded;
  exports.setActiveSpanInBrowser = setActiveSpanInBrowser;
  exports.setAttribute = setAttribute;
  exports.setAttributes = setAttributes;
  exports.setContext = setContext;
  exports.setConversationId = setConversationId;
  exports.setCurrentClient = setCurrentClient;
  exports.setExtra = setExtra;
  exports.setExtras = setExtras;
  exports.setMeasurement = setMeasurement;
  exports.setTag = setTag;
  exports.setTags = setTags;
  exports.setUser = setUser;
  exports.showReportDialog = showReportDialog;
  exports.spanStreamingIntegration = spanStreamingIntegration;
  exports.spanToBaggageHeader = spanToBaggageHeader;
  exports.spanToJSON = spanToJSON;
  exports.spanToStaticSpanJSON = spanToStaticSpanJSON;
  exports.spanToTraceHeader = spanToTraceHeader;
  exports.startBrowserTracingNavigationSpan = startBrowserTracingNavigationSpan;
  exports.startBrowserTracingPageLoadSpan = startBrowserTracingPageLoadSpan;
  exports.startInactiveSpan = startInactiveSpan;
  exports.startNewTrace = startNewTrace;
  exports.startSession = startSession;
  exports.startSpan = startSpan;
  exports.startSpanManual = startSpanManual;
  exports.suppressTracing = suppressTracing;
  exports.uiProfiler = uiProfiler;
  exports.updateSpanName = updateSpanName;
  exports.webVitalsIntegration = webVitalsIntegration;
  exports.winjsStackLineParser = winjsStackLineParser;
  exports.withActiveSpan = withActiveSpan;
  exports.withIsolationScope = withIsolationScope;
  exports.withScope = withScope;
  exports.withStaticSpan = withStaticSpan;
  exports.withStreamedSpan = withStreamedSpan;

  return exports;

})({});
//# sourceMappingURL=bundle.tracing.js.map
