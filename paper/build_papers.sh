#!/usr/bin/env bash
# Ordered build for the bidirectional xr-hyper cross-references:
# main.tex reads appendix.aux (prefix A-) and appendix.tex reads main.aux
# (prefix M-), so each document must be compiled against a current .aux of
# the other. Single-document latexmk runs leave visible '??' in the PDFs.
# Fails loudly if any unresolved reference survives the full sequence.
set -euo pipefail
cd "$(dirname "$0")"

run() { pdflatex -interaction=nonstopmode -halt-on-error "$1" > /dev/null; }

run main.tex          # main.aux for the appendix's M- refs
run appendix.tex      # appendix.aux for main's A- refs
run main.tex          # resolve A- refs
bibtex main > /dev/null || true
run appendix.tex      # resolve M- refs against final main.aux
run main.tex          # settle bibliography + page numbers
run main.tex
run appendix.tex

fail=0
for pdf in main.pdf appendix.pdf; do
    n=$(pdftotext "$pdf" - 2>/dev/null | grep -c '??' || true)
    if [ "$n" -gt 0 ]; then
        echo "FAIL: $pdf contains $n unresolved '??' reference(s)" >&2
        fail=1
    else
        echo "OK: $pdf has no unresolved references"
    fi
done
exit $fail
