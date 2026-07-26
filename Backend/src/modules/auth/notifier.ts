import nodemailer, { type Transporter } from "nodemailer";
import type { RuntimeConfig } from "../../config/env.js";

export type AuthNotifier = Readonly<{
  sendEmailVerification: (email: string, token: string) => Promise<void>;
  sendPasswordReset: (email: string, token: string) => Promise<void>;
}>;

export type SmtpAuthNotifier = AuthNotifier &
  Readonly<{
    verify: () => Promise<void>;
  }>;

function buildActionUrl(baseUrl: string, action: string, token: string): string {
  const url = new URL(`${baseUrl.replace(/\/$/, "")}/${action}`);
  url.searchParams.set("token", token);
  return url.toString();
}

export function createSmtpAuthNotifier(config: RuntimeConfig): SmtpAuthNotifier {
  const auth =
    config.smtpUser === undefined || config.smtpPassword === undefined
      ? undefined
      : {
          pass: config.smtpPassword,
          user: config.smtpUser,
        };
  const transporter: Transporter = nodemailer.createTransport({
    ...(auth === undefined ? {} : { auth }),
    host: config.smtpHost,
    port: config.smtpPort,
    secure: config.smtpSecure,
  });

  return {
    sendEmailVerification: async (email, token) => {
      const url = buildActionUrl(config.authActionUrlBase, "verify-email", token);
      await transporter.sendMail({
        from: config.authEmailFrom,
        subject: "Verify your LingoTrip email",
        text: `Open this link to verify your LingoTrip email:\n\n${url}\n\nIf you did not create this account, you can ignore this message.`,
        to: email,
      });
    },
    sendPasswordReset: async (email, token) => {
      const url = buildActionUrl(config.authActionUrlBase, "reset-password", token);
      await transporter.sendMail({
        from: config.authEmailFrom,
        subject: "Reset your LingoTrip password",
        text: `Open this link to reset your LingoTrip password:\n\n${url}\n\nIf you did not request this, you can ignore this message.`,
        to: email,
      });
    },
    verify: async () => {
      await transporter.verify();
    },
  };
}
