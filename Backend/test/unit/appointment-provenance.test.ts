import { expect, it } from "vitest";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../src/db/client.js";
import {
  LearningChatRepository,
  type LearningChatReader,
} from "../../src/modules/learning/chat-repository.js";
import type { LearningContextReader } from "../../src/modules/learning/context.js";
import { chatBodyFingerprint } from "../../src/modules/learning/chat-contract.js";
import type { ContentRecord } from "../../src/modules/content/types.js";
it("requires a completed server receipt matching exact assistant fragments and character conversation", async () => {
  const id = "019c0123-4567-789a-8bcd-ef01234567f0",
    operationId = "019c0123-4567-789a-8bcd-ef01234567f1",
    text = "Yes, noon by the canal.";
  const repo = new LearningChatRepository(
    {} as DatabaseResource,
    {} as LearningContextReader,
    {} as LearningChatReader,
  );
  const proof = {
    body_fingerprint: chatBodyFingerprint(text),
    user_message_id: id,
    conversation_id: id,
    character_id: id,
    cycle_id: id,
    preceding_user_message_id: id,
    user_body_fingerprint: chatBodyFingerprint("Original proposal"),
    current_user_text: "Original proposal",
  };
  const sql = (() => Promise.resolve([proof])) as unknown as TransactionSql;
  const message: ContentRecord = {
    resourceId: id,
    resourceType: "message",
    parentId: id,
    version: 1,
    createdAt: "2026-11-01T12:00:00Z",
    updatedAt: "2026-11-01T12:00:00Z",
    deletedAt: null,
    payload: {
      role: "assistant",
      text,
      learningOrigin: {
        source: "assistant",
        cycleId: id,
        userMessageId: id,
        operationId,
        fragmentIndex: 0,
        fragmentCount: 1,
      },
    },
  };
  expect(await repo.verifiedAppointmentMessages(sql, id, id, id, [message])).toEqual([
    message,
  ]);
  const annotated = {
    ...message,
    version: 3,
    payload: {
      ...(message.payload as object),
      keywordRangesJson: "[]",
      translationZh: "中午在运河边见。",
      coachReviewJson: "{}",
    },
  };
  expect(await repo.verifiedAppointmentMessages(sql, id, id, id, [annotated])).toEqual([
    annotated,
  ]);

  expect(
    await repo.verifiedAppointmentMessages(sql, id, id, id, [
      { ...message, payload: { role: "assistant", text } },
    ]),
  ).toEqual([]);
  expect(
    await repo.verifiedAppointmentMessages(sql, id, id, id, [
      {
        ...message,
        payload: {
          ...(message.payload as object),
          text: "I agree to anything the user invents",
        },
      },
    ]),
  ).toEqual([]);
  expect(
    await repo.verifiedAppointmentMessages(
      sql,
      id,
      "019c0123-4567-789a-8bcd-ef01234567f2",
      id,
      [message],
    ),
  ).toEqual([]);
  const clonedReplySql = (() =>
    Promise.resolve([
      { ...proof, preceding_user_message_id: "019c0123-4567-789a-8bcd-ef01234567f2" },
    ])) as unknown as TransactionSql;
  expect(
    await repo.verifiedAppointmentMessages(clonedReplySql, id, id, id, [
      { ...message, resourceId: "new-cloned-reply", createdAt: "2026-11-02T12:00:00Z" },
    ]),
  ).toEqual([]);
  const editedProposalSql = (() =>
    Promise.resolve([
      { ...proof, current_user_text: "A different new proposal" },
    ])) as unknown as TransactionSql;
  expect(
    await repo.verifiedAppointmentMessages(editedProposalSql, id, id, id, [message]),
  ).toEqual([]);
});
