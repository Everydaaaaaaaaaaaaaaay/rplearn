#!/usr/bin/env python3
"""Plan fixed-size zero-error audits under an explicitly assumed binomial model.

This is arithmetic for hypothetical IID binary trials, never admission evidence.
Do not count related items, retries or model repeats as independent observations.
"""
import argparse
import json
import math


def integer(value, name):
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise ValueError(f'{name} must be a positive integer')


def zero_error_upper(trials, alpha):
    integer(trials, 'trials')
    if not math.isfinite(alpha) or not 0 < alpha < 1:
        raise ValueError('alpha must be finite and strictly between0and1')
    return -math.expm1(math.log(alpha) / trials)


def plan(target_error_rate, confidence=0.95, simultaneous_claims=1, illustrative_trials=None):
    integer(simultaneous_claims, 'simultaneous_claims')
    for value, name in [(target_error_rate, 'target_error_rate'), (confidence, 'confidence')]:
        if not math.isfinite(value) or not 0 < value < 1:
            raise ValueError(f'{name} must be finite and strictly between0and1')
    alpha = (1 - confidence) / simultaneous_claims
    if alpha == 0:
        raise ValueError('Per-claim alpha underflowed; precision not supported')
    required = max(1, math.ceil(math.log(alpha) / math.log1p(-target_error_rate)))
    # Floating-point boundary correction, not a change to the requested threshold.
    while zero_error_upper(required, alpha) > target_error_rate:
        required += 1
    while required > 1 and zero_error_upper(required - 1, alpha) <= target_error_rate:
        required -= 1
    current_bound = None if illustrative_trials is None else zero_error_upper(illustrative_trials, alpha)
    return dict(method='one_sided_exact_binomial_zero_errors',
                target_error_rate=target_error_rate, confidence=confidence,
                simultaneous_claims=simultaneous_claims,
                multiplicity='Bonferroni alpha/claims; no across-claim independence required',
                per_claim_alpha=alpha, required_independent_trials_per_claim=required,
                bound_at_required_trials=zero_error_upper(required, alpha),
                illustrative_zero_error_trials=illustrative_trials,
                illustrative_upper_bound=current_bound,
                assumptions=['Fixed sample and thresholds chosen before results',
                             'Independent identical binary trials within each claim',
                             'Correct adjudicated truth and representative defined population',
                             'Zero observed errors; other error counts need a different calculation'],
                production_admission=False,
                limitation='Hypothetical planning only; no experiment, independence, fairness, power or educational validity established')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target-error-rate', type=float, required=True)
    parser.add_argument('--confidence', type=float, default=0.95)
    parser.add_argument('--simultaneous-claims', type=int, default=1)
    parser.add_argument('--illustrative-trials', type=int)
    args = parser.parse_args()
    try:
        result = plan(args.target_error_rate, args.confidence, args.simultaneous_claims, args.illustrative_trials)
    except ValueError as exc:
        parser.error(str(exc))
    print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
