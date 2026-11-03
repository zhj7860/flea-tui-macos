// The packed forms against the scorer as it stood before them, so a packing slip cannot hide behind the same code on both sides.
use super::*;

fn score(hay: &str, query: &str) -> Option<i32> {
    Fuzzy::new(query).score(hay)
}

// The scorer as it stood before the packed forms: one Folded per char, no prefilter, none of this file's packing.
fn classic_score(candidate: &str, query: &str) -> Option<i32> {
    let needle: Vec<char> = query.to_lowercase().chars().collect();
    if needle.is_empty() {
        return Some(0);
    }
    let hay: Vec<Folded> = candidate.chars().map(fold).collect();
    let base = hay.iter().rposition(|c| c.lower == '/').map_or(0, |slash| slash + 1);
    let (mut best, mut starts) = (None::<i32>, 0);
    for start in (0..hay.len()).filter(|&i| hay[i].lower == needle[0]) {
        let (mut total, mut at, mut previous) = (0, start, None::<usize>);
        for (k, wanted) in needle.iter().enumerate() {
            if k > 0 {
                at += 1;
                while at < hay.len() && hay[at].lower != *wanted {
                    at += 1;
                }
                if at == hay.len() {
                    return best;
                }
            }
            total += match previous {
                Some(p) if at == p + 1 => BONUS_CONSECUTIVE,
                Some(p) => -PENALTY_GAP * (at - p - 1) as i32,
                None => 0,
            };
            if at == 0 || is_separator(hay[at - 1].lower) || (hay[at].upper && !hay[at - 1].upper) {
                total += BONUS_BOUNDARY;
            }
            if at >= base {
                total += BONUS_BASENAME;
            }
            previous = Some(at);
        }
        best = Some(best.map_or(total, |b| b.max(total)));
        starts += 1;
        if starts == MAX_STARTS {
            break;
        }
    }
    best
}

// The packed forms answer exactly what the classic scorer answers, ASCII and mixed script alike.
#[test]
fn packed_forms_score_identically_to_the_classic_scorer() {
    let candidates = [
        "docs/work/bench-notes.txt",
        "Downloads/CleanShot at 18.25.25@2x.png",
        "CAFÉ-Notes.md",
        "SearchStrip.qml",
        "benches/İstanbul.txt",
        "notes/日本語-file.txt",
        "MiXeD/CaSe_PaTh-01.TXT",
        "café/MyFileName.txt",
    ];
    let queries = ["bench", "notes", "shot2x", "café", "strip", "stnbul", "nihon", "mixedcase", "mfn", "zzz", ""];
    for candidate in candidates {
        let packed = fold_packed(candidate);
        let hay = match &packed {
            Packed::Ascii(bytes) => Hay::Ascii(bytes),
            Packed::Wide(words) => Hay::Wide(words),
        };
        if candidate.is_ascii() {
            assert!(matches!(packed, Packed::Ascii(_)), "{candidate} packs to bytes");
        } else {
            assert!(matches!(packed, Packed::Wide(_)), "{candidate} packs to words");
        }
        for query in queries {
            let classic = classic_score(candidate, query);
            assert_eq!(Fuzzy::new(query).score_pre_folded(hay), classic, "{query} against {candidate} pre-folded");
            assert_eq!(score(candidate, query), classic, "{query} against {candidate} through score");
        }
    }
}
