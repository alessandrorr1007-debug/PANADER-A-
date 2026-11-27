-- Extension to the disposable Auth mock only; real Supabase already has these objects.
alter table auth.users add column email text;
create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id));
create function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('session_id',nullif(current_setting('request.jwt.claim.session_id',true),'')) $$;
grant execute on function auth.jwt() to authenticated,anon;
