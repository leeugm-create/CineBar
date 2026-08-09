CREATE TABLE `page_visits` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`ts` integer NOT NULL,
	`path` text NOT NULL,
	`country` text DEFAULT '--' NOT NULL,
	`ip_hash` text NOT NULL,
	`locale` text DEFAULT 'zh-Hans' NOT NULL
);
