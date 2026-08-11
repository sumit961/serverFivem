CREATE TABLE `p_mdt_applications` (
  `id` int(11) NOT NULL,
  `applicant` longtext NOT NULL,
  `questions` longtext NOT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'pending',
  `timestamp` bigint(30) NOT NULL,
  `reviewer` longtext DEFAULT NULL,
  `reviewNote` varchar(300) DEFAULT NULL,
  `reviewedAt` bigint(30) DEFAULT NULL,
  `job` varchar(60) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_bolo` (
  `id` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `description` longtext NOT NULL,
  `target` longtext NOT NULL,
  `tags` longtext NOT NULL,
  `status` varchar(20) NOT NULL,
  `creator` longtext NOT NULL,
  `timestamp` bigint(30) NOT NULL,
  `expire` bigint(30) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_charges` (
  `name` varchar(60) NOT NULL,
  `charges` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_citizens` (
  `identifier` varchar(100) NOT NULL,
  `avatar` longtext DEFAULT NULL,
  `notes` longtext NOT NULL DEFAULT '[]'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_evidences` (
  `id` int(11) NOT NULL,
  `type` varchar(40) NOT NULL,
  `title` varchar(200) NOT NULL,
  `description` longtext NOT NULL,
  `location` varchar(100) NOT NULL,
  `itemData` longtext DEFAULT NULL,
  `mediaUrl` longtext NOT NULL,
  `creator` longtext NOT NULL,
  `history` longtext NOT NULL DEFAULT '[]',
  `status` varchar(30) NOT NULL DEFAULT 'undeposited',
  `timestamp` bigint(30) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_garage` (
  `id` int(11) NOT NULL,
  `vehicle` longtext NOT NULL,
  `job` varchar(60) NOT NULL,
  `status` varchar(10) NOT NULL,
  `grades` longtext NOT NULL DEFAULT '[]',
  `officers` longtext NOT NULL DEFAULT '[]',
  `licences` longtext NOT NULL DEFAULT '[]'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


CREATE TABLE `p_mdt_incidents` (
  `id` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `description` longtext NOT NULL,
  `tags` longtext NOT NULL,
  `creator` longtext NOT NULL,
  `timestamp` bigint(30) NOT NULL,
  `expire` bigint(30) DEFAULT NULL,
  `citizens` longtext DEFAULT NULL,
  `vehicles` longtext DEFAULT NULL,
  `status` varchar(15) NOT NULL DEFAULT 'open'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


CREATE TABLE `p_mdt_judgments` (
  `id` int(11) NOT NULL,
  `targets` longtext NOT NULL,
  `charges` longtext NOT NULL,
  `timestamp` bigint(30) NOT NULL,
  `officer` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_logs` (
  `id` int(11) NOT NULL,
  `identifier` varchar(100) NOT NULL,
  `category` varchar(60) NOT NULL,
  `action` varchar(60) NOT NULL,
  `message` varchar(300) NOT NULL,
  `name` varchar(200) NOT NULL,
  `timestamp` bigint(30) NOT NULL,
  `job` varchar(30) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


CREATE TABLE `p_mdt_officers` (
  `identifier` varchar(100) NOT NULL,
  `data` longtext DEFAULT NULL,
  `licences` longtext NOT NULL DEFAULT '[]'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_permissions` (
  `id` int(11) NOT NULL,
  `job` varchar(60) NOT NULL,
  `grade` varchar(60) NOT NULL,
  `permissions` longtext NOT NULL,
  `timestamp` bigint(30) NOT NULL,
  `modifiedBy` varchar(120) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_reports` (
  `id` int(11) NOT NULL,
  `title` varchar(200) NOT NULL,
  `type` varchar(50) NOT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'open',
  `content` longtext NOT NULL,
  `tags` longtext NOT NULL,
  `officers` longtext NOT NULL,
  `suspects` longtext NOT NULL,
  `civilians` longtext NOT NULL,
  `vehicles` longtext NOT NULL,
  `photos` longtext NOT NULL,
  `weapons` longtext NOT NULL,
  `evidences` longtext NOT NULL,
  `incidents` longtext NOT NULL,
  `warrants` longtext NOT NULL,
  `timestamp` bigint(30) NOT NULL,
  `creator` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_vehicles` (
  `plate` varchar(10) NOT NULL,
  `avatar` longtext DEFAULT NULL,
  `notes` longtext NOT NULL DEFAULT '[]',
  `photos` longtext NOT NULL DEFAULT '[]'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_warrants` (
  `id` int(11) NOT NULL,
  `type` varchar(60) NOT NULL,
  `title` varchar(200) NOT NULL,
  `content` longtext NOT NULL,
  `target` longtext NOT NULL,
  `location` varchar(200) DEFAULT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'active',
  `expire` bigint(30) DEFAULT NULL,
  `timestamp` bigint(30) NOT NULL,
  `creator` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `p_mdt_weapons` (
  `serial` varchar(30) NOT NULL,
  `model` varchar(100) NOT NULL,
  `owner` longtext NOT NULL,
  `timestamp` bigint(30) NOT NULL,
  `note` longtext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE `p_mdt_applications`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_bolo`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_charges`
  ADD PRIMARY KEY (`name`);

ALTER TABLE `p_mdt_citizens`
  ADD PRIMARY KEY (`identifier`);

ALTER TABLE `p_mdt_evidences`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_garage`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_incidents`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_judgments`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_logs`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_officers`
  ADD PRIMARY KEY (`identifier`);

ALTER TABLE `p_mdt_permissions`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_reports`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_vehicles`
  ADD PRIMARY KEY (`plate`);

ALTER TABLE `p_mdt_warrants`
  ADD PRIMARY KEY (`id`);

ALTER TABLE `p_mdt_weapons`
  ADD PRIMARY KEY (`serial`);

ALTER TABLE `p_mdt_applications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `p_mdt_bolo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `p_mdt_evidences`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `p_mdt_garage`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `p_mdt_incidents`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `p_mdt_judgments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `p_mdt_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `p_mdt_permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `p_mdt_reports`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `p_mdt_warrants`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;
