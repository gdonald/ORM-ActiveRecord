
CREATE TABLE users (
  id serial,
  fname character varying,
  lname character varying
);

CREATE TABLE pages (
  id serial,
  user_id integer NOT NULL,
  name character varying NOT NULL
);

ALTER TABLE ONLY pages
  ADD CONSTRAINT pages_pkey PRIMARY KEY (id);

ALTER TABLE ONLY users
  ADD CONSTRAINT users_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pages
  ADD CONSTRAINT fk_user_id
  FOREIGN KEY (user_id)
  REFERENCES users(id);
