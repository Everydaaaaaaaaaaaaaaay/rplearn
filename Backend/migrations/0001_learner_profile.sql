CREATE TYPE "app"."learning_goal" AS ENUM('dailyConversation', 'travel', 'school', 'exam', 'studyAbroad', 'work', 'culture');--> statement-breakpoint
CREATE TYPE "app"."proficiency_source" AS ENUM('selfReported', 'placement');--> statement-breakpoint
CREATE TYPE "app"."study_stage" AS ENUM('primary', 'juniorHigh', 'seniorHigh', 'university', 'postgraduate', 'working', 'other');--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD COLUMN "has_completed_profile_setup" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD COLUMN "learning_goal" "app"."learning_goal" DEFAULT 'dailyConversation' NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD COLUMN "placement_completed_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD COLUMN "placement_score" integer;--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD COLUMN "proficiency_source" "app"."proficiency_source" DEFAULT 'selfReported' NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD COLUMN "study_stage" "app"."study_stage";--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD CONSTRAINT "user_profiles_placement_score_range" CHECK ("app"."user_profiles"."placement_score" is null or "app"."user_profiles"."placement_score" between 0 and 100);