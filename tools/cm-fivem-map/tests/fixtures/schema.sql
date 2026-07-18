-- Fixture schema for cm-fivem-map tests.

CREATE TABLE IF NOT EXISTS fixture_items (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(64) NOT NULL
);

CREATE TABLE fixture_events (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(64) NOT NULL,
    ts INT NOT NULL,
    item_id INT,
    FOREIGN KEY (item_id) REFERENCES fixture_items(id)
);

ALTER TABLE fixture_events ADD COLUMN note VARCHAR(255);

-- comment: DROP TABLE fixture_items; (must be ignored, this is a comment)
