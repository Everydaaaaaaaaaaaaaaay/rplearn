UPDATE "app"."regions"
SET "is_active" = false
WHERE "id" IN ('reykjavik', 'lisbon', 'tokyo');--> statement-breakpoint

INSERT INTO "app"."regions" ("id", "country_code", "name_en", "name_zh", "is_active")
VALUES
	('toronto', 'CA', 'Toronto', '多伦多', true),
	('sydney', 'AU', 'Sydney', '悉尼', true),
	('neworleans', 'US', 'New Orleans', '新奥尔良', true),
	('manchester', 'GB', 'Manchester', '曼彻斯特', true),
	('kingston', 'JM', 'Kingston', '金斯敦', true)
ON CONFLICT ("id") DO UPDATE
SET
	"country_code" = EXCLUDED."country_code",
	"name_en" = EXCLUDED."name_en",
	"name_zh" = EXCLUDED."name_zh",
	"is_active" = true;--> statement-breakpoint
