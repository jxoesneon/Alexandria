#!/usr/bin/env node

/**
 * Alexandria MCP **SIMULATOR** (ALX-006) — development harness only.
 *
 * This is NOT a live Alexandria node. It is a zero-dependency mock of the
 * in-app Dart MCP server (lib/services/agent/alexandria_mcp_server.dart)
 * kept for exercising external-agent client plumbing during development.
 *
 * SAFETY (ALX-010/ALX-011 veto):
 *  - Every response is stamped `simulated: true` / `mock: true`.
 *  - ALL financial and credit-minting tools were REMOVED. A previous
 *    version of this file minted fake credits (`+=15`/`+=5`), exported
 *    counterfeit `cashuA` bearer tokens, and reported `settled_live`
 *    Lightning payouts with fabricated preimages — pure fraud surface.
 *    The surviving tools are strictly non-monetary: archive search,
 *    read-only wallet telemetry, replication commissioning, and bounty
 *    announcement against an in-process mock state.
 *  - The process refuses to start unless invoked with `--dev` (or
 *    `--simulator`), so it can never be exported to an agent runtime by
 *    accident.
 *
 * The real tool surface lives inside the app: AlexandriaMcpServer wires
 * the persistent credit ledger, verifier-signed work receipts, and the
 * egress lockdown. This file mirrors only the harmless subset of its
 * schema and must never be presented as a production node.
 *
 * BRIDGE MODE (ALX-012 §5.2/§5.6 — the real stdio runner): invoked with
 *   --bridge --port <p> --token <t>     (or env ALX_MCP_PORT/ALX_MCP_TOKEN)
 * this file becomes a zero-dependency thin shim between stdio JSON-RPC
 * and the app's authenticated loopback control socket
 * (lib/services/agent/mcp_stdio_runner.dart — McpControlSocket). The
 * shim holds the per-process session token and injects it into every
 * forwarded request (`session_token`), so MCP clients never learn the
 * credential. It performs no tool logic, no auth decisions, and no
 * buffering beyond line framing — the Dart runner enforces the
 * allowlist, rate budgets, and consent ceilings.
 */

const readline = require('readline');
const crypto = require('crypto');
const net = require('net');

// ---- Mode selection ------------------------------------------------------
const bridgeMode = process.argv.includes('--bridge');
const devMode =
  process.argv.includes('--dev') || process.argv.includes('--simulator');

function argValue(flag) {
  const i = process.argv.indexOf(flag);
  return i !== -1 ? process.argv[i + 1] : undefined;
}

if (bridgeMode) {
  // ---- Thin stdio → authenticated control-socket bridge -----------------
  const port = Number(argValue('--port') || process.env.ALX_MCP_PORT || 0);
  const token = argValue('--token') || process.env.ALX_MCP_TOKEN || '';
  if (!port || !token) {
    process.stderr.write(
      'alexandria-mcp-bridge: --bridge requires --port and --token ' +
        '(or ALX_MCP_PORT / ALX_MCP_TOKEN).\n'
    );
    process.exit(1);
  }

  const socket = net.connect({ host: '127.0.0.1', port });
  let authed = false;
  let sockBuf = '';

  socket.on('connect', () => {
    // First frame is the control-socket handshake; every later request
    // still carries the token — the handshake is transport auth, not a
    // credential replacement.
    socket.write(JSON.stringify({ auth: token }) + '\n');
  });

  socket.on('data', (chunk) => {
    sockBuf += chunk.toString('utf8');
    let nl;
    while ((nl = sockBuf.indexOf('\n')) !== -1) {
      const line = sockBuf.slice(0, nl);
      sockBuf = sockBuf.slice(nl + 1);
      if (!line.trim()) continue;
      if (!authed) {
        // Expected: {"ok":true} — anything else means auth failed.
        try {
          const frame = JSON.parse(line);
          if (frame.ok === true) {
            authed = true;
            continue;
          }
        } catch (_) {}
        process.stderr.write('alexandria-mcp-bridge: control socket rejected auth.\n');
        process.exit(1);
      }
      process.stdout.write(line + '\n');
    }
  });

  socket.on('error', (err) => {
    process.stderr.write(`alexandria-mcp-bridge: socket error: ${err.message}\n`);
    process.exit(1);
  });
  socket.on('close', () => process.exit(0));

  const bridgeRl = readline.createInterface({
    input: process.stdin,
    terminal: false
  });
  bridgeRl.on('line', (line) => {
    if (!line.trim()) return;
    try {
      const req = JSON.parse(line);
      // Inject the session credential into every forwarded request.
      req.session_token = token;
      socket.write(JSON.stringify(req) + '\n');
    } catch (err) {
      process.stdout.write(JSON.stringify({
        jsonrpc: '2.0',
        error: { code: -32700, message: `Parse error: ${err.message}` }
      }) + '\n');
    }
  });
} else if (!devMode) {
  // ---- Dev-mode gate ------------------------------------------------------
  // Refuse to run as a default/implicit MCP server. The exported configs
  // produced by the app pass --dev explicitly.
  process.stderr.write(
    'alexandria-mcp-simulator: refusing to start without --dev or --bridge.\n' +
      'This file is a DEVELOPMENT SIMULATOR — it is not a live Alexandria ' +
      'node and exposes no real credits, payouts, or archive state.\n' +
      'The production MCP surface is AlexandriaMcpServer inside the app ' +
      '(lib/services/agent/alexandria_mcp_server.dart), reached through ' +
      '--bridge --port <p> --token <t> against its authenticated control ' +
      'socket.\n'
  );
  process.exit(1);
}

// In-process mock state. `credits` is a simulated display balance only —
// no tool in this file can mint or egress value.
const state = {
  credits: 100.0,
  protocolTreasury: 4.2,
  archivalCommonsPool: 18.5,
  pochScore: 1.0,
  isPochCompliant: true,
  bandwidthMultiplier: 1.0,
  storageBytes: 1024 * 1024 * 1024, // 1 GB
  seedingBytes: 250 * 1024 * 1024,
  porChallengesAnswered: 1,
  agentId: 'bcn_sim_steward_01',
  bounties: [
    {
      id: 'bcn_sample_01',
      cid: 'bafk_sample_bounty',
      title: 'Preserve Turing 1936 Computable Numbers',
      doi: '10.1112/plms/s2-42.1.230',
      offeredCredits: 30.0,
      urgency: 'high'
    }
  ]
};

// Simulated-only tool surface. Every tool that minted, debited-to-
// external, or exported value was removed (ALX-010/ALX-011 safety veto):
//   REMOVED alexandria_ingest_doi            (minted +15 ℭ per call)
//   REMOVED alexandria_submit_por_challenge  (minted +5 ℭ, always "valid")
//   REMOVED alexandria_export_cashu_voucher  (counterfeit cashuA tokens)
//   REMOVED alexandria_sweep_lightning_live  (fabricated preimages,
//                                           'settled_live' payouts)
const TOOLS = [
  {
    name: 'alexandria_search_archive',
    description:
      '[SIMULATED] Searches the decentralized Alexandria library for academic documents, preprints, and CIDs. Returns mock data.',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search keyword, author, paper title, or DOI'
        }
      },
      required: ['query']
    }
  },
  {
    name: 'alexandria_get_wallet_balance',
    description:
      '[SIMULATED] Retrieves mock node Archival Credit balance, Proof of Common Heritage (PoCH) score, and QoS multiplier.',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  },
  {
    name: 'alexandria_replicate_cid',
    description:
      '[SIMULATED] Commissions parity replication across the peer swarm. Debits a mock credit balance only — no real credits move.',
    inputSchema: {
      type: 'object',
      properties: {
        cid: {
          type: 'string',
          description: 'The target Content Identifier (CIDv1)'
        },
        credits: {
          type: 'number',
          description: 'Amount of (simulated) Archival Credits to allocate'
        }
      },
      required: ['cid', 'credits']
    }
  },
  {
    name: 'alexandria_post_moltbook_bounty',
    description:
      '[SIMULATED] Publishes a mock preservation bounty to a local Moltbook feed. Nothing is signed or broadcast.',
    inputSchema: {
      type: 'object',
      properties: {
        cid: { type: 'string', description: 'Target endangered CID' },
        doi: { type: 'string', description: 'Optional DOI of the document' },
        title: { type: 'string', description: 'Descriptive title for the bounty' },
        credits_reward: {
          type: 'number',
          description: 'Reward offered in (simulated) Archival Credits'
        },
        urgency: {
          type: 'string',
          enum: ['normal', 'high', 'critical'],
          description: 'Urgency level of the preservation alert'
        }
      },
      required: ['cid', 'title', 'credits_reward']
    }
  }
];

function textResponse(payload) {
  // Stamp every payload at the data level so no consumer can mistake
  // simulator output for live-node state.
  const stamped =
    payload && typeof payload === 'object' && !Array.isArray(payload)
      ? { simulated: true, mock: true, ...payload }
      : `[SIMULATOR] ${payload}`;
  return {
    content: [
      {
        type: 'text',
        text:
          typeof stamped === 'string'
            ? stamped
            : JSON.stringify(stamped, null, 2)
      }
    ],
    isError: false,
    simulated: true,
    mock: true
  };
}

function errorResponse(message) {
  return {
    content: [{ type: 'text', text: `[SIMULATOR] ${message}` }],
    isError: true,
    simulated: true,
    mock: true
  };
}

async function executeTool(name, args = {}) {
  switch (name) {
    case 'alexandria_search_archive': {
      const q = (args.query || '').toLowerCase();
      const matches = [
        {
          cid: 'bafkreic3w7j4pqwqlp...',
          title: 'Attention Is All You Need',
          doi: '10.48550/arXiv.1706.03762',
          replicas: 12,
          rarity: 'Healthy'
        },
        ...state.bounties
          .filter(b => b.title.toLowerCase().includes(q) || (b.doi && b.doi.includes(q)) || b.cid.includes(q))
          .map(b => ({
            cid: b.cid,
            title: b.title,
            doi: b.doi,
            replicas: 1,
            rarity: 'Critically Endangered',
            bounty_credits: b.offeredCredits
          }))
      ];
      return textResponse({
        query: args.query,
        total_matches: matches.length,
        matches
      });
    }

    case 'alexandria_get_wallet_balance': {
      return textResponse({
        balance_credits: state.credits,
        protocol_treasury: state.protocolTreasury,
        archival_commons_pool: state.archivalCommonsPool,
        poch_score: state.pochScore,
        is_poch_compliant: state.isPochCompliant,
        bandwidth_qos_multiplier: state.bandwidthMultiplier,
        contributions: {
          storage_mb: state.storageBytes / (1024 * 1024),
          seeding_mb: state.seedingBytes / (1024 * 1024),
          por_challenges_passed: state.porChallengesAnswered
        },
        note: 'Mock telemetry from the development simulator — not a live node balance.'
      });
    }

    case 'alexandria_replicate_cid': {
      const cid = args.cid;
      const credits = Number(args.credits || 0);
      if (!cid || credits <= 0) {
        return errorResponse('Valid CID and credits > 0 are required.');
      }
      if (state.credits < credits) {
        return errorResponse(`Insufficient simulated balance (${state.credits.toFixed(1)} ℭ) to allocate ${credits} ℭ.`);
      }
      state.credits -= credits;
      return textResponse({
        status: 'success',
        cid,
        credits_spent: credits,
        swarm_tasks_dispatched: 5,
        remaining_balance: state.credits
      });
    }

    case 'alexandria_post_moltbook_bounty': {
      const cid = args.cid;
      const title = args.title;
      const credits = Number(args.credits_reward || 0);
      if (!cid || !title || credits <= 0) {
        return errorResponse('Valid cid, title, and credits_reward > 0 are required.');
      }
      const bountyId = `bcn_sim_${crypto.randomBytes(6).toString('hex')}`;
      state.bounties.push({
        id: bountyId,
        cid,
        title,
        doi: args.doi,
        offeredCredits: credits,
        urgency: args.urgency || 'normal'
      });
      return textResponse({
        status: 'simulated_publish',
        bounty_id: bountyId,
        moltbook_submolt: 'alexandria-bounties',
        author_agent_id: state.agentId,
        offered_credits: credits,
        note: 'Mock bounty recorded locally — nothing was signed or broadcast.'
      });
    }

    default:
      return errorResponse(`Unknown tool: ${name}`);
  }
}

// JSON-RPC 2.0 stdio loop — simulator only. In --bridge mode stdin is
// owned by the bridge's own readline interface above; registering a
// second consumer would split the input stream.
if (!bridgeMode) {
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

rl.on('line', async (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;

  try {
    const req = JSON.parse(trimmed);
    const { id, method, params } = req;

    if (method === 'initialize') {
      process.stdout.write(JSON.stringify({
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: '2024-11-05',
          capabilities: { tools: {} },
          serverInfo: {
            name: 'alexandria-mcp-simulator',
            version: '1.0.0',
            simulated: true,
            mock: true
          }
        }
      }) + '\n');
    } else if (method === 'notifications/initialized') {
      // No response required for notification
    } else if (method === 'tools/list') {
      process.stdout.write(JSON.stringify({
        jsonrpc: '2.0',
        id,
        result: { tools: TOOLS, simulated: true, mock: true }
      }) + '\n');
    } else if (method === 'tools/call') {
      const toolName = params ? params.name : '';
      const args = params ? params.arguments : {};
      const result = await executeTool(toolName, args);
      process.stdout.write(JSON.stringify({
        jsonrpc: '2.0',
        id,
        result
      }) + '\n');
    } else {
      process.stdout.write(JSON.stringify({
        jsonrpc: '2.0',
        id,
        error: {
          code: -32601,
          message: `Method not found: ${method}`
        }
      }) + '\n');
    }
  } catch (err) {
    process.stdout.write(JSON.stringify({
      jsonrpc: '2.0',
      error: {
        code: -32700,
        message: `Parse error: ${err.message}`
      }
    }) + '\n');
  }
});
}
