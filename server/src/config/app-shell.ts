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
    id: 'support-center',
    label: 'Destek Merkezi',
    section: 'commerce',
    href: '/app/#support-center',
    description: 'Destek talepleri ve yanıt geçmişi.',
    module: 'portal',
    moduleTab: 'support'
  },
  {
    id: 'platform-companies',
    label: 'Platform Şirketleri',
    section: 'platform',
    href: '/app/#platform-companies',
    description: 'Tenant ve müşteri organizasyonlarını yönetin.',
    module: 'admin',
    moduleTab: 'companies',
    roles: ['sysadmin']
  },
  {
    id: 'platform-billing',
    label: 'Ödeme Operasyonları',
    section: 'platform',
    href: '/app/#platform-billing',
    description: 'Havale onayları, ödeme yöntemleri ve planlar.',
    module: 'admin',
    moduleTab: 'transfers',
    roles: ['sysadmin']
  },
  {
    id: 'platform-licenses',
    label: 'Lisans Yönetimi',
    section: 'platform',
    href: '/app/#platform-licenses',
    description: 'Şirket lisanslarını üretin, yenileyin ve askıya alın.',
    module: 'admin',
    moduleTab: 'licenses',
    roles: ['sysadmin']
  },
  {
    id: 'platform-health',
    label: 'Sistem Sağlığı',
    section: 'platform',
    href: '/app/#platform-health',
    description: 'Telemetri, güvenlik ve olay yönetimi.',
    module: 'admin',
    moduleTab: 'health',
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
  return APP_NAV_ITEMS.filter((item) => {
    const rolePass = !item.roles || item.roles.some((role) => roles.includes(role));
    const permissionPass = !item.permissions || item.permissions.some((permission) => permissions.includes(permission));
    return rolePass && permissionPass;
  });
}

export function resolveLandingRoute(roles: string[] = [], permissions: string[] = []) {
  if (roles.includes('sysadmin')) return '/app/#platform-companies';
  if (permissions.includes('billing:view')) return '/app/#billing-center';
  if (permissions.includes('devices:view')) return '/app/#company-dashboard';
  return '/app/#home';
}
