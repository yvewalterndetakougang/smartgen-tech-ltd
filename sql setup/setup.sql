-- =====================================================================
-- SmartGen Tech Ltd : configuration COMPLÈTE de la base de données
-- À coller en entier dans Supabase > SQL Editor > New query > Run
-- Peut être relancé sans risque (aucune donnée n'est effacée).
-- =====================================================================

-- 1. Fonction : "cette personne est-elle l'administrateur ?"
create or replace function public.is_admin() returns boolean
language sql stable as $$
  select coalesce((auth.jwt() ->> 'email') = 'smartgentechltd@gmail.com', false)
$$;

-- 2. Messages reçus par le formulaire de contact
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  nom text not null check (char_length(nom) between 1 and 120),
  telephone text not null check (char_length(telephone) between 1 and 40),
  email text check (email is null or char_length(email) <= 200),
  service text check (service is null or char_length(service) <= 100),
  budget text check (budget is null or char_length(budget) <= 100),
  message text not null check (char_length(message) between 1 and 3000),
  traite boolean not null default false
);
alter table public.messages
  add column if not exists user_id uuid references auth.users(id) on delete set null;

-- 3. Projets
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  client text not null,
  titre text not null,
  type text,
  montant numeric not null default 0,
  statut text not null default 'À démarrer'
);
alter table public.projects
  add column if not exists client_id uuid references auth.users(id) on delete set null;
alter table public.projects
  add column if not exists devise text not null default 'FCFA' check (devise in ('FCFA','USD','EUR'));

-- 4. Profils des clients (remplis automatiquement à l'inscription)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  nom text,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, nom)
  values (new.id, new.email, left(coalesce(new.raw_user_meta_data ->> 'nom', ''), 120))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

insert into public.profiles (id, email)
  select id, email from auth.users on conflict (id) do nothing;

-- 5. Sécurité : activer les règles d'accès
alter table public.messages enable row level security;
alter table public.projects enable row level security;
alter table public.profiles enable row level security;

-- Nettoyage des anciennes règles
drop policy if exists "visiteurs envoient un message" on public.messages;
drop policy if exists "envoi de message" on public.messages;
drop policy if exists "admin lit les messages" on public.messages;
drop policy if exists "admin modifie les messages" on public.messages;
drop policy if exists "admin supprime les messages" on public.messages;
drop policy if exists "client lit ses messages" on public.messages;
drop policy if exists "admin gere les projets" on public.projects;
drop policy if exists "client lit ses projets" on public.projects;
drop policy if exists "lecture des profils" on public.profiles;

-- Messages : tout le monde peut en ENVOYER, personne ne peut lire ceux des autres
create policy "envoi de message" on public.messages
  for insert to anon, authenticated
  with check (traite = false and (user_id is null or user_id = auth.uid()));

create policy "admin lit les messages" on public.messages
  for select to authenticated using (public.is_admin());
create policy "admin modifie les messages" on public.messages
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin supprime les messages" on public.messages
  for delete to authenticated using (public.is_admin());
create policy "client lit ses messages" on public.messages
  for select to authenticated using (user_id = auth.uid());

-- Projets : l'admin gère tout, un client voit seulement les siens
create policy "admin gere les projets" on public.projects
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "client lit ses projets" on public.projects
  for select to authenticated using (client_id = auth.uid());

-- Profils : chacun voit le sien, l'admin voit tous
create policy "lecture des profils" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());