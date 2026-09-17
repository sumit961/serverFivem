ALTER TABLE `users` 
ADD COLUMN `electrician_panels` int(11) NOT NULL DEFAULT 0,
ADD COLUMN `electrician_plates` int(11) NOT NULL DEFAULT 0,
ADD COLUMN `electrician_level` int(11) NOT NULL DEFAULT 1;
