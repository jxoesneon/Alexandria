/// Canonical normalization for bounty ids (NFD-style, UAX #15).
///
/// THREAT MODEL — canonical-equivalence spoofing: Unicode admits two
/// spellings of the same grapheme, e.g. U+00E9 `é` vs `e` + U+0301
/// (combining acute). `_isCanonicalBountyId` rejects control/invisible/
/// bidi codepoints but raw `==` treats canonically-equivalent ids as
/// DISTINCT, so an attacker could announce `bounty_x\u0065\u0301` while
/// the escrow/attestation/claim rows key on `bounty_x\u00E9` — a visual
/// and identity collision that splits dedup, defeats tombstones, and
/// mismatches signed `EscrowAttestation.bindsBounty` checks.
///
/// The fix normalizes every id to its fully-decomposed canonical form
/// (NFD) at the trust boundary — ingest AND every comparison site — so
/// canonically-equivalent spellings collapse to ONE id everywhere the
/// id is used as a key. NFD rather than NFC because decomposition needs
/// no composition-exclusion table and canonical equivalence is exactly
/// "same NFD" (UAX #15 §3): two strings are canonically equivalent iff
/// their NFD forms are identical.
///
/// Coverage: the full canonical-decomposition table for the Unicode
/// version pinned in unicode_canonical_tables.dart, Hangul algorithmic
/// decomposition (UAX #15 §3.12), and canonical ordering by combining
/// class. Compatibility decompositions (`<compat>` mappings — halfwidth,
/// circled, superscript forms, …) are deliberately NOT folded: NFKD
/// equivalence is display-level, not canonical identity, and folding it
/// would merge ids the UCD does not consider the same character.
library;

import 'unicode_canonical_tables.dart';

/// Hangul Jamo constants for the algorithmic (table-free) syllable
/// decomposition, per UAX #15 §3.12 / Unicode Standard §3.12.
const int _sBase = 0xAC00;
const int _lBase = 0x1100;
const int _vBase = 0x1161;
const int _tBase = 0x11A7;
const int _lCount = 19;
const int _vCount = 21;
const int _tCount = 28;
const int _nCount = _vCount * _tCount; // 588
const int _sCount = _lCount * _nCount; // 11172

/// Returns the canonical (fully decomposed, canonically ordered) form
/// of [id] — its NFD form. Pure-ASCII inputs return unchanged on a fast
/// path. Unpaired surrogate code units pass through untouched: they are
/// ill-formed, not canonically-equivalent to anything, and the
/// canonical-id gate rejects them downstream.
String normalizeBountyId(String id) {
  // Fast path: no codepoint < 0x80 decomposes or combines, so ASCII ids
  // (the overwhelmingly common case — `bounty_<ms>` etc.) are already
  // canonical.
  var needsWork = false;
  for (final r in id.runes) {
    if (r > 0x7f) {
      needsWork = true;
      break;
    }
  }
  if (!needsWork) return id;

  final out = <int>[];
  for (final r in id.runes) {
    _decomposeCanonical(r, out);
  }
  _orderCanonically(out);
  return String.fromCharCodes(out);
}

/// Canonical-identity comparison for bounty ids: exact match, or equal
/// canonical forms. Use anywhere an id from the wire is compared against
/// a stored/signed id so canonically-equivalent spellings cannot fork
/// the key space.
bool bountyIdsEquivalent(String a, String b) =>
    a == b || normalizeBountyId(a) == normalizeBountyId(b);

/// Recursively appends the canonical decomposition of [r] to [out]
/// (canonical decompositions may themselves contain decomposable
/// codepoints — e.g. U+1E09 → U+0063 U+0327 U+0301 where the cedilla
/// form further decomposes — so each mapped element is decomposed in
/// turn). Hangul syllables decompose algorithmically.
void _decomposeCanonical(int r, List<int> out) {
  // Hangul syllable → Jamo triple, per UAX #15 §3.12 arithmetic.
  if (r >= _sBase && r < _sBase + _sCount) {
    final sIndex = r - _sBase;
    out.add(_lBase + sIndex ~/ _nCount);
    out.add(_vBase + (sIndex % _nCount) ~/ _tCount);
    final tIndex = sIndex % _tCount;
    if (tIndex > 0) out.add(_tBase + tIndex);
    return;
  }
  final mapped = kCanonicalDecomposition[r];
  if (mapped == null) {
    out.add(r);
    return;
  }
  for (final m in mapped) {
    _decomposeCanonical(m, out);
  }
}

int _ccc(int r) => kCanonicalCombiningClass[r] ?? 0;

/// Canonical ordering (UAX #15 §3.11 D108): stable-sort each run of
/// non-starters by ascending canonical combining class. Implemented as
/// an insertion pass — a mark only bubbles left past marks with a
/// strictly greater class, so equal classes keep their relative order
/// (stability is required for correctness).
void _orderCanonically(List<int> buf) {
  for (var i = 1; i < buf.length; i++) {
    final c = _ccc(buf[i]);
    if (c == 0) continue; // starter — begins a new reordering segment
    var j = i;
    while (j > 0 && _ccc(buf[j - 1]) > c) {
      final tmp = buf[j - 1];
      buf[j - 1] = buf[j];
      buf[j] = tmp;
      j--;
    }
  }
}
