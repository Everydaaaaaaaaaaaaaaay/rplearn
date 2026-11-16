import {
  getDefaultAutoSelectFamilyAttemptTimeout,
  setDefaultAutoSelectFamilyAttemptTimeout,
} from "node:net";

export function configureOutboundNetworking(): void {
  // Node's 250ms address-selection window can expire before a cross-region TCP
  // handshake finishes. Keep route-level request deadlines as the outer bound.
  setDefaultAutoSelectFamilyAttemptTimeout(
    Math.max(1500, getDefaultAutoSelectFamilyAttemptTimeout()),
  );
}
