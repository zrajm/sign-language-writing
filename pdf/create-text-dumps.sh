#!/bin/zsh
#
# Usage: ./create-text-dumps.sh
#
# Generate text dumps (using `pdfgrep`) of all found pdf files. These text
# dumps can be used for faster searching (with `grep`).
#

emulate -RL zsh
set -eu

out() { printf '%s\n' "$@"; }

out "Removing any orphaned text dumps..."
for TXTFILE in **/.*.txt(.N); do
    PDFFILE="${TXTFILE:h}/${${TXTFILE:t:r}#.}.pdf"
    # If text file doesn't have a corresponding PDF, delete the text file.
    [[ -e "$PDFFILE" ]] || rm --verbose --force "$TXTFILE"
done

out "Creating/updating text dumps..."
for PDFFILE in **/*.pdf; do
    TXTFILE="${PDFFILE:h}/.${PDFFILE:t:r}.txt"

    # If PDF is symlink, link to original's text dump file.
    if [[ -L $PDFFILE ]]; then
        if [[ ! -L $TXTFILE ]]; then
            PDFLINK=`readlink $PDFFILE`
            TXTLINK="${PDFLINK:h}/.${PDFLINK:t:r}.txt"
            out "linking $TXTLINK -> $TXTFILE"
            ln --force --symbolic $TXTLINK $TXTFILE
        fi
        continue
    fi

    # Otherwise, create (or overwrite old) dump file.
    if [[ "$TXTFILE" -ot "$PDFFILE" ]]; then
        out "updating $TXTFILE"
    elif [[ ! -f "$TXTFILE" ]]; then
        out "creating $TXTFILE"
    else
        continue
    fi
    # Extract all text strings, remove squeeze multiple space into one.
    pdfgrep --only-matching '.*' "$PDFFILE" | \
        perl -Mutf8 -C -pe 's#[\s[:cntrl:]\cL\p{XPosixCntrl}]+(?!(?<=\n)$)# #g' >"$TXTFILE"
done

#[eof]
