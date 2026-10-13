#!/usr/bin/env python3
"""Current review after degree-range repairs and source14 alternatives."""
import validate_firstrelease_v0_11 as previous

if __name__ == '__main__':
    previous.core.author_evidence_count = previous.previous.current.author_evidence_count
    previous.core.DEFAULT = previous.core.BASE / 'FirstRelease/review-index-v0.13.json'
    previous.core.check = previous.check
    raise SystemExit(previous.core.main())
