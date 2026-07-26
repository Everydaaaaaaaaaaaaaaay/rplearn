ALTER TABLE "app"."user_profiles" ADD COLUMN "starter_region_id" text;--> statement-breakpoint
INSERT INTO "app"."regions" ("id", "country_code", "name_en", "name_zh")
VALUES
	('capetown', 'ZA', 'Cape Town', '开普敦'),
	('singapore', 'SG', 'Singapore', '新加坡'),
	('dublin', 'IE', 'Dublin', '都柏林'),
	('edinburgh', 'GB', 'Edinburgh', '爱丁堡'),
	('vancouver', 'CA', 'Vancouver', '温哥华'),
	('auckland', 'NZ', 'Auckland', '奥克兰'),
	('nairobi', 'KE', 'Nairobi', '内罗毕'),
	('reykjavik', 'IS', 'Reykjavík', '雷克雅未克'),
	('lisbon', 'PT', 'Lisbon', '里斯本'),
	('tokyo', 'JP', 'Tokyo', '东京')
ON CONFLICT ("id") DO UPDATE
SET "country_code" = EXCLUDED."country_code",
	"name_en" = EXCLUDED."name_en",
	"name_zh" = EXCLUDED."name_zh";--> statement-breakpoint
UPDATE "app"."user_profiles"
SET "starter_region_id" = CASE
	WHEN "current_region_id" IN ('london', 'melbourne', 'newyork') THEN "current_region_id"
	ELSE 'london'
END
WHERE "has_completed_onboarding" = true;--> statement-breakpoint
DELETE FROM "app"."region_unlocks"
WHERE "source" = 'initial'
	AND "user_id" IN (
		SELECT "user_id"
		FROM "app"."user_profiles"
		WHERE "has_completed_onboarding" = false
	);--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD CONSTRAINT "user_profiles_starter_region_id_regions_id_fk" FOREIGN KEY ("starter_region_id") REFERENCES "app"."regions"("id") ON DELETE no action ON UPDATE no action;
