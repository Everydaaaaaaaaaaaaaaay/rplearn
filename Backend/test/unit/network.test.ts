import {
  getDefaultAutoSelectFamilyAttemptTimeout,
  setDefaultAutoSelectFamilyAttemptTimeout,
} from "node:net";
import { afterEach, describe, expect, it } from "vitest";
import { configureOutboundNetworking } from "../../src/infrastructure/network.js";

const initialTimeout = getDefaultAutoSelectFamilyAttemptTimeout();
afterEach(() => setDefaultAutoSelectFamilyAttemptTimeout(initialTimeout));

describe("outbound connection address selection", () => {
  it("allows cross-region connections longer than the Node 250ms default", () => {
    setDefaultAutoSelectFamilyAttemptTimeout(250);
    configureOutboundNetworking();
    expect(getDefaultAutoSelectFamilyAttemptTimeout()).toBe(1500);
  });

  it("preserves a deliberately longer operator-supplied timeout", () => {
    setDefaultAutoSelectFamilyAttemptTimeout(3000);
    configureOutboundNetworking();
    expect(getDefaultAutoSelectFamilyAttemptTimeout()).toBe(3000);
  });
});
