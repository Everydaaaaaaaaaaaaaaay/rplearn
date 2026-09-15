-- 辅助任务预算独立配置，复用已有倍率版本、幂等命令和变更审计。
ALTER TABLE app.credit_rate_policy
  ADD COLUMN auxiliary_rate_units integer NOT NULL DEFAULT 10000
  CHECK (auxiliary_rate_units BETWEEN 0 AND 1000000);
