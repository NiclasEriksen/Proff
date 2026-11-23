#!/usr/bin/env bash
# The changelog players read on CurseForge and GitHub, as the release workflow writes it:
#   tools/changelog.sh                 HEAD since the newest tag: a preview before tagging
#   tools/changelog.sh v0.9.0          that tag since the one before it (release.yml runs this)
#   tools/changelog.sh v0.9.0 v0.8.2   from a given tag
#   tools/changelog.sh --draft v0.10.0 writes COMMIT.md: the lines since the newest tag, for you to edit; run again,
#                                      it adds only the commits since (your edits stay), --force writes it anew
#
# COMMIT.md (2026-11-22, the user: "for a release, I should have a COMMIT.md file that includes the lines for me to
# edit"): the release's changelog as you want players to read it. --draft writes it from the commit subjects; you
# reword, merge, reorder or drop lines, and commit it before tagging. When it's for the tag being released (its
# first line "# Proff vX.Y.Z"), that file is the changelog, word for word (its <!-- --> lines left out);
# else the subjects, as before.
# One line per commit subject (they're written for players), without the developer-only ones (Tests:,
# Tidy-up:, Notes:, Docs:, Developer probe), a subject's {{...}} as ***** and .github/changelog-fix.txt's
# rewordings (a pushed subject that gave a secret away), the Claude credit once at the top.

# (Dyreparken's copy also warns about easter-egg giveaways; Proff has nothing secret, so that part is left out.)
set -euo pipefail
cd "$(dirname "$0")/.."
draft=""
if [[ ${1:-} == --draft ]]; then
    draft="${2:?--draft needs the version, e.g. v0.10.0}"
    [[ $draft =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta)[0-9]+)?$ ]] || { echo "not a version: $draft" >&2; exit 1; }
    since=""
    if [[ -f COMMIT.md ]] && head -1 COMMIT.md | grep -qxF "# Proff $draft" && [[ ${3:-} != --force ]]; then
        since=$(sed -n 's/^<!-- through \([0-9a-f]*\) -->$/\1/p' COMMIT.md)
        [[ -n $since ]] || { echo "COMMIT.md has no '<!-- through <commit> -->' line: --force writes it anew" >&2; exit 1; }
    fi
    shift 2
    if [[ -n $since ]]; then set -- HEAD "$since"; else set -- HEAD; fi
fi
tag="${1:-HEAD}"
if [[ $# -ge 2 ]]; then
    prev="$2"
else
    prev=$(git describe --tags --abbrev=0 "${tag}^" 2>/dev/null || true)
fi
title="$tag"
[[ $tag == HEAD ]] && title="(unreleased, since ${prev:-the start})"

lines=$(git log --no-merges --format='%H %s' ${prev:+"$prev.."}"$tag" \
    | while read -r sha subject; do
        fix=$(grep -m1 "^$sha " .github/changelog-fix.txt 2>/dev/null | cut -d' ' -f2- || true)
        echo "- ${fix:-$subject}"
    done \
    | grep -vE '^- (Tests|Tidy-up|Notes|Docs|Developer probe)\b' \
    | sed -E 's/\{\{[^}]*\}\}/*****/g' || true)

if [[ -n $draft && -n $since ]]; then
    head=$(git rev-parse HEAD)
    if [[ -n $lines ]]; then
        # (the new lines go after the last "- " line: your order and edits above stay)
        last=$(grep -n '^- ' COMMIT.md | tail -1 | cut -d: -f1)
        { head -n "${last:-$(wc -l < COMMIT.md)}" COMMIT.md; echo "$lines"; tail -n +"$(( ${last:-$(wc -l < COMMIT.md)} + 1 ))" COMMIT.md; } > COMMIT.md.new
        mv COMMIT.md.new COMMIT.md
    fi
    sed -i "s/^<!-- through [0-9a-f]* -->$/<!-- through $head -->/" COMMIT.md
    echo "COMMIT.md for $draft: $(grep -c . <<<"${lines}" || true) new line(s) added" >&2
elif [[ -n $draft ]]; then
    {
        echo "# Proff $draft"
        echo
        echo "<!-- The changelog players read for $draft (CurseForge, GitHub). Edit freely: reword, merge, reorder, drop. -->"
        echo "<!-- Lines like this one are left out. Commit it before tagging: release.yml uses it for $draft as written. -->"
        echo "<!-- through $(git rev-parse HEAD) -->"
        echo
        echo "_Developed with the help of Claude (Anthropic)._"
        echo
        echo "${lines:-- Small fixes and polish.}"
    } > COMMIT.md
    echo "COMMIT.md written for $draft ($(grep -c '^- ' COMMIT.md) lines)" >&2
elif [[ $tag != HEAD && -f COMMIT.md ]] && head -1 COMMIT.md | grep -qxF "# Proff $tag"; then
    grep -v '^<!--.*-->$' COMMIT.md | cat -s
    lines=$(grep '^- ' COMMIT.md || true)
else
    echo "# Proff ${title}"
    echo
    echo "_Developed with the help of Claude (Anthropic)._"
    echo
    echo "${lines:-- Small fixes and polish.}"
fi
