-- CI only: extend disposable Auth mock, never install in Supabase.
create table auth.mfa_factors(id uuid primary key,user_id uuid not null references auth.users(id),status text not null,factor_type text not null default 'totp');
create or replace function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('session_id',nullif(current_setting('request.jwt.claim.session_id',true),''),'aal',coalesce(nullif(current_setting('request.jwt.claim.aal',true),''),'aal1')) $$;
