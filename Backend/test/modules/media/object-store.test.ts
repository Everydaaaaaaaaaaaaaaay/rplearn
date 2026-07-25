import { describe, expect, it } from "vitest";
import { loadConfig } from "../../../src/config/env.js";
import { createMediaObjectStore } from "../../../src/modules/media/object-store.js";
import { newEntityId } from "../../../src/shared/id.js";

describe("MediaObjectStore", () => {
  it("signs exact upload length and type while hoisting integrity metadata", async () => {
    const store = createMediaObjectStore(
      loadConfig({
        MEDIA_S3_ACCESS_KEY_ID: "test-access",
        MEDIA_S3_BUCKET: "private-test",
        MEDIA_S3_ENDPOINT: "http://127.0.0.1:9000",
        MEDIA_S3_FORCE_PATH_STYLE: "true",
        MEDIA_S3_SECRET_ACCESS_KEY: "test-secret",
        MEDIA_STORAGE_ENABLED: "true",
        NODE_ENV: "test",
      }),
    );
    const objectKey = `${newEntityId()}/${newEntityId()}`;
    const checksum = "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=";

    const upload = await store.createUploadUrl(
      {
        byteSize: 1234,
        checksumSha256: checksum,
        contentType: "audio/x-caf",
        objectKey,
      },
      300,
    );
    const url = new URL(upload.url);

    expect(url.pathname).toBe(`/private-test/${objectKey}`);
    expect(url.searchParams.get("X-Amz-SignedHeaders")).toBe(
      "content-length;content-type;host",
    );
    expect(url.searchParams.get("x-amz-checksum-sha256")).toBe(checksum);
    expect(url.searchParams.get("x-amz-meta-sha256")).toBe(checksum);
    expect(upload.headers).toEqual({
      "content-length": "1234",
      "content-type": "audio/x-caf",
    });
  });
});
