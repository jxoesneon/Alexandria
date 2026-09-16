import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Tool dispatch into the app's existing service container. The runner
/// is deliberately a THIN SHIM (ALX-012 §5.6): it never constructs a
/// second ProviderContainer — the caller injects the already-wired
/// `AlexandriaMcpServer.listTools`/`callTool` (or any equivalent pair).
typedef McpToolLister = List<Map<String, dynamic>> Function();
typedef McpToolInvoker = Future<Map<String, dynamic>> Function(
    String toolName, Map<String, dynamic> arguments);

/// Human-consent surface for economic tool calls (ALX-012 §5.2.3).
/// Called synchronously before any spend executes; returning false (or
/// throwing, or never being installed) refuses the call. The request
/// carries the prospective amount and the session's spend-so-far so the
/// consent UI can render an informed yes/no.
typedef McpConsentHook = Future<bool> Function(McpSpendRequest request);

/// A pending economic tool call presented to the consent hook.
class McpSpendRequest {
  final String toolName;
  final double amountCredits;
  final double sessionSpendBefore;
  final double sessionCeilingCredits;
  final Map<String, dynamic> arguments;

  const McpSpendRequest({
    required this.toolName,
    required this.amountCredits,
    required this.sessionSpendBefore,
    required this.sessionCeilingCredits,
    required this.arguments,
  });
}

/// Per-tool sliding-window rate budget (ALX-012 §5.2.2): at most
/// [maxCalls] invocations of one tool inside [window]. Budgets are
/// independent per tool — a runaway loop on one tool cannot starve or
/// exceed another's allowance.
class McpRateBudget {
  final int maxCalls;
  final Duration window;
  const McpRateBudget({required this.maxCalls, required this.window});
}

/// The gated JSON-RPC front door for `AlexandriaMcpServer` — the "real
/// MCP stdio runner" deferred milestone (ALX-012 §5.2/§5.6).
///
/// Preconditions implemented here:
///
///  1. SESSION-SCOPED AUTH — a per-process random token (generated, never
///     persisted, never written to exported config) gates EVERY request,
///     including `initialize` and `tools/list`. `stdio-open` is not a
///     session boundary: any local process could open the pipe, so the
///     token — not process existence — is the credential.
///  2. PER-TOOL RATE BUDGETS — independent sliding windows per tool
///     ([McpRateBudget]).
///  3. SPEND/ESCROW CEILINGS + HUMAN CONSENT — economic tools (anything
///     that can debit or escrow ℭ) require the installed [McpConsentHook]
///     to approve each call, AND cumulative session spend is hard-capped
///     at [sessionSpendCeilingCredits] (consent cannot exceed it).
///  4. READ-ONLY ALLOWLIST — the default surface is exactly
///     [readOnlyAllowlist]; nothing else is dispatchable. Minting tools
///     additionally require [permitMintingTools] — the receipt-ingest
///     gate of §5.2.4 stays shut until signed-claim verification is
///     wired end-to-end (WorkReceipt claim path).
///
/// Non-goals (documented bounds): the runner authenticates the session,
/// not the agent's *intent* — a compromised-but-authenticated agent can
/// still spend up to the ceiling. The ceiling and consent hook are the
/// bound; the allowlist is the blast-radius limiter.
class AlexandriaMcpRunner {
  /// Read-only, non-economic default tool surface (ALX-012 §5.6).
  static const Set<String> readOnlyAllowlist = {
    'alexandria_search_archive',
    'alexandria_get_wallet_balance',
    'alexandria_request_por_challenge',
  };

  /// Default per-tool budget when the operator does not pin one.
  static const McpRateBudget defaultBudget =
      McpRateBudget(maxCalls: 30, window: Duration(minutes: 1));

  /// Tools that debit or escrow credits → consent + ceiling gated.
  /// Maps tool name → the argument carrying the credit amount.
  static const Map<String, String> spendArgumentByTool = {
    'alexandria_replicate_cid': 'credits',
    'alexandria_post_moltbook_bounty': 'credits_reward',
    'alexandria_export_cashu_voucher': 'credits',
    'alexandria_sweep_lightning_live': 'credits',
  };

  /// Tools that mint value or ingest receipt-claims. These stay refused
  /// even when added to the allowlist unless [permitMintingTools] is
  /// explicitly set — receipt ingest is off the tool surface until
  /// signed-claim verification is wired (ALX-012 §5.2.4). This is a
  /// deliberate second gate, not a documentation note.
  static const Set<String> mintingTools = {
    'alexandria_ingest_doi',
    'alexandria_submit_por_challenge',
  };

  final McpToolLister _listTools;
  final McpToolInvoker _callTool;
  final String _sessionToken;
  final Set<String> _allowedTools;
  final Map<String, McpRateBudget> _rateBudgets;
  final McpConsentHook? _consentHook;

  /// Hard cap on cumulative debited/escrowed credits this session may
  /// approve. Consent can never exceed it — the ceiling is the bound a
  /// compromised agent cannot talk its way past. Default 0: no economic
  /// call is ever permitted without an operator-set ceiling.
  final double sessionSpendCeilingCredits;

  /// §5.2.4 gate: minting/receipt-ingest tools are refused while false,
  /// regardless of the allowlist.
  final bool permitMintingTools;

  double _sessionSpend = 0.0;
  final Map<String, List<DateTime>> _callLog = {};

  AlexandriaMcpRunner({
    String? sessionToken,
    required McpToolLister listTools,
    required McpToolInvoker callTool,
    Set<String>? allowedTools,
    Map<String, McpRateBudget>? rateBudgets,
    McpConsentHook? consentHook,
    this.sessionSpendCeilingCredits = 0.0,
    this.permitMintingTools = false,
  })  : _listTools = listTools,
        _callTool = callTool,
        _sessionToken = sessionToken ?? generateSessionToken(),
        // Frozen copy — the caller must not widen the surface after
        // construction by mutating the set it handed in.
        _allowedTools = Set.unmodifiable(
            allowedTools ?? Set.of(readOnlyAllowlist)),
        _rateBudgets = Map.unmodifiable(rateBudgets ?? const {}),
        _consentHook = consentHook;

  /// Generates a session credential: 256 bits of CSPRNG entropy,
  /// base64url — never stored, never exported to client config; the
  /// operator hands it to the bridge shim out-of-band.
  static String generateSessionToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// The session token this runner authenticates against. Exposed for
  /// the in-process host to hand to its own bridge child process.
  String get sessionToken => _sessionToken;

  /// Cumulative credits debited/escrowed through economic tools this
  /// session (successful calls only).
  double get sessionSpend => _sessionSpend;

  /// Constant-time token comparison: an early-exit `==` would leak
  /// prefix length through timing — a local attacker could then recover
  /// the credential byte-by-byte. (Loopback-only threat, but the runner
  /// is the authentication boundary; keep it honest.)
  bool _tokenMatches(String? presented) {
    final expected = _sessionToken;
    if (presented == null) return false;
    final a = utf8.encode(presented);
    final b = utf8.encode(expected);
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Extracts the presented session token: accepted at top level
  /// (`session_token`) or under `params._meta.session_token` (the MCP
  /// conventional out-of-band channel).
  String? _presentedToken(Map<String, dynamic> request) {
    final top = request['session_token'];
    if (top is String) return top;
    final params = request['params'];
    if (params is Map) {
      final meta = params['_meta'];
      if (meta is Map && meta['session_token'] is String) {
        return meta['session_token'] as String;
      }
      final p = params['session_token'];
      if (p is String) return p;
    }
    return null;
  }

  Map<String, dynamic> _rpcError(dynamic id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  /// Handles one JSON-RPC 2.0 request. Returns null for notifications
  /// (no `id`), so transports know not to write a response line.
  Future<Map<String, dynamic>?> handleJsonRpcRequest(
      Map<String, dynamic> request) async {
    final id = request['id'];
    final method = request['method'] as String?;

    // Auth gate: every method — including initialize/tools/list —
    // requires the session credential. Unauthenticated requests get
    // nothing that reveals server shape beyond an auth error.
    if (!_tokenMatches(_presentedToken(request))) {
      return _rpcError(id, -32001, 'Unauthorized: session token required');
    }

    switch (method) {
      case 'initialize':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'protocolVersion': '2024-11-05',
            'capabilities': {'tools': {}},
            'serverInfo': {
              'name': 'alexandria-mcp-runner',
              'version': '1.0.0',
            },
          },
        };
      case 'ping':
        return {'jsonrpc': '2.0', 'id': id, 'result': <String, dynamic>{}};
      case 'notifications/initialized':
      case 'notifications/cancelled':
        return null;
      case 'tools/list':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            // Only allowlisted tools are advertised — an agent cannot
            // even discover gated tools through the runner.
            'tools': _listTools()
                .where((t) => _allowedTools.contains(t['name']))
                .toList(),
          },
        };
      case 'tools/call':
        final paramsRaw = request['params'];
        final params = paramsRaw is Map
            ? Map<String, dynamic>.from(paramsRaw)
            : <String, dynamic>{};
        final name = params['name'] as String? ?? '';
        final argsRaw = params['arguments'];
        final args = argsRaw is Map
            ? Map<String, dynamic>.from(argsRaw)
            : <String, dynamic>{};
        final outcome = await _dispatchToolCall(name, args);
        final protocolError = outcome._protocolError;
        if (protocolError != null) {
          return _rpcError(
              id, protocolError, outcome._errorMessage ?? 'error');
        }
        return {'jsonrpc': '2.0', 'id': id, 'result': outcome._result};
      default:
        return _rpcError(id, -32601, 'Method not found: $method');
    }
  }

  bool _budgetAllows(String tool) {
    final budget = _rateBudgets[tool] ?? defaultBudget;
    final now = DateTime.now();
    final log = _callLog.putIfAbsent(tool, () => []);
    log.removeWhere((t) => now.difference(t) > budget.window);
    if (log.length >= budget.maxCalls) return false;
    log.add(now);
    return true;
  }

  /// The gated dispatch: allowlist → mint gate → rate budget →
  /// consent/ceiling → invoke. Order matters: the allowlist runs first
  /// so a non-allowlisted name never even burns rate-budget tokens.
  Future<_ToolOutcome> _dispatchToolCall(
      String tool, Map<String, dynamic> args) async {
    if (!_allowedTools.contains(tool)) {
      return _ToolOutcome.error('Tool not allowed: $tool');
    }
    if (mintingTools.contains(tool) && !permitMintingTools) {
      return _ToolOutcome.error(
          'Tool $tool is a minting/receipt-ingest path — excluded until '
          'signed-claim verification is wired (ALX-012 §5.2.4)');
    }
    if (!_budgetAllows(tool)) {
      return _ToolOutcome.protocolError(
          -32029, 'Rate budget exceeded for tool: $tool');
    }

    // Economic gate: consent hook per call + hard session ceiling.
    final spendArg = spendArgumentByTool[tool];
    if (spendArg != null) {
      final amount = (args[spendArg] as num?)?.toDouble() ?? 0.0;
      if (!amount.isFinite || amount <= 0) {
        return _ToolOutcome.error(
            'Tool $tool requires a positive finite $spendArg amount.');
      }
      final projected = _sessionSpend + amount;
      if (projected > sessionSpendCeilingCredits) {
        // Hard ceiling: consent cannot override — the point of the
        // ceiling is that a compromised agent cannot exceed it even
        // by spamming the consent surface.
        return _ToolOutcome.error(
            'Session spend ceiling exceeded: ${projected.toStringAsFixed(3)} '
            'ℭ requested vs ${sessionSpendCeilingCredits.toStringAsFixed(3)} '
            'ℭ ceiling (spent ${_sessionSpend.toStringAsFixed(3)} ℭ).');
      }
      final consent = _consentHook;
      if (consent == null) {
        return _ToolOutcome.error(
            'Tool $tool can debit/escrow credits but no human-consent '
            'hook is installed (ALX-012 §5.2.3) — refusing.');
      }
      bool approved;
      try {
        approved = await consent(McpSpendRequest(
          toolName: tool,
          amountCredits: amount,
          sessionSpendBefore: _sessionSpend,
          sessionCeilingCredits: sessionSpendCeilingCredits,
          arguments: args,
        ));
      } catch (_) {
        approved = false; // consent surface failed — fail closed
      }
      if (!approved) {
        return _ToolOutcome.error('Human consent denied for $tool.');
      }
      final result = await _callTool(tool, args);
      if (result['isError'] != true) _sessionSpend += amount;
      return _ToolOutcome.ok(result);
    }

    return _ToolOutcome.ok(await _callTool(tool, args));
  }
}

class _ToolOutcome {
  final Map<String, dynamic>? _result;
  final int? _protocolError;
  final String? _errorMessage;
  const _ToolOutcome._(this._result, this._protocolError, this._errorMessage);
  factory _ToolOutcome.ok(Map<String, dynamic> result) =>
      _ToolOutcome._(result, null, null);
  factory _ToolOutcome.error(String message) => _ToolOutcome._(
        {
          'content': [
            {'type': 'text', 'text': message}
          ],
          'isError': true,
        },
        null,
        null,
      );
  factory _ToolOutcome.protocolError(int code, String message) =>
      _ToolOutcome._(null, code, message);
}

/// Authenticated local control socket for [AlexandriaMcpRunner]
/// (ALX-012 §5.6: "a thin stdio shim to an authenticated local control
/// socket of the running node").
///
/// Binds loopback-only ([InternetAddress.loopbackIPv4]) on an ephemeral
/// port. Wire protocol is newline-delimited JSON:
///  * the client MUST send `{"auth": "<sessionToken>"}` as its FIRST
///    frame, within [authTimeout] of connecting — anything else (or a
///    timeout) closes the connection;
///  * each subsequent frame is a JSON-RPC request passed to the
///    runner's `handleJsonRpcRequest`; non-null responses are written
///    back one-per-line;
///  * requests still carry the session token — socket auth is the
///    transport handshake, not a credential replacement (§5.6: "session
///    credential, not process existence").
class McpControlSocket {
  final AlexandriaMcpRunner runner;
  final Duration authTimeout;
  final int maxFrameBytes;

  ServerSocket? _server;
  final List<Socket> _connections = [];

  McpControlSocket(
    this.runner, {
    this.authTimeout = const Duration(seconds: 5),
    this.maxFrameBytes = 1 << 20, // 1 MiB frame cap — a DoS bound
  });

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  Future<int> start() async {
    final server =
        _server ??= await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handleConnection);
    return server.port;
  }

  void _handleConnection(Socket socket) {
    _connections.add(socket);
    var authed = false;
    var done = false;
    final buffer = <int>[];
    StreamSubscription<List<int>>? sub;
    Timer? authTimer;

    void close() {
      if (done) return;
      done = true;
      authTimer?.cancel();
      sub?.cancel();
      _connections.remove(socket);
      socket.destroy();
    }

    // Serialized outbox: dart:io's flush() BINDS the sink for the
    // duration of the write — a writeln issued while a flush is pending
    // throws "StreamSink is bound to a stream". Two frames arriving in
    // one chunk spawn concurrent processLine calls, so every write +
    // flush is chained through this queue.
    var outbox = Future<void>.value();
    void enqueueWrite(Map<String, dynamic> response) {
      outbox = outbox.then((_) async {
        if (done) return;
        socket.writeln(jsonEncode(response));
        await socket.flush();
      }).catchError((_) {});
    }

    Future<void> processLine(List<int> lineBytes) async {
      Map<String, dynamic> request;
      try {
        request = jsonDecode(utf8.decode(lineBytes)) as Map<String, dynamic>;
      } catch (_) {
        enqueueWrite({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32700, 'message': 'Parse error'}
        });
        return;
      }
      final response = await runner.handleJsonRpcRequest(request);
      if (response != null) enqueueWrite(response);
    }

    Future<void> processAuth(List<int> lineBytes) async {
      try {
        final frame =
            jsonDecode(utf8.decode(lineBytes)) as Map<String, dynamic>;
        // Reuse the runner's constant-time credential check — the socket
        // adds no second secret to manage.
        if (runner._tokenMatches(frame['auth'] as String?)) {
          authed = true;
          authTimer?.cancel();
          enqueueWrite({'ok': true});
        } else {
          close();
        }
      } catch (_) {
        close();
      }
    }

    authTimer = Timer(authTimeout, () {
      if (!authed) close();
    });

    // Pre-auth pipeline: frames are processed strictly in arrival order
    // until the handshake completes. Without this chain, an `auth` frame
    // and a request frame landing in ONE TCP chunk would race — the
    // request could be routed to processAuth before the async handshake
    // set `authed`, closing a legitimately-authenticated connection.
    var pipeline = Future<void>.value();

    // Frame accumulation with a hard byte cap — an unbounded line buffer
    // would let a local peer exhaust memory with one giant "line".
    sub = socket.listen(
      (chunk) {
        buffer.addAll(chunk);
        if (buffer.length > maxFrameBytes) {
          close();
          return;
        }
        int nl;
        while ((nl = buffer.indexOf(10)) != -1) {
          final line = buffer.sublist(0, nl);
          buffer.removeRange(0, nl + 1);
          if (line.isNotEmpty && line.last == 13) line.removeLast();
          if (line.isEmpty) continue;
          if (!authed) {
            pipeline = pipeline.then((_) async {
              if (done) return;
              // Re-check inside the chain: once an earlier auth frame
              // completes, subsequent queued frames are real requests.
              if (authed) {
                await processLine(line);
              } else {
                await processAuth(line);
              }
            });
          } else {
            unawaited(processLine(line));
          }
        }
      },
      onDone: close,
      onError: (_) => close(),
      cancelOnError: true,
    );
  }

  Future<void> close() async {
    for (final c in List.of(_connections)) {
      c.destroy();
    }
    _connections.clear();
    await _server?.close();
    _server = null;
  }
}
