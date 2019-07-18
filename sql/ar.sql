--
-- PostgreSQL database dump
--

-- Dumped from database version 11.4
-- Dumped by pg_dump version 11.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: pages; Type: TABLE; Schema: public; Owner: gd
--

CREATE TABLE public.pages (
    id integer NOT NULL,
    user_id integer NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE public.pages OWNER TO gd;

--
-- Name: pages_id_seq; Type: SEQUENCE; Schema: public; Owner: gd
--

CREATE SEQUENCE public.pages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.pages_id_seq OWNER TO gd;

--
-- Name: pages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gd
--

ALTER SEQUENCE public.pages_id_seq OWNED BY public.pages.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: gd
--

CREATE TABLE public.users (
    id integer NOT NULL,
    fname character varying,
    lname character varying
);


ALTER TABLE public.users OWNER TO gd;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: gd
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO gd;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gd
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: pages id; Type: DEFAULT; Schema: public; Owner: gd
--

ALTER TABLE ONLY public.pages ALTER COLUMN id SET DEFAULT nextval('public.pages_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: gd
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Data for Name: pages; Type: TABLE DATA; Schema: public; Owner: gd
--

COPY public.pages (id, user_id, name) FROM stdin;
2	1	Perl6
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: gd
--

COPY public.users (id, fname, lname) FROM stdin;
1	Greg	Donald
\.


--
-- Name: pages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: gd
--

SELECT pg_catalog.setval('public.pages_id_seq', 2, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: gd
--

SELECT pg_catalog.setval('public.users_id_seq', 1, true);


--
-- Name: pages pages_pkey; Type: CONSTRAINT; Schema: public; Owner: gd
--

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: gd
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: pages fk_user_id; Type: FK CONSTRAINT; Schema: public; Owner: gd
--

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT fk_user_id FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

