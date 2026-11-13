# EFATA API

The Android app and admin dashboard use https://api.efata.io. Authentication is handled through the API with Supabase Auth. Application records live in the private EFATA PostgreSQL schema.

Configure the server using .env.example, apply the SQL migrations in order, and run npm test. For local API development, run npm start. Provision administrator roles only through a trusted database operator, never through public registration.
