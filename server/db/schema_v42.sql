UPDATE plans SET
  name = 'Başlangıç', price = 149.00, currency = 'TRY', billing_interval = 'monthly',
  features = '{"windows_devices":1,"android_devices":1,"users":4,"stores":1,"core_features":true}'::jsonb,
  device_limit = 2, store_limit = 1, user_limit = 4, is_active = true
WHERE id = 'plan-basic';

UPDATE plans SET
  name = 'Profesyonel', price = 399.00, currency = 'TRY', billing_interval = 'monthly',
  features = '{"windows_devices":3,"android_devices":3,"users":11,"stores":3,"core_features":true,"priority_support":true}'::jsonb,
  device_limit = 6, store_limit = 3, user_limit = 11, is_active = true
WHERE id = 'plan-pro';

UPDATE plans SET
  name = 'Kurumsal', currency = 'TRY', is_active = true,
  features = COALESCE(features, '{}'::jsonb) || '{"custom_quote":true,"core_features":true}'::jsonb
WHERE id = 'plan-enterprise';

UPDATE plans SET is_active = false WHERE id = 'plan-free';
