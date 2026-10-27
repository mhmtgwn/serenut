export interface AppNavItem {
  id: string;
  label: string;
  subtabLabel?: string;
  parentId?: string;
  section: 'overview' | 'operations' | 'commerce' | 'customers' | 'communication' | 'security' | 'platform' | 'account';
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
    subtabLabel: 'Hızlı Kısayollar',
    parentId: 'company-dashboard',
    section: 'overview',
    href: '/app/#home',
    description: 'Rolünüze uygun özet, kısayollar ve görev akışı.',
    module: 'home'
  },
  {
    id: 'company-dashboard',
    label: 'Genel Bakış',
    subtabLabel: 'İşletme Özeti',
    section: 'overview',
    href: '/app/#company-dashboard',
    description: 'Kurulum rehberi, aktif paket, bağlı cihaz ve işletme özeti.',
    module: 'portal',
    moduleTab: 'dashboard',
    permissions: ['devices:view']
  },
  {
    id: 'sales-operations',
    label: 'SMS ve Operasyon',
    subtabLabel: 'SMS Ana Cihazı & Saha Özeti',
    parentId: 'notification-channels',
    section: 'operations',
    href: '/app/#sales-operations',
    description: 'SMS ana cihazı, şube ve terminal bağlantı özeti.',
    module: 'portal',
    moduleTab: 'devices',
    permissions: ['notifications.templates.manage'],
    roles: ['owner']
  },
  {
    id: 'company-devices',
    label: 'Cihazlar ve Şubeler',
    subtabLabel: 'Bağlı Cihazlar (Terminaller)',
    section: 'operations',
    href: '/app/#company-devices',
    description: 'Kasadaki bilgisayarları, mobil terminalleri ve mağaza şubelerinizi yönetin.',
    module: 'portal',
    moduleTab: 'devices',
    permissions: ['devices:view']
  },
  {
    id: 'company-stores',
    label: 'Şubeler',
    subtabLabel: 'Mağaza Şubeleri',
    parentId: 'company-devices',
    section: 'operations',
    href: '/app/#company-stores',
    description: 'Şube kayıtlarını, adreslerini ve durumlarını yönetin.',
    module: 'portal',
    moduleTab: 'stores',
    permissions: ['settings:manage']
  },
  {
    id: 'team-management',
    label: 'Ekip ve Yetkiler',
    section: 'operations',
    href: '/app/#team-management',
    description: 'Personel hesapları, şube görevleri ve özel rol yetkileri.',
    module: 'portal',
    moduleTab: 'users',
    permissions: ['users:manage']
  },
  {
    id: 'billing-center',
    label: 'Abonelik ve Faturalar',
    subtabLabel: 'Paketler ve Ödemeler',
    section: 'commerce',
    href: '/app/#billing-center',
    description: 'Paket yükseltme, kredi kartı / havale ödemeleri ve fatura geçmişi.',
    module: 'portal',
    moduleTab: 'subscription',
    permissions: ['billing:view']
  },
  {
    id: 'company-licenses',
    label: 'Lisanslar',
    subtabLabel: 'Lisans ve Cihaz Hakları',
    parentId: 'billing-center',
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
    description: 'Windows masaüstü (.exe) ve Android mobil (.apk) kurulum paketlerini indirin.',
    module: 'portal',
    moduleTab: 'downloads'
  },
  {
    id: 'notification-channels',
    label: 'WhatsApp ve SMS',
    subtabLabel: 'WhatsApp & SMS Ayarları',
    section: 'communication',
    href: '/app/#notification-channels',
    description: 'WhatsApp Web QR bağlantısını ve Android SMS ana cihazını yönetin.',
    module: 'portal',
    moduleTab: 'notifications',
    roles: ['owner']
  },
  {
    id: 'support-center',
    label: 'Destek Merkezi',
    subtabLabel: 'Destek Taleplerim',
    section: 'communication',
    href: '/app/#support-center',
    description: 'Destek talebi oluşturun ve teknik ekibimizle yazışmalarınızı takip edin.',
    module: 'portal',
    moduleTab: 'support'
  },
  {
    id: 'system-diagnostics',
    label: 'Sistem ve Loglar',
    subtabLabel: 'Teknik Tanılama ve Loglar',
    parentId: 'support-center',
    section: 'operations',
    href: '/app/#system-diagnostics',
    description: 'Cihaz, senkronizasyon ve uygulama kayıtlarını inceleyin.',
    module: 'portal',
    moduleTab: 'diagnostics',
    roles: ['owner', 'admin', 'manager']
  },
  {
    id: 'platform-overview',
    label: 'Genel Bakış',
    section: 'overview',
    href: '/app/#platform-overview',
    description: 'Canlı ticari metrikler, bekleyen havale onayları ve sunucu durumu.',
    module: 'admin',
    moduleTab: 'commercial',
    roles: ['sysadmin']
  },
  {
    id: 'platform-companies',
    label: 'Firmalar ve Lisanslar',
    subtabLabel: 'Firmalar (CRM)',
    section: 'customers',
    href: '/app/#platform-companies',
    description: 'Müşteri firmaları, özel paketleri, cihaz ve abonelik haklarını yönetin.',
    module: 'admin',
    moduleTab: 'companies',
    roles: ['sysadmin']
  },
  {
    id: 'platform-subscriptions',
    label: 'Abonelikler',
    subtabLabel: 'Tüm Abonelikler',
    parentId: 'platform-companies',
    section: 'customers',
    href: '/app/#platform-subscriptions',
    description: 'Firma aboneliklerini, dönemlerini ve durumlarını inceleyin.',
    module: 'admin',
    moduleTab: 'subscriptions',
    roles: ['sysadmin']
  },
  {
    id: 'platform-licenses',
    label: 'Lisanslar',
    subtabLabel: 'Lisans Anahtarları',
    parentId: 'platform-companies',
    section: 'customers',
    href: '/app/#platform-licenses',
    description: 'Lisans üretin, yenileyin, askıya alın veya iptal edin.',
    module: 'admin',
    moduleTab: 'licenses',
    roles: ['sysadmin']
  },
  {
    id: 'platform-billing',
    label: 'Ödemeler ve Paketler',
    subtabLabel: 'Havale Onayları & Tahsilat',
    section: 'commerce',
    href: '/app/#platform-billing',
    description: 'Bekleyen havale bildirimlerini onaylayın, banka IBAN ve iyzico ayarlarını yönetin.',
    module: 'admin',
    moduleTab: 'transfers',
    roles: ['sysadmin']
  },
  {
    id: 'platform-plans',
    label: 'Planlar',
    subtabLabel: 'Satış Paketleri ve Fiyatlar',
    parentId: 'platform-billing',
    section: 'commerce',
    href: '/app/#platform-plans',
    description: 'Satış planlarını, limitleri ve fiyatları yönetin.',
    module: 'admin',
    moduleTab: 'plans',
    roles: ['sysadmin']
  },
  {
    id: 'platform-releases',
    label: 'Sürümler ve Cihazlar',
    subtabLabel: 'Uygulama Sürümleri (OTA)',
    section: 'operations',
    href: '/app/#platform-releases',
    description: 'Windows ve Android sürümlerini yayınlayın ve bağlı terminalleri yönetin.',
    module: 'admin',
    moduleTab: 'releases',
    roles: ['sysadmin']
  },
  {
    id: 'platform-devices',
    label: 'Cihazlar',
    subtabLabel: 'Tüm Kayıtlı Cihazlar',
    parentId: 'platform-releases',
    section: 'customers',
    href: '/app/#platform-devices',
    description: 'Tüm firmalara bağlı cihazları yönetin ve gerektiğinde değiştirin.',
    module: 'admin',
    moduleTab: 'devices',
    roles: ['sysadmin']
  },
  {
    id: 'platform-support',
    label: 'Destek ve E-posta',
    subtabLabel: 'Destek Talepleri & Başvurular',
    section: 'communication',
    href: '/app/#platform-support',
    description: 'Müşteri destek taleplerini, ön başvuruları ve kurumsal e-postaları yönetin.',
    module: 'admin',
    moduleTab: 'support',
    roles: ['sysadmin']
  },
  {
    id: 'platform-mail',
    label: 'E-posta Kutusu',
    subtabLabel: 'Kurumsal E-posta Kutusu',
    parentId: 'platform-support',
    section: 'communication',
    href: '/app/#platform-mail',
    description: 'Gelen ve gönderilen e-postaları yönetin.',
    module: 'admin',
    moduleTab: 'mail',
    roles: ['sysadmin']
  },
  {
    id: 'platform-security',
    label: 'Sistem ve Güvenlik',
    subtabLabel: 'Güvenlik, Şifre ve Loglar',
    section: 'security',
    href: '/app/#platform-security',
    description: 'Yönetici şifresi, kurtarma kodları, hata logları ve sunucu bakımı.',
    module: 'admin',
    moduleTab: 'security',
    roles: ['sysadmin']
  },
  {
    id: 'platform-maintenance',
    label: 'Sunucu Bakımı',
    subtabLabel: 'Disk ve Sunucu Temizliği',
    parentId: 'platform-security',
    section: 'operations',
    href: '/app/#platform-maintenance',
    description: 'Disk kullanımını inceleyin ve güvenli bakım görevlerini çalıştırın.',
    module: 'admin',
    moduleTab: 'maintenance',
    roles: ['sysadmin']
  },
  {
    id: 'platform-health',
    label: 'Sistem',
    subtabLabel: 'Altyapı Sağlığı & Olaylar',
    parentId: 'platform-security',
    section: 'operations',
    href: '/app/#platform-health',
    description: 'Telemetri, servis sağlığı ve sistem olaylarını izleyin.',
    module: 'admin',
    moduleTab: 'health',
    roles: ['sysadmin']
  },
  {
    id: 'account-settings',
    label: 'Hesap ve Firma Ayarları',
    section: 'account',
    href: '/app/#account-settings',
    description: 'Şifre, kurtarma kodları, firma/fatura bilgileri ve aktif oturumlar.',
    module: 'portal',
    moduleTab: 'settings',
    permissions: ['settings:view']
  }
];

export function filterNavByEntitlements(roles: string[] = [], permissions: string[] = []) {
  if (roles.includes('sysadmin')) {
    return APP_NAV_ITEMS.filter((item) => item.roles?.includes('sysadmin'));
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
