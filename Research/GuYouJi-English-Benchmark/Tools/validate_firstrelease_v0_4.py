#!/usr/bin/env python3
"""Use frozen v0.3 checks with the v0.4 language-variant index by default."""
import validate_firstrelease_v0_3 as core

if __name__ == '__main__':
    core.DEFAULT = core.BASE / 'FirstRelease/review-index-v0.4.json'
    raise SystemExit(core.main())
