-- Meta: let Meta match app installs (and later events) to the ad click.
--
-- Ads Manager showed "—" installs although Meta accepted every AppInstall
-- event: the events carried no click data Meta could match. The Play Store
-- install referrer of an ad install holds Meta's own encrypted click data
-- (utm_content={"app":...,"source":{"data":...,"nonce":...}}). It is now
-- sent as app_data.install_referrer, with installer_package
-- com.android.vending, as the Conversions API for App Events documents.
-- Nothing else in the event changes.

create or replace function public.meta_event_payload(e public.meta_events, s public.meta_settings)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_email text;
  v_user  jsonb := '{}'::jsonb;
  v_ev    jsonb;
  v_inst  public.installs;
  v_click public.ad_clicks;
  v_ip    text;
  v_ua    text;
  v_app   jsonb;
begin
  if e.ad_click_id is not null then
    select * into v_click from public.ad_clicks where id = e.ad_click_id;
  end if;
  select * into v_inst from public.installs i
   where i.install_id = coalesce(
           e.install_id,
           (select coalesce(ua.last_touch_install_id, ua.first_touch_install_id)
              from public.user_attribution ua where ua.user_id = e.user_id),
           (select i2.install_id from public.installs i2 where i2.first_user_id = e.user_id
             order by i2.created_at desc limit 1));
  if v_click.id is null and v_inst.ad_click_id is not null then
    select * into v_click from public.ad_clicks where id = v_inst.ad_click_id;
  end if;

  if e.user_id is not null then
    select email into v_email from auth.users where id = e.user_id;
    v_user := jsonb_build_object('external_id', jsonb_build_array(public.meta_sha256(e.user_id::text)));
    if v_email is not null then
      v_user := v_user || jsonb_build_object('em', jsonb_build_array(public.meta_sha256(v_email)));
    end if;
  elsif e.install_id is not null then
    v_user := jsonb_build_object('external_id', jsonb_build_array(public.meta_sha256(e.install_id::text)));
  elsif v_click.id is not null then
    v_user := jsonb_build_object('external_id', jsonb_build_array(public.meta_sha256(v_click.id::text)));
  end if;
  v_user := v_user || jsonb_build_object('country', jsonb_build_array(public.meta_sha256('in')));

  v_ip := coalesce(e.client_ip, v_click.client_ip, v_inst.client_ip);
  v_ua := coalesce(v_click.user_agent, e.user_agent, v_inst.user_agent);
  if coalesce(v_click.fbc, v_inst.fbc) is not null then
    v_user := v_user || jsonb_build_object('fbc', coalesce(v_click.fbc, v_inst.fbc));
  end if;
  if coalesce(v_click.fbp, v_inst.fbp) is not null then
    v_user := v_user || jsonb_build_object('fbp', coalesce(v_click.fbp, v_inst.fbp));
  end if;
  if v_ip is not null then v_user := v_user || jsonb_build_object('client_ip_address', v_ip); end if;
  if v_ua is not null then v_user := v_user || jsonb_build_object('client_user_agent', v_ua); end if;

  v_ev := jsonb_build_object(
    'event_name', e.event_name,
    'event_time', extract(epoch from e.event_time)::bigint,
    'event_id', e.event_id,
    'action_source', s.action_source,
    'user_data', v_user,
    'custom_data', e.custom_data);

  if s.action_source = 'app' then
    v_app := jsonb_build_object(
      'advertiser_tracking_enabled', 1,
      'application_tracking_enabled', 1,
      'extinfo', jsonb_build_array('a2', s.app_package, '1.0', '1.0', '13', 'Android', 'en_IN', 'IST',
                                   '', '1080', '2400', '2.75', '8', '64', '32', 'Asia/Kolkata'));
    -- Installed from Google Play with a referrer (only the Play Store
    -- version has one): pass it on so Meta can match the ad click.
    if v_inst.referrer_status = 'ok' and coalesce(v_inst.raw_referrer, '') <> '' then
      v_app := v_app || jsonb_build_object(
        'install_referrer', v_inst.raw_referrer,
        'installer_package', 'com.android.vending');
    end if;
    v_ev := v_ev || jsonb_build_object('app_data', v_app);
  else
    v_ev := v_ev || jsonb_build_object('event_source_url',
      coalesce(v_click.page_url, s.website_url, 'https://example.com'));
  end if;
  return v_ev;
end $function$;
