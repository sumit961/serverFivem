-- ============================================================
-- cm-family | 019_family_event_engine_stabilization.sql
-- Family Event Engine — Phase 1.1 Stabilization
-- Additive settlement fields for cm_family_event_instances
-- ============================================================

ALTER TABLE `cm_family_event_instances`
  ADD COLUMN IF NOT EXISTS `reward_state` VARCHAR(32) NOT NULL DEFAULT 'not_applicable' AFTER `metadata`,
  ADD COLUMN IF NOT EXISTS `reward_processing_at` TIMESTAMP NULL DEFAULT NULL AFTER `reward_state`,
  ADD COLUMN IF NOT EXISTS `reward_delivered_at` TIMESTAMP NULL DEFAULT NULL AFTER `reward_processing_at`,
  ADD COLUMN IF NOT EXISTS `reward_metadata` LONGTEXT NULL AFTER `reward_delivered_at`,
  ADD KEY IF NOT EXISTS `idx_evt_reward_state` (`reward_state`);
