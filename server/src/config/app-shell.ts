export interface AppNavItem {
  id: string;
  label: string;
  section: 'overview' | 'operations' | 'commerce' | 'platform' | 'account';
  href: string;
  description: string;
  module: 'home' | 'portal' | 'admin';
  moduleTab?: string;
  permissions?: string[];
  roles?: string[];
}

export const APP_NAV_ITEMS: AppNavItem[] = [
  {
    id: 'workspace-home',
    label: 'Çalışma Alanı',
    section: 'overview',
    href: '/app/#home',
    description: 'Rolünüze uygun özet, kısayollar ve görev akışı.',
    module: 'home'
  },
  {
    id: 'company-dashboard',
    label: 'Firma Paneli',
    section: 'overview',
    href: '/app/#company-dashboard',
    description: 'Firma dashboard, cihaz, kullanıcı ve lisans görünümü.',
    module: 'portal',
    moduleTab: 'dashboard',
    permissions: ['devices:view']
  },
  {
    id: 'sales-operations',
    label: 'Satış ve Operasyon',
    section: 'operations',
    href: '/app/#sales-operations',
    description: 'Cihaz, şube ve operasyon durumları.',
    module: 'portal',
    moduleTab: 'devices',
    permissions: ['sales:view']
  },
  {
    id: 'company-stores',
    label: 'Şubeler',
    section: 'operations',
    href: '/app/#company-stores',
    description: 'Şube kayıtlarını, adreslerini ve durumlarını yönetin.',
    module: 'portal',
    moduleTab: 'stores'
  },
  {
    id: 'company-devices',
    label: 'Cihazlar',
    section: 'operations',
    href: '/app/#company-devices',
    description: 'Bağlı terminalleri, şubelerini ve çevrimiçi durumlarını izleyin.',
    module: 'portal',
    moduleTab: 'devices',
    permissions: ['devices:view']
  },
  {
    id: 'team-management',
    label: 'Kullanıcılar ve Roller',
    section: 'operations',
    href: '/app/#team-management',
    description: 'Alt kullanıcı yönetimi ve rol atamaları.',
    module: 'portal',
    moduleTab: 'users',
    permissions: ['users:manage']
  },
  {
    id: 'billing-center',
    label: 'Abonelik ve Faturalama',
    section: 'commerce',
    href: '/app/#billing-center',
    description: 'Planlar, faturalar ve ödeme akışları.',
    module: 'portal',
    moduleTab: 'subscription',
    permissions: ['billing:view']
  },
  {
    id: 'company-licenses',
    label: 'Lisanslar',
    section: 'commerce',
    href: '/app/#company-licenses',
    description: 'Lisans anahtarlarını, cihaz haklarını ve geçerlilik tarihlerini görün.',
    module: 'portal',
    moduleTab: 'licenses',
    permissions: ['devices:view']
  },
  {
    id: 'company-downloads',
    label: 'Uygulama İndir',
    section: 'commerce',
    href: '/app/#company-downloads',
    description: 'Yetkili Windows ve Android kurulum paketlerini indirin.',
    module: 'portal',
    moduleTab: 'downloads'
  },
  {
    id: 'support-center',
    label: 'Destek Merkezi',
    section: 'commerce',
    href: '/app/#support-center',
    description: 'Destek talepleri ve yanıt geçmişi.',
    module: 'portal',
    moduleTab: 'support'
  },
  {
    id: 'system-diagnostics',
    label: 'Sistem ve Loglar',
    section: 'operations',
    href: '/app/#system-diagnostics',
    description: 'Cihaz, senkronizasyon ve uygulama hatalarını inceleyin.',
    module: 'portal',
    moduleTab: 'diagnostics',
    roles: ['owner', 'admin', 'manager']
  },
  {
    id: 'platform-overview',
    label: 'Genel Bakış',
    section: 'platform',
    href: '/app/#platform-overview',
    description: 'Kayıt, deneme, abonelik, lisans ve havale özeti.',
    module: 'admin',
    moduleTab: 'commercial',
    roles: ['sysadmin']
  },
  {
    id: 'platform-companies',
    label: 'Firmalar',
    section: 'platform',
    href: '/app/#platform-companies',
    description: 'Tenant ve müşteri organizasyonlarını yönetin.',
    module: 'admin',
    moduleTab: 'companies',
    roles: ['sysadmin']
  },
  {
    id: 'platform-billing',
    label: 'Ödemeler',
    section: 'platform',
    href: '/app/#platform-billing',
    description: 'Havale onayları, ödeme yöntemleri ve planlar.',
    module: 'admin',
    moduleTab: 'transfers',
    roles: ['sysadmin']
  },
  {
    id: 'platform-subscriptions',
    label: 'Abonelikler',
    section: 'platform',
    href: '/app/#platform-subscriptions',
    description: 'Firma aboneliklerini, dönemlerini ve durumlarını inceleyin.',
    module: 'admin',
    moduleTab: 'subscriptions',
    roles: ['sysadmin']
  },
  {
    id: 'platform-plans',
    label: 'Planlar',
    section: 'platform',
    href: '/app/#platform-plans',
    description: 'Satış planlarını, limitleri ve fiyatları yönetin.',
    module: 'admin',
    moduleTab: 'plans',
    roles: ['sysadmin']
  },
  {
    id: 'platform-releases',
    label: 'Güncellemeler',
    section: 'platform',
    href: '/app/#platform-releases',
    description: 'Android ve Windows sürümlerini yayınlayın, kademeli dağıtın veya geri çekin.',
    module: 'admin',
    moduleTab: 'releases',
    roles: ['sysadmin']
  },
  {
    id: 'platform-licenses',
    label: 'Lisanslar',
    section: 'platform',
    href: '/app/#platform-licenses',
    description: 'Lisans üretin, yenileyin, askıya alın veya iptal edin.',
    module: 'admin',
    moduleTab: 'licenses',
    roles: ['sysadmin']
  },
  {
    id: 'platform-devices',
    label: 'Cihazlar',
    section: 'platform',
    href: '/app/#platform-devices',
    description: 'Tüm firmalara bağlı cihazları yönetin ve gerektiğinde değiştirin.',
    module: 'admin',
    moduleTab: 'devices',
    roles: ['sysadmin']
  },
  {
    id: 'platform-health',
    label: 'Sistem',
    section: 'platform',
    href: '/app/#platform-health',
    description: 'Telemetri, güvenlik ve olay yönetimi.',
    module: 'admin',
    moduleTab: 'health',
    roles: ['sysadmin']
  },
  {
    id: 'platform-maintenance',
    label: 'Sunucu Bakımı',
    section: 'platform',
    href: '/app/#platform-maintenance',
    description: 'Disk kullanımını inceleyin ve güvenli bakım görevlerini çalıştırın.',
    module: 'admin',
    moduleTab: 'maintenance',
    roles: ['sysadmin']
  },
  {
    id: 'platform-security',
    label: 'Güvenlik ve Loglar',
    section: 'platform',
    href: '/app/#platform-security',
    description: 'Admin şifreleri, güvenlik işlemleri ve sistem kayıtları.',
    module: 'admin',
    moduleTab: 'security',
    roles: ['sysadmin']
  },
  {
    id: 'platform-support',
    label: 'Destek',
    section: 'platform',
    href: '/app/#platform-support',
    description: 'Firmalardan gelen destek taleplerini görüntüleyin.',
    module: 'admin',
    moduleTab: 'support',
    roles: ['sysadmin']
  },
  {
    id: 'platform-mail',
    label: 'E-posta',
    section: 'platform',
    href: '/app/#platform-mail',
    description: 'Gelen ve gönderilen e-postaları yönetin.',
    module: 'admin',
    moduleTab: 'mail',
    roles: ['sysadmin']
  },
  {
    id: 'account-settings',
    label: 'Hesap Ayarları',
    section: 'account',
    href: '/app/#account-settings',
    description: 'Profil, şifre ve marka ayarları.',
    module: 'portal',
    moduleTab: 'settings',
    permissions: ['settings:view']
  }
];

export function filterNavByEntitlements(roles: string[] = [], permissions: string[] = []) {
  if (roles.includes('sysadmin')) {
    return APP_NAV_ITEMS.filter((item) => item.roles?.includes('sysadmin') || item.id === 'account-settings');
  }
  return APP_NAV_ITEMS.filter((item) => {
    const rolePass = !item.roles || item.roles.some((role) => roles.includes(role));
    const permissionPass = !item.permissions || item.permissions.some((permission) => permissions.includes(permission));
    return rolePass && permissionPass;
  });
}

export function resolveLandingRoute(roles: string[] = [], permissions: string[] = []) {
  const landingId = resolveLandingModuleId(roles, permissions);
  return APP_NAV_ITEMS.find((item) => item.id === landingId)?.href || '/app/#home';
}

export function resolveLandingModuleId(roles: string[] = [], permissions: string[] = []) {
  if (roles.includes('sysadmin')) return 'platform-overview';
  if (permissions.includes('billing:view')) return 'billing-center';
  if (permissions.includes('devices:view')) return 'company-dashboard';
  return 'workspace-home';
}
