APrameyah Learning Impact Platform V4 — cloud-ready MVP

This package is designed to connect to the Supabase project created for Aprameyah.

Files:
- index.html — web application
- supabase_setup.sql — security policies + participant access functions

IMPORTANT:
1. Run supabase_setup.sql in Supabase SQL Editor after the existing schema.
2. Create one Admin user in Supabase Authentication > Users > Add user.
3. Open index.html locally for testing, enter the Supabase Project URL and Publishable Key on the Setup screen.
4. Sign in with the Admin user.
5. Use the Admin area to create clients, programs, modules, questions and participants.
6. Participant links are token based and use a Supabase RPC function; admin tables remain protected by RLS.

For production deployment, the app should be hosted over HTTPS and the Supabase publishable key may be embedded in the frontend. Never expose a database password, service_role key or secret key.

This is an MVP. Before real client data is used, add audit logging, stronger token expiry/rotation, email delivery, backups, privacy/retention controls and a production deployment review.
