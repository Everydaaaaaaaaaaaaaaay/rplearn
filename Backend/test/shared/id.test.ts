import { describe, expect, it } from "vitest";
import { entityIdSchema, newEntityId } from "../../src/shared/id.js";

describe("entity identifiers", () => {
  it("creates sortable UUIDv7 identifiers", () => {
    const identifier = newEntityId();

    expect(entityIdSchema.parse(identifier)).toBe(identifier);
    expect(identifier.at(14)).toBe("7");
  });
});
