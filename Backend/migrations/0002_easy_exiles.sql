CREATE TABLE "app"."identity_provider_credentials" (
	"ciphertext" "bytea" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"identity_id" uuid PRIMARY KEY NOT NULL,
	"key_version" text NOT NULL,
	"nonce" "bytea" NOT NULL,
	"tag" "bytea" NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "app"."identity_provider_credentials" ADD CONSTRAINT "identity_provider_credentials_identity_id_user_identities_id_fk" FOREIGN KEY ("identity_id") REFERENCES "app"."user_identities"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "identity_credentials_key_version_index" ON "app"."identity_provider_credentials" USING btree ("key_version");