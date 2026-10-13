#!/usr/bin/env python3
"""Use v0.7 author/image/group checks for the additional grade8 narrative family."""
import validate_firstrelease_v0_7 as current

if __name__ == '__main__':
    current.core.author_evidence_count = current.author_evidence_count
    current.core.DEFAULT = current.core.BASE / 'FirstRelease/review-index-v0.8.json'
    current.core.check = current.check
    raise SystemExit(current.core.main())
