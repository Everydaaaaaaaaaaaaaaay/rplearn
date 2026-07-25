export type MediaPurpose = "voice_message";
export type MediaStatus = "pending" | "ready" | "deleted";

export type MediaAsset = Readonly<{
  byteSize: number;
  checksumSha256: string;
  contentType: string;
  createdAt: string;
  deletedAt: string | null;
  id: string;
  pendingExpiresAt: string;
  purpose: MediaPurpose;
  readyAt: string | null;
  status: MediaStatus;
}>;

export type InternalMediaAsset = MediaAsset &
  Readonly<{
    objectKey: string;
    purgedAt: string | null;
    userId: string;
  }>;

export type MediaUploadReservation = Readonly<{
  asset: MediaAsset;
  upload: Readonly<{
    expiresAt: string;
    headers: Readonly<Record<string, string>>;
    method: "PUT";
    url: string;
  }> | null;
}>;

export type MediaDownload = Readonly<{
  asset: MediaAsset;
  download: Readonly<{
    expiresAt: string;
    url: string;
  }>;
}>;
