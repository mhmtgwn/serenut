/* ==========================================================================
   SERENUT OS V2 - AUTH SERVICE
   ========================================================================= */

import { getAuthToken, clearAuthToken } from './api-client.js';

function getProfileStorageKey() {
  if (window.location.pathname.includes('/app')) {
    return 'app_profile';
  }
  return window.location.pathname.includes('/admin') ? 'admin_profile' : 'portal_profile';
}

/**
 * Checks if the user has an active session token
 * @returns {boolean}
 */
export function isAuthenticated() {
  return !!getAuthToken();
}

/**
 * Returns the parsed user profile stored in the session
 * @returns {object|null}
 */
export function getUserProfile() {
  try {
    const profile = sessionStorage.getItem(getProfileStorageKey()) || sessionStorage.getItem('app_profile');
    return profile ? JSON.parse(profile) : null;
  } catch (_) {
    return null;
  }
}

/**
 * Sets the user profile in session storage
 * @param {object} profile 
 */
export function setUserProfile(profile) {
  sessionStorage.setItem(getProfileStorageKey(), JSON.stringify(profile));
  if (window.location.pathname.includes('/app')) {
    sessionStorage.setItem('portal_profile', JSON.stringify(profile));
    sessionStorage.setItem('admin_profile', JSON.stringify(profile));
  }
}

/**
 * Checks if the authenticated user has a specific role
 * @param {string} role 
 * @returns {boolean}
 */
export function hasRole(role) {
  const profile = getUserProfile();
  const roles = profile?.roles || [];
  return roles.includes(role);
}

/**
 * Enforces authentication by redirecting to appropriate landing page if session invalid
 */
export function authGuard() {
  if (!isAuthenticated()) {
    clearAuthToken();
  }
}

/**
 * Enforces admin authorization by checking sysadmin role
 */
export function adminGuard() {
  authGuard();
  if (!hasRole('sysadmin')) {
    alert('Bu panele erişim yetkiniz bulunmamaktadır.');
    clearAuthToken();
  }
}
